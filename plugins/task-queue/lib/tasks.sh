#!/usr/bin/env bash
# claude-task-queue: support lib for the SessionStart "resume bridge" + live-queue
# queries. The native task list is per-session working memory (a fresh session can't
# see an earlier one's unfinished tasks); this reads Claude Code's store to re-surface
# and classify them. Claude Code persists each TaskCreate/TaskUpdate as a JSON file at
# ~/.claude/tasks/<session-id>/<n>.json ({ id, subject, activeForm, status:
# pending|in_progress|completed, blocks, blockedBy }). READ-ONLY by principle — the
# model owns those tasks. A folder is keyed by session id; we map a session to its repo
# via its transcript ~/.claude/projects/<enc-cwd>/<sid>.jsonl (immutable, so cached).

set -euo pipefail

# ---- locations (all overridable for tests) ---------------------------------

# Injective encoding of an absolute repo ROOT into one filename component, for the
# per-repo flag files (away / agent / review) keyed by root. Percent-encodes '/' (after
# escaping any literal '%'), so distinct roots NEVER collide — the old '/'→'-' scheme
# mapped e.g. /a/foo-bar and /a/foo/bar to the SAME key, silently SHARING autopilot/agent/
# review state across two unrelated repos. NOT backward-compatible: a flag written under
# the old scheme is orphaned (the mode reads off until re-toggled) — a deliberate one-time
# reset. hud mirrors this exactly (hud_enc_root); drift-guard.bats asserts they agree.
# (Session-keyed markers — intent/design/present/verify/away-continue — stay '/'→'-':
# a session id has no '/', so it can't collide; only path-keyed flags needed the change.)
tq_enc_root() { printf '%s' "${1:-}" | sed -e 's:%:%25:g' -e 's:/:%2F:g'; }

tq_tasks_dir()       { printf '%s' "${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}"; }
tq_projects_dir()    { printf '%s' "${CLAUDE_TQ_PROJECTS_DIR:-$HOME/.claude/projects}"; }
tq_state_dir()       { printf '%s' "${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"; }
tq_root_cache_file() { printf '%s/root-cache.tsv' "$(tq_state_dir)"; }

# Intent of record for the intent→outcome gate: the latest SUBSTANTIVE prompt,
# stashed by tq-capture (UserPromptSubmit) and replayed by tq-verify (Stop) to
# check the finished change against what the owner actually asked. Per session;
# lives in the state dir (both hooks share CLAUDE_TQ_STATE_DIR=CLAUDE_PLUGIN_DATA).
tq_intent_file()     { printf '%s/intent-%s' "$(tq_state_dir)" "$(printf '%s' "${1:-nosession}" | sed 's:/:-:g')"; }

# Per-prompt safety counter for away/solo auto-continue: bounds how many times the
# Stop hook may re-continue the queue on its own before yielding, so a stuck model
# can't spin forever burning tokens. Lives beside the intent file (same state dir,
# both hooks share it); reset by tq-capture on each new prompt (fresh budget per ask).
tq_away_continue_file() { printf '%s/away-continue-%s' "$(tq_state_dir)" "$(printf '%s' "${1:-nosession}" | sed 's:/:-:g')"; }

# ---- deferred-marker predicates (single source of truth) --------------------
# DEFERRED = subject leads with `❓ [parked]` (a DECISION; holds the review gate) or
# `⏳ [blocked]` (WAITING ON AN OWNER ACTION). Neither drains — this is the load-bearing
# stall/spin boundary, so it lives ONCE and tolerates leading whitespace (`sub("^\\s+";"")`)
# so a stray space can't flip a parked item into "work". Spliced into select() via `'"$VAR"'`.
TQ_JQ_PARKED='((.subject // "") | sub("^\\s+";"") | startswith("❓"))'
TQ_JQ_BLOCKED='((.subject // "") | sub("^\\s+";"") | startswith("⏳"))'
TQ_JQ_DEFERRED="($TQ_JQ_PARKED or $TQ_JQ_BLOCKED)"

