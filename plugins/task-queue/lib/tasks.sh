#!/usr/bin/env bash
# claude-task-queue (v0.4): support lib for the SessionStart "resume bridge".
#
# Claude Code's native task list is per-session working memory — a fresh session
# starts empty and can't see tasks an earlier session left unfinished. This lib
# backs bin/tq-resume.sh, which reads Claude Code's native task store and
# surfaces a repo's still-open tasks from earlier sessions so the model can
# re-adopt them.
#
# Claude Code persists every task the model creates (TaskCreate / TaskUpdate) as
# a JSON file under ~/.claude/tasks/<session-id>/<n>.json:
#   { "id", "subject", "description", "activeForm",
#     "status": "pending" | "in_progress" | "completed", "blocks", "blockedBy" }
#
# Read-only by principle: this never writes the native store. The model owns
# those tasks; we only read them. A task folder is keyed by session id; we map a
# session to its repo by reading the cwd from its transcript
# ~/.claude/projects/<enc-cwd>/<sid>.jsonl (immutable per session, so cached).

set -euo pipefail

# ---- locations (all overridable for tests) ---------------------------------

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
                  and ((.subject // "") | startswith("❓")))
           | (.subject // "")' "$f" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

# Open, non-parked WORK in this session's live queue: pending/in_progress tasks whose
# subject is NOT a ❓ parked item. This is the "is there real queue left to drain"
# signal that drives away/solo auto-continue — the Stop hook keeps the model working
# until this is empty (only ❓ parked items remain). Subjects, one per line, deduped.
tq_open_worklist() {
  local sid="$1" tdir f
  [ -n "$sid" ] || return 0
  tdir="$(tq_tasks_dir)/$sid"
  [ -d "$tdir" ] || return 0
  for f in "$tdir"/*.json; do
    [ -f "$f" ] || continue
    jq -r 'select((.status=="pending" or .status=="in_progress")
                  and ((.subject // "") | startswith("❓") | not))
           | (.subject // "")' "$f" 2>/dev/null || true
  done | awk 'NF && !seen[$0]++'
}

# (The standalone pause mode was folded into solo — see lib/away.sh. `solo`, run when
# the owner steps away, suppresses the approval loop the way pause used to, so there is
# no separate pause flag any more.)

# Agent-mode: an opt-in, per-repo flag (same scheme as away). When ON, the
# SessionStart policy permits fanning independent tasks out to subagents; OFF by
# default for token efficiency. Set with bin/tq-agent.sh.
tq_agent_dir()       { printf '%s' "${CLAUDE_TQ_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}"; }
tq_agent_file()      { printf '%s/%s' "$(tq_agent_dir)" "$(printf '%s' "$1" | sed 's:/:-:g')"; }
# Agent-mode is on when this repo has an explicit opt-in flag, OR the global
# default is on (CLAUDE_TQ_AGENT_MODE=on|1 — set once in settings.json env to
# enable everywhere without a per-repo decision). Off by default otherwise.
tq_is_agent_mode() {
  [ -n "${1:-}" ] || return 1
  [ -f "$(tq_agent_file "$1")" ] && return 0
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

# A cwd -> absolute project ROOT: the git repo toplevel. Falls back to the cwd
# itself when the session didn't run inside a repo (or the path is gone).
tq_root_for_cwd() {
  local cwd="$1" top dir
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; return 0; fi
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

# ---- resume bridge ----------------------------------------------------------

# Build the SessionStart "resume" note for a repo: OPEN (pending / in_progress)
# tasks from OTHER sessions rooted at the same repo as cur_root — work a previous
# session left unfinished — so a fresh session can re-adopt the relevant ones
# into its (otherwise empty) native task list.
#
# Kept short on purpose (it enters model context, every SessionStart): subjects
# only — all in_progress tasks, plus the most-recently-touched todos up to a cap,
# with a "…and N more" tail — followed by a pointer to the prior session folder
# where the FULL description + blockedBy of every task lives on disk. That pointer
# is how a crash-resume stays high-fidelity without inlining every description on
# every startup (which the token budget forbids); the model reads those files when
# it actually restores. Whole sessions untouched for longer than the age cutoff are
# skipped so abandoned backlogs stop resurrecting. De-duplicated by subject (newest
# mtime wins). Prints nothing when there is no qualifying carried-over work.
#
#   $1  cur_root  absolute repo root of the starting session
#   $2  cur_sid   the starting session's id (excluded: it has no tasks yet)
#
# Tunables (env): CLAUDE_TQ_RESUME_MAX (todos shown, default 7),
#                 CLAUDE_TQ_RESUME_MAX_AGE_DAYS (session age cutoff, default 14).
tq_resume_context() {
  local cur_root="$1" cur_sid="${2:-}"
  [ -n "$cur_root" ] || return 0
  local tdir sdir sid root f has newest m rows
  local max="${CLAUDE_TQ_RESUME_MAX:-7}"
  local days="${CLAUDE_TQ_RESUME_MAX_AGE_DAYS:-14}"
  local now cutoff
  now="$(date +%s 2>/dev/null || echo 0)"
  cutoff=$(( now - days * 86400 ))
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || return 0

  # Emit "status<TAB>mtime<TAB>subject" for every open task in a matching,
  # recently-active session.
  rows="$(
    for sdir in "$tdir"/*/; do
      [ -d "$sdir" ] || continue
      sid="$(basename "$sdir")"
      [ "$sid" = "$cur_sid" ] && continue
      has=0; newest=0
      for f in "$sdir"*.json; do
        [ -f "$f" ] || continue
        has=1; m="$(tq_mtime "$f")"; [ "$m" -gt "$newest" ] && newest="$m"
      done
      [ "$has" -eq 1 ] || continue
      [ "$newest" -ge "$cutoff" ] || continue          # skip stale sessions
      root="$(tq_session_root "$sid" 2>/dev/null || true)"
      [ "$root" = "$cur_root" ] || continue
      for f in "$sdir"*.json; do
        [ -f "$f" ] || continue
        m="$(tq_mtime "$f")"
        jq -r --arg m "$m" --arg d "$sdir" 'select(.status=="pending" or .status=="in_progress")
               | [.status, $m, (.subject // ""), $d] | @tsv' "$f" 2>/dev/null || true
      done
    done
  )"
  [ -n "$rows" ] || return 0

  # Dedup by subject (newest mtime wins), doing first, todos ranked by recency
  # and capped. One bullet per task; a tail counts whatever was trimmed.
  printf '%s\n' "$rows" | awk -F'\t' -v max="$max" '
    NF >= 3 {
      s=$3; mt=$2+0; d=$4
      if (!(s in mtime) || mt > mtime[s]) mtime[s]=mt
      if ($1=="in_progress") doing[s]=1
      if (mt > gmax) { gmax=mt; gdir=d }   # newest folder = the crash-resume target
    }
    END {
      dn=0; tn=0
      for (s in mtime) {
        if (s in doing) { dsub[dn++]=s }
        else { tsub[tn]=s; tmt[tn]=mtime[s]; tn++ }
      }
      n=dn+tn
      if (n==0) exit 0
      # sort todos by mtime desc (small n, simple selection sort)
      for (i=0;i<tn;i++) for (j=i+1;j<tn;j++)
        if (tmt[j] > tmt[i]) { x=tmt[i];tmt[i]=tmt[j];tmt[j]=x; y=tsub[i];tsub[i]=tsub[j];tsub[j]=y }
      shown = (tn > max ? max : tn)
      more  = tn - shown
      printf "%d open task%s carry over from an earlier session in this project — your native list starts empty each session, so this is the crash/restart safety net. If the user is continuing this work, REINSTATE them now with TaskCreate as your first action (restore any in-progress ones to in_progress and resume from the progress breadcrumb in each one'"'"'s description) before anything else; if they have clearly moved on, ignore this note.\n", n, (n==1?"":"s")
      for (i=0;i<dn;i++)    printf "  ⏳ %s\n", dsub[i]
      for (i=0;i<shown;i++) printf "  ◻ %s\n", tsub[i]
      if (more > 0) printf "  …and %d more todo%s.\n", more, (more==1?"":"s")
      # Subjects only above (the budget caps this block, and it fires every
      # SessionStart, not just crashes). The FULL description + blockedBy for each
      # task lives on disk in the prior session folder — point there so a restore
      # is high-fidelity without inlining every description on every startup.
      if (gdir != "") printf "Full description + blockedBy for each is on disk at %s*.json — read those before recreating so restored tasks keep their detail and dependencies (this is also where the %d above and any not listed all live).\n", gdir, n
    }'
}
