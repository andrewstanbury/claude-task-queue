#!/usr/bin/env bash
# PostToolUse[Write|Edit] — the intent→outcome reminder (R27), ADVISORY. On the FIRST edit after
# a prompt, surface the recorded intent as context (no block, no extra turn) so the model checks
# the outcome against it and recaps in one line when done — while it's still working, not after.
# Fires once per request: a `reminded-<sid>` marker that prompt.sh clears on each new prompt.
# Silent under autopilot, when nothing is recorded, or after it has already fired this request.
# Best-effort + non-blocking. Disable: CLAUDE_COMPANION_GATES=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_GATES:-1}" = "0" ] && exit 0
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"
companion_autopilot_on "$root" && exit 0          # away → no recap to show anyone

intent_f="$(companion_intent_file "$sid")"; [ -f "$intent_f" ] || exit 0
reminded="$(companion_reminded_flag "$sid")"; [ -f "$reminded" ] && exit 0   # already fired this request
intent="$(cat "$intent_f" 2>/dev/null | tr '\n\t' '  ' | cut -c1-500)"; [ -n "$intent" ] || exit 0
{ mkdir -p "$(companion_state_dir)" 2>/dev/null && : > "$reminded"; } 2>/dev/null || true

ledger=""; dec="$(companion_decisions_path "$root")"; [ -n "$dec" ] && ledger=" against recorded direction ($dec)"
jq -cn --arg i "$intent" --arg l "$ledger" '{hookSpecificOutput:{hookEventName:"PostToolUse",
  additionalContext:("[companion] intent of record: \"\($i)\". Before you finish, confirm the outcome matches it\($l), then recap in one line what now works (demonstrate it, do not just assert); if it diverged or you hit a conflict, say so first.")}}'