# Open QUESTIONS the user still owes an answer on (so a new prompt doesn't bury
# them). Modelled as native tasks whose subject is marked with a leading "❓": the
# model creates one with TaskCreate when it leaves an answer-worthy question
# hanging, and marks it completed once the user answers or drops it. Lists the
# subject of each pending/in_progress ❓ task for the GIVEN session (this
# conversation), deduped by subject. Empty when none / no session / no store.
tq_open_questions() {
  local sid="$1" tdir f
  [ -n "$sid" ] || return 0
  tdir="$(tq_tasks_dir)/$sid"
  [ -d "$tdir" ] || return 0
  for f in "$tdir"/*.json; do
    [ -f "$f" ] || continue
    jq -r 'select((.status=="pending" or .status=="in_progress")
                  and '"$TQ_JQ_PARKED"')
           | (.subject // "")' "$f" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

# Open, non-parked WORK in this session's live queue: pending/in_progress tasks that
# are NOT deferred — neither a ❓ [parked] decision NOR a ⏳ [blocked] owner-action item
# (both wait on the owner, so neither is drainable). This is the "is there real queue
# left to drain" signal that drives away/solo auto-continue — the Stop hook keeps the
# model working until this is empty (only ❓/⏳ items remain, which it can't action
# alone). Subjects, one per line, deduped.
tq_open_worklist() {
  local sid="$1" tdir f
  [ -n "$sid" ] || return 0
  tdir="$(tq_tasks_dir)/$sid"
  [ -d "$tdir" ] || return 0
  for f in "$tdir"/*.json; do
    [ -f "$f" ] || continue
    jq -r 'select((.status=="pending" or .status=="in_progress")
                  and ('"$TQ_JQ_DEFERRED"' | not))
           | (.subject // "")' "$f" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

# Tasks READY to start now in this session: pending, non-deferred (not ❓/⏳) tasks whose every blockedBy
# is already completed (or that have none) — the independent, unblocked candidates the
# capture hook offers for parallel subagent fan-out when agent-mode is on. It does the
# dependency analysis (the hard part); the model still makes the Task calls, since no
# hook can spawn agents. Prints one subject per ready task, deduped; empty when none.
tq_ready_tasks() {
  local sid="$1" tdir f bb blocker bstat ready
  [ -n "$sid" ] || return 0
  tdir="$(tq_tasks_dir)/$sid"
  [ -d "$tdir" ] || return 0
  for f in "$tdir"/*.json; do
    [ -f "$f" ] || continue
    jq -e 'select(.status=="pending" and ('"$TQ_JQ_DEFERRED"' | not))' \
      "$f" >/dev/null 2>&1 || continue
    ready=1
    bb="$(jq -r '.blockedBy[]? // empty' "$f" 2>/dev/null || true)"
    if [ -n "$bb" ]; then
      while IFS= read -r blocker; do
        [ -n "$blocker" ] || continue
        bstat="$(jq -r '.status // ""' "$tdir/$blocker.json" 2>/dev/null || true)"
        [ "$bstat" = "completed" ] || { ready=0; break; }
      done <<< "$bb"
    fi
    [ "$ready" -eq 1 ] || continue
    jq -r '.subject // ""' "$f" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

# (The standalone pause mode was folded into solo — see lib/away.sh. `solo`, run when
# the owner steps away, suppresses the approval loop the way pause used to, so there is
# no separate pause flag any more.)

# Agent-mode: an opt-in, per-repo flag (same scheme as away). When ON, the
# SessionStart policy permits fanning independent tasks out to subagents; OFF by
# default for token efficiency. Set with bin/tq-agent.sh.
tq_agent_dir()       { printf '%s' "${CLAUDE_TQ_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}"; }
tq_agent_file()      { printf '%s/%s' "$(tq_agent_dir)" "$(tq_enc_root "$1")"; }
# Agent-mode is on when this repo has an explicit opt-in flag, OR the global
# default is on (CLAUDE_TQ_AGENT_MODE=on|1 — set once in settings.json env to
# enable everywhere without a per-repo decision). Off by default otherwise. A flag
# whose content is the literal "off" is a TOMBSTONE: it lets /task-queue:agents turn
# a single repo off even when the global default would otherwise enable it.
tq_is_agent_mode() {
  [ -n "${1:-}" ] || return 1
  local f; f="$(tq_agent_file "$1")"
  if [ -f "$f" ]; then [ "$(cat "$f" 2>/dev/null || true)" != "off" ]; return; fi
  case "${CLAUDE_TQ_AGENT_MODE:-}" in on|1) return 0 ;; esac
  return 1
}

# (Away-mode state + the return-digest — tq_away_since / tq_away_digest — live in
# lib/away.sh, sourced alongside this by every away consumer, so tasks.sh stays
# focused on the native task store.)

# ---- drift canary -----------------------------------------------------------

# Sample real task files and report whether they still match the schema we read
# (see CONTRACT.md). This is how a never-reviewed install notices Claude Code
# changing the store format — the SessionStart hook warns when it returns drift.
#   "ok"    a sampled file has the expected id + status fields
#   "drift" a file exists but is missing them — our parsing is out of date
#   "empty" no task files to check (says nothing about the schema)
tq_schema_status() {
  local tdir f sample=0
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || { printf 'empty'; return 0; }
  for f in "$tdir"/*/*.json; do
    [ -f "$f" ] || continue
    sample=$((sample + 1))
    jq -e 'has("id") and has("status")' "$f" >/dev/null 2>&1 || { printf 'drift'; return 0; }
    [ "$sample" -ge 25 ] && break
  done
  [ "$sample" -gt 0 ] && printf 'ok' || printf 'empty'
}

