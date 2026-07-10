#!/usr/bin/env bash
# task-queue — support lib: away-mode state + the return-digest.
#
# Away-mode = the owner stepped away from the keyboard, so the model runs fully
# autonomous and PARKS anything needing them (see bin/tq-resume.sh's AWAY block).
# Kept in its own unit so lib/tasks.sh stays focused on the native task store;
# these helpers depend on that lib (tq_tasks_dir / tq_session_root / tq_mtime) at
# call time, so it must be sourced alongside this one. Sourced by bin/tq-away.sh
# and bin/tq-resume.sh.

set -uo pipefail

# Per-repo flag (same scheme as agent). No global env default: a machine-wide
# "never ask me" is a footgun, so away is always a deliberate, visible, per-repo toggle.
tq_away_dir()  { printf '%s' "${CLAUDE_TQ_AWAY_DIR:-$HOME/.claude/state/task-queue/away}"; }
tq_away_file() { printf '%s/%s' "$(tq_away_dir)" "$(tq_enc_root "$1")"; }
tq_is_away()   { [ -n "${1:-}" ] && [ -f "$(tq_away_file "$1")" ]; }

# --- owner-present marker: autopilot ≠ absent --------------------------------
# Away/autopilot means the owner DECLARED they stepped away, so the queue drains
# autonomously and asks are parked. But a PROMPT is proof they're back at the
# keyboard for THAT turn — otherwise a note dropped mid-autopilot traps the session
# in "can't ask you, keep parking" (the loop this fixes). So tq-capture stamps a
# per-session presence marker on each prompt; the ask-guard and capture loop consult
# it to keep the OWNER-DRIVEN turn interactive, while the autonomous drain that
# follows (tq-verify clears the marker on entering auto-continue) still parks.
# Filenames are `present-<sid>`, never colliding with the repo-root away flags
# (which encode an absolute path, always starting with '-'). Self-expiring after
# CLAUDE_TQ_PRESENT_WINDOW seconds as a backstop if the Stop-clear never runs
# (auto-continue disabled, or a crash), so a stale marker can't defeat away. Set the
# window to 0 for lights-out autopilot: even the owner's own prompts stay autonomous.
tq_present_window()    { printf '%s' "${CLAUDE_TQ_PRESENT_WINDOW:-1800}"; }
tq_away_present_file() { printf '%s/present-%s' "$(tq_away_dir)" "${1:-nosession}"; }

tq_mark_present() {
  [ -n "${1:-}" ] || return 0
  mkdir -p "$(tq_away_dir)" 2>/dev/null || true
  date +%s > "$(tq_away_present_file "$1")" 2>/dev/null || true
}
tq_clear_present() { [ -n "${1:-}" ] || return 0; rm -f "$(tq_away_present_file "$1")" 2>/dev/null || true; }

# True when the owner submitted a prompt recently in this session (marker fresh).
tq_owner_present() {
  local f stamp now win
  [ -n "${1:-}" ] || return 1
  f="$(tq_away_present_file "$1")"
  [ -f "$f" ] || return 1
  stamp="$(head -n1 "$f" 2>/dev/null | tr -dc '0-9' || true)"
  [ -n "$stamp" ] || return 1
  now="$(date +%s)"; win="$(tq_present_window)"
  [ "$((now - stamp))" -lt "$win" ]
}

# The canonical autopilot PARK-vs-DECIDE rule — the single source of truth for what an
# away/autopilot session parks for the owner vs. decides itself. Emitted once here and
# composed into all three park-guidance surfaces (the ask-guard deny, the SessionStart
# away banner in signals.sh, and the Stop auto-continue in tq-verify.sh), so a threshold
# change is a ONE-line edit here, not five hand-copied strings. The test is what a wrong
# call would COST to undo, not mere uncertainty. Kept lean — every caller carries a
# per-event token budget (tests/token-budget.bats).
tq_park_rule() {
  printf '%s' "PARK what needs the owner, TAGGED by kind. A DECISION they must make — a direction/design/structural choice, a new dependency or interface/data-model change, an ambiguous high-blast-radius fork, or approving anything irreversible/externally-binding — as a '❓ [parked] <what to decide + your rec>' task. A manual ACTION only they can do — a device, an external/paid service, an owner-only test, a step you can't run here — as a '⏳ [blocked] <what they must do>' task (⏳ items don't hold the review gate; the queue drains around them and they resurface when unblocked). Decide the routine, low-stakes rest yourself (recommended option, noted). A human PLAYTEST is the ONE check you do NOT park or stop for (a game's feel/visuals you can't run): finish the work, mark it DONE with a 'playtest pending' note, and KEEP DRAINING. NEVER STALL on the absent owner: if an unparkable decision blocks all progress, take your recommended safest-reversible default, record it, and drop a '❓' note to override."
}

