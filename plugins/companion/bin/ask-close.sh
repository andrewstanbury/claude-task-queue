#!/usr/bin/env bash
# ask-close.sh — PostToolUse[AskUserQuestion]: close the park that ask-guard opened, once the owner
# has actually ANSWERED. Claude-Code-only (hooks), added 2026-08-22 by owner request.
#
# THE PROBLEM IT COMPLETES. ask-guard now parks every question, not only the ones autopilot denies,
# because a recommendation the owner scrolls past or misses while typing elsewhere used to vanish
# with no record — and the work behind it went with it. Parking everything fixes the loss and
# creates a new one: an ANSWERED question would leave a stale ❓ behind, and a pile of stale parks
# trains the owner to ignore the pile, which is the same as having no pile.
#
# So: answered → the park goes. Missed, dismissed, or abandoned → the park stays and surfaces at the
# next session start and in /companion:review.
#
# MATCHING IS RECOMPUTED, NOT PASSED. This rebuilds the same subject prefix ask-guard wrote from the
# same `tool_input.questions`, so no id has to survive between two separate hook invocations. Same
# input, same string — and if the two ever drift, the failure is a stale park (visible, closable),
# never a closed park for an unanswered question.
#
# ERRS TOWARD LEAVING THE PARK. It closes only on POSITIVE evidence of an answer in `tool_response`.
# No response, an empty one, or anything it cannot read leaves the park alone: a stale ❓ costs the
# owner one glance, while wrongly closing one loses the decision — which is the whole thing this
# pair exists to prevent. Best-effort throughout (R68): it never fails the action that triggered it.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

in="$(cat 2>/dev/null || true)"
[ -n "$in" ] || exit 0
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$sid" ] || exit 0

# POSITIVE EVIDENCE ONLY. An absent or empty tool_response means we cannot tell an answer from a
# dismissal, and the safe reading of "cannot tell" is "leave it parked".
answered="$(printf '%s' "$in" | jq -r '
  (.tool_response // .tool_result // empty) | if . == null then empty else tostring end' 2>/dev/null || true)"
case "${answered:-}" in ''|'{}'|'[]'|null|'""') exit 0 ;; esac

cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(companion_root "$cwd")"
store="$(companion_tasks_dir "$root")/$sid"
[ -d "$store" ] || exit 0
_tq="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)/tq"
[ -x "$_tq" ] || exit 0

# Same subject shape ask-guard writes — one line per question.
# shellcheck disable=SC2016  # jq program: single quotes are required
subjects="$(printf '%s' "$in" | jq -r '
  (.tool_input.questions // [])[]
  | [ ("❓ [parked] decision: " + (.question // "a decision"))
      + " — options: " + ([ .options[]? | (.label // "") + (if (.description//"")!="" then " (" + .description + ")" else "" end) ] | join(" · "))
      + "; rec: " + ((.options[0].label // "the first option")) ]
  | @tsv' 2>/dev/null || true)"
[ -n "$subjects" ] || exit 0

while IFS= read -r subject; do
  [ -n "$subject" ] || continue
  subject="$(printf '%b' "$subject")"
  probe="${subject:0:120}"
  for f in "$store"/*.json; do
    [ -f "$f" ] || continue
    grep -qsF "$probe" "$f" 2>/dev/null || continue
    [ "$(jq -r '.status // ""' "$f" 2>/dev/null)" = pending ] || continue
    id="$(jq -r '.id // empty' "$f" 2>/dev/null)"
    [ -n "$id" ] || continue
    ( cd "$root" 2>/dev/null && CLAUDE_COMPANION_SESSION_ID="$sid" "$_tq" note "$id" "answered in session — park closed by ask-close.sh" >/dev/null 2>&1 ) || true
    ( cd "$root" 2>/dev/null && CLAUDE_COMPANION_SESSION_ID="$sid" "$_tq" cancel "$id" >/dev/null 2>&1 ) || true
    break
  done
done <<EOF
$subjects
EOF
exit 0
