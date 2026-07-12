#!/usr/bin/env bash
# UserPromptSubmit — side-effects only, no injection (the review loop is steering, not a
# per-prompt hook). Jobs for the gates:
#   1. Stash the prompt as the INTENT OF RECORD, and clear the `reminded` marker so the advisory
#      intent→outcome reminder (intent-note.sh) fires once on this request's first edit.
#   2. On a VISUAL prompt, arm the design-preview marker (work-guard blocks edits until a
#      wireframe is shown); clear it otherwise. Suppressed under autopilot (owner is away — no
#      outcome recap to show, no preview to present). Best-effort; disable CLAUDE_COMPANION_GATES=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_GATES:-1}" = "0" ] && exit 0
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
prompt="$(printf '%s' "$in" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0
case "$prompt" in '/'*|'!'*) exit 0 ;; esac                      # slash/bang aren't work
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"

# Under autopilot the owner is away — no intent recap, no preview. Don't arm the gates.
companion_autopilot_on "$root" && { rm -f "$(companion_design_flag "$sid")" "$(companion_reminded_flag "$sid")" 2>/dev/null || true; exit 0; }

# 1) intent of record — record it and re-arm the once-per-request reminder.
{ mkdir -p "$(companion_state_dir)" 2>/dev/null && printf '%s' "$prompt" > "$(companion_intent_file "$sid")"; } 2>/dev/null || true
rm -f "$(companion_reminded_flag "$sid")" 2>/dev/null || true
# 2) design-preview marker
if companion_looks_visual "$prompt"; then
  { mkdir -p "$(companion_state_dir)" 2>/dev/null && : > "$(companion_design_flag "$sid")"; } 2>/dev/null || true
else
  rm -f "$(companion_design_flag "$sid")" 2>/dev/null || true
fi
exit 0