# Epoch when away-mode was turned on for this repo (the flag file holds it), or 0.
# Used for the staleness nudge (how long away) and the return-digest (what changed
# since). Robust to an empty/legacy flag file (prints 0).
tq_away_since() {
  local f v
  [ -n "${1:-}" ] || { printf '0'; return 0; }
  f="$(tq_away_file "$1")"
  [ -f "$f" ] || { printf '0'; return 0; }
  v="$(head -n1 "$f" 2>/dev/null | tr -dc '0-9' || true)"
  printf '%s' "${v:-0}"
}

# --- return-review gate: enforce "clear the parked pile before new work" -------
# When autopilot turns OFF with a parked ❓ DECISION pile, tq-away.sh sets a per-repo
# review-pending marker; the PreToolUse guard (bin/tq-review-guard.sh) then BLOCKS
# edits until every parked ❓ is resolved, so the owner reviews what autopilot
# decided before more code lands — the enforced backing for tq_away_digest's "review
# these first" instruction. Only ❓ decisions arm/hold the gate; ⏳ [blocked]
# owner-action items are informational (surfaced, not gated) so editing isn't frozen
# on a manual step. Same per-repo flag scheme as away; lives in the away dir.
# (`review-` prefix never collides with the away flags, which encode an absolute path
# via tq_enc_root and so start with `%2F`, nor the `present-<sid>` markers.)
tq_review_file()    { printf '%s/review-%s' "$(tq_away_dir)" "$(tq_enc_root "${1:-}")"; }
tq_review_set()     { [ -n "${1:-}" ] || return 0; mkdir -p "$(tq_away_dir)" 2>/dev/null || true; : > "$(tq_review_file "$1")" 2>/dev/null || true; }
tq_review_clear()   { [ -n "${1:-}" ] || return 0; rm -f "$(tq_review_file "$1")" 2>/dev/null || true; }
tq_review_pending() { [ -n "${1:-}" ] && [ -f "$(tq_review_file "$1")" ]; }

