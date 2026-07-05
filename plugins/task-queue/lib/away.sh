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
tq_away_file() { printf '%s/%s' "$(tq_away_dir)" "$(printf '%s' "$1" | sed 's:/:-:g')"; }
tq_is_away()   { [ -n "${1:-}" ] && [ -f "$(tq_away_file "$1")" ]; }

# The canonical autopilot PARK-vs-DECIDE rule — the single source of truth for what an
# away/autopilot session parks for the owner vs. decides itself. Emitted once here and
# composed into all three park-guidance surfaces (the ask-guard deny, the SessionStart
# away banner in signals.sh, and the Stop auto-continue in tq-verify.sh), so a threshold
# change is a ONE-line edit here, not five hand-copied strings. The test is what a wrong
# call would COST to undo, not mere uncertainty. Kept lean — every caller carries a
# per-event token budget (tests/token-budget.bats).
tq_park_rule() {
  printf '%s' "PARK the decisions the owner will want — an important direction or design/structural choice, a new dependency or interface/data-model change, an ambiguous high-blast-radius fork, anything irreversible or externally-binding (delete, push, send, spend), or a check you cannot run — as a '❓ [parked] <what needs deciding — with your recommendation>' task; decide the routine, low-stakes rest yourself (recommended option, noted)."
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

# Return-digest: what happened for cur_root while the owner was away (since epoch
# `since`) — tasks COMPLETED since then and OPEN ❓ items still awaiting them, across
# sessions rooted at this repo. Printed by tq-away.sh on "off" (the explicit "I'm
# back"). Counts + up to 3 completed subjects; one line when nothing changed.
tq_away_digest() {
  local cur_root="$1" since="${2:-0}"
  [ -n "$cur_root" ] || return 0
  local tdir sdir sid root f m done_n park_n subj shown
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || return 0
  done_n=0; park_n=0; shown=""
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
      elif jq -e '(.status=="pending" or .status=="in_progress") and ((.subject//"")|startswith("❓"))' "$f" >/dev/null 2>&1; then
        park_n=$((park_n + 1))
      fi
    done
  done
  if [ "$done_n" -eq 0 ] && [ "$park_n" -eq 0 ]; then
    printf 'While you were away: nothing recorded as completed, and no parked items to review.\n'
    return 0
  fi
  printf 'While you were away: %d task(s) completed, %d ❓ parked for your review.\n' "$done_n" "$park_n"
  [ -n "$shown" ] && printf '%s\n' "${shown#$'\n'}"
  [ "$park_n" -gt 0 ] && printf 'The parked items re-surface on your next prompt (and show in hud as ❓%d).\n' "$park_n"
}