# ---- helpers ----------------------------------------------------------------

# Portable mtime (seconds). GNU stat then BSD/macOS stat then 0.
tq_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

# A cwd -> absolute project ROOT: git toplevel, normalized to the PRIMARY worktree (git-common-dir's
# parent) so a linked worktree keys the same flags/tasks as the main checkout. hud mirrors this exactly.
# A SUBMODULE's common-dir is <super>/.git/modules/<name>, whose parent lands INSIDE .git — not a
# working root, and shared across sibling submodules (they'd collide to one flag key). Detect that
# (resolved parent under a .git dir) and fall back to the submodule's own --show-toplevel.
tq_root_for_cwd() {
  local cwd="$1" top dir gcd
  gcd="$(git -C "$cwd" rev-parse --git-common-dir 2>/dev/null || true)"
  if [ -n "$gcd" ]; then
    top="$(cd "$cwd" 2>/dev/null && cd "$(dirname "$gcd")" 2>/dev/null && pwd)"
    case "$top" in */.git|*/.git/*) top="" ;; esac   # submodule/gitdir-inside-.git → not a real root
    [ -n "$top" ] || top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    [ -n "$top" ] && { printf '%s' "$top"; return 0; }
  fi
  dir="$cwd"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/.git" ] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  printf '%s' "$cwd"
}

# (Project-doc detection — tq_policy_documented, tq_roadmap_path — lives in
# lib/project.sh, sourced by bin/tq-resume.sh, to keep this file focused on the
# native task store.)

# session id -> absolute repo root. Cached (a session's cwd never changes).
# Returns non-zero and prints nothing when the transcript or its cwd can't be
# resolved (e.g. the session's transcript hasn't been written yet).
tq_session_root() {
  local sid="$1" cache root transcript cwd pdir f
  cache="$(tq_root_cache_file)"

  if [ -f "$cache" ]; then
    root="$(awk -F'\t' -v s="$sid" '$1==s {print $2; exit}' "$cache" 2>/dev/null || true)"
    [ -n "$root" ] && { printf '%s' "$root"; return 0; }
  fi

  pdir="$(tq_projects_dir)"
  transcript=""
  for f in "$pdir"/*/"$sid.jsonl"; do
    [ -f "$f" ] && { transcript="$f"; break; }
  done
  [ -n "$transcript" ] || return 1

  cwd="$(head -n 40 "$transcript" 2>/dev/null | jq -r 'select(.cwd != null) | .cwd' 2>/dev/null | head -n1 || true)"
  [ -n "$cwd" ] || return 1
  root="$(tq_root_for_cwd "$cwd")"
  [ -n "$root" ] || return 1

  mkdir -p "$(tq_state_dir)" 2>/dev/null || true
  printf '%s\t%s\n' "$sid" "$root" >> "$cache" 2>/dev/null || true
  printf '%s' "$root"
}

# (The SessionStart "resume bridge" — tq_resume_context — lives in lib/resume.sh,
# sourced after this file by its only consumers (bin/tq-resume.sh, bin/tq-restore.sh),
# so the per-prompt hot path (the guards + tq-capture) doesn't parse a builder it never
# calls and this file stays under the size budget.)