# Does this repo still have any open parked ❓ DECISION across its RECENTLY-ACTIVE
# sessions? Returns 0 (yes) on the FIRST match — the guard only needs presence, not a
# count — else 1. ⏳ [blocked] owner-action items are deliberately NOT counted here:
# they don't hold the return-review gate. Sessions untouched since the age cutoff are
# SKIPPED (same staleness rule as the resume bridge, CLAUDE_TQ_RESUME_MAX_AGE_DAYS):
# without it, a session that armed the review marker on `autopilot off` and then
# crashed/quit with an unresolved ❓ would hold the edit gate FOREVER, in every future
# session for this repo, with nothing the live session can resolve (the ❓ lives in the
# dead session's folder, unreachable by TaskUpdate). The cutoff lets an abandoned pile
# age out so editing can't be locked repo-wide indefinitely. Depends on lib/tasks.sh
# (tq_tasks_dir/tq_session_root/tq_mtime), sourced alongside.
tq_repo_has_parked() {
  local cur_root="${1:-}" tdir sdir sid f newest m now cutoff days
  [ -n "$cur_root" ] || return 1
  tdir="$(tq_tasks_dir)"; [ -d "$tdir" ] || return 1
  days="${CLAUDE_TQ_RESUME_MAX_AGE_DAYS:-14}"
  now="$(date +%s 2>/dev/null || echo 0)"; cutoff=$(( now - days * 86400 ))
  for sdir in "$tdir"/*/; do
    [ -d "$sdir" ] || continue
    sid="$(basename "$sdir")"
    [ "$(tq_session_root "$sid" 2>/dev/null || true)" = "$cur_root" ] || continue
    newest=0
    for f in "$sdir"*.json; do
      [ -f "$f" ] || continue
      m="$(tq_mtime "$f")"; [ "$m" -gt "$newest" ] && newest="$m"
    done
    [ "$newest" -ge "$cutoff" ] || continue          # abandoned pile → stop holding the gate
    for f in "$sdir"*.json; do
      [ -f "$f" ] || continue
      jq -e '(.status=="pending" or .status=="in_progress") and '"$TQ_JQ_PARKED" \
        "$f" >/dev/null 2>&1 && return 0
    done
  done
  return 1
}

# Return-digest: what happened for cur_root while the owner was away (since epoch
# `since`) — tasks COMPLETED since then, OPEN ❓ DECISIONS still awaiting a call, and
# ⏳ [blocked] items waiting on a manual owner action, across sessions rooted at this
# repo. Printed by tq-away.sh on "off" (the explicit "I'm back"). Counts + up to 3
# completed subjects; ALL ❓ subjects listed in full (each carries its recommendation)
# so "off" is itself the review checkpoint — the owner decides the ❓ pile here before
# the queue resumes; ⏳ items are listed as "do these when you can" (they don't gate
# editing). One line when nothing changed.
tq_away_digest() {
  local cur_root="$1" since="${2:-0}"
  [ -n "$cur_root" ] || return 0
  local tdir sdir sid root f m done_n park_n block_n open_n subj shown parked blocked open_show
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || return 0
  done_n=0; park_n=0; block_n=0; open_n=0; shown=""; parked=""; blocked=""; open_show=""
  for sdir in "$tdir"/*/; do
    [ -d "$sdir" ] || continue
    sid="$(basename "$sdir")"
    root="$(tq_session_root "$sid" 2>/dev/null || true)"
    [ "$root" = "$cur_root" ] || continue
    for f in "$sdir"*.json; do
      [ -f "$f" ] || continue
      if jq -e '.status=="completed"' "$f" >/dev/null 2>&1; then
        m="$(tq_mtime "$f")"
        if [ "$m" -ge "$since" ]; then
          done_n=$((done_n + 1))
          subj="$(jq -r '.subject // ""' "$f" 2>/dev/null || true)"
          [ -n "$subj" ] && [ "$(printf '%s\n' "$shown" | grep -c .)" -lt 3 ] \
            && shown="$shown"$'\n'"  ✓ $subj"
        fi
      elif jq -e '(.status=="pending" or .status=="in_progress") and '"$TQ_JQ_PARKED" "$f" >/dev/null 2>&1; then
        park_n=$((park_n + 1))
        subj="$(jq -r '.subject // ""' "$f" 2>/dev/null || true)"
        [ -n "$subj" ] && parked="$parked"$'\n'"  $subj"
      elif jq -e '(.status=="pending" or .status=="in_progress") and '"$TQ_JQ_BLOCKED" "$f" >/dev/null 2>&1; then
        block_n=$((block_n + 1))
        subj="$(jq -r '.subject // ""' "$f" 2>/dev/null || true)"
        [ -n "$subj" ] && blocked="$blocked"$'\n'"  $subj"
      elif jq -e '.status=="pending" or .status=="in_progress"' "$f" >/dev/null 2>&1; then
        # Open + NOT deferred = real work the drain left unfinished (e.g. it hit the
        # per-prompt continue cap). Surfacing this is the anti-blind-stall guarantee.
        open_n=$((open_n + 1))
        subj="$(jq -r '.subject // ""' "$f" 2>/dev/null || true)"
        [ -n "$subj" ] && [ "$(printf '%s\n' "$open_show" | grep -c .)" -lt 3 ] \
          && open_show="$open_show"$'\n'"  • $subj"
      fi
    done
  done
  if [ "$done_n" -eq 0 ] && [ "$park_n" -eq 0 ] && [ "$block_n" -eq 0 ] && [ "$open_n" -eq 0 ]; then
    printf 'While you were away: nothing recorded as completed, and nothing waiting on you.\n'
    return 0
  fi
  printf 'While you were away: %d task(s) completed, %d ❓ to decide, %d ⏳ waiting on you, %d still queued.\n' "$done_n" "$park_n" "$block_n" "$open_n"
  [ -n "$shown" ] && printf '%s\n' "${shown#$'\n'}"
  if [ "$open_n" -gt 0 ]; then
    printf 'STILL QUEUED — %d task(s) NOT finished (autopilot did not drain the whole queue — likely the per-prompt continue cap). Do NOT assume the work is done; pick these up:\n' "$open_n"
    printf '%s\n' "${open_show#$'\n'}"
    [ "$open_n" -gt 3 ] && printf '  …and %d more (see the task list)\n' "$((open_n - 3))"
  fi
  if [ "$park_n" -gt 0 ]; then
    printf 'Decisions to review FIRST (each carries a recommendation):\n'
    printf '%s\n' "${parked#$'\n'}"
    printf 'Present each to the owner NOW the design-preview way — a blocking AskUserQuestion offering 2-3 concrete options with your recommended one first (labelled "(Recommended)"), so they pick rather than face an open prose question — and apply their choice BEFORE pulling any new queue work; resolve/clear each ❓ (TaskUpdate) as you go. This is ENFORCED: editing code is BLOCKED until the ❓ pile is empty. Re-enabling autopilot resumes the rest of the queue. (Also in hud as ❓%d.)\n' "$park_n"
  fi
  if [ "$block_n" -gt 0 ]; then
    printf 'Waiting on a manual action from you (the queue drains AROUND these — they do NOT block editing, and resurface when unblocked):\n'
    printf '%s\n' "${blocked#$'\n'}"
    printf 'Relay these so the owner knows what only they can unblock (device, external/paid service, owner-only test, an action you cannot run). Leave each ⏳ as-is; drop the ⏳ (TaskUpdate → normal queued task) only once the blocker is actually cleared. (Also in hud as ⏳%d.)\n' "$block_n"
  fi
}
