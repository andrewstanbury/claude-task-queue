#!/usr/bin/env bash
# PreToolUse[Write|Edit] — two enforced work-gates (R27) that harden STEERING clauses the model
# could otherwise skip. Best-effort, fail-OPEN (allow). Never fires under autopilot (owner is
# away — work-first is the point). Disable: CLAUDE_COMPANION_GATES=0.
#   1. RETURN-REVIEW — back from a run with parked ❓ decisions still open and not yet presented
#      this return → block until they're shown (ask-guard sets the review flag when you present).
#   2. DESIGN-PREVIEW — this prompt asked for a visual/UI change and no wireframe has been shown
#      (the design flag armed by prompt.sh is still set) → block until you present it.
# (The intent→outcome reminder is advisory and lives in intent-note.sh, PostToolUse.)
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

# Autopilot ON → the owner is away; neither gate applies. Still let the edit through.
companion_autopilot_on "$root" && exit 0

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",
    permissionDecision:"deny", permissionDecisionReason:$r}}'
  exit 0
}

# 1) return-review: parked ❓ decisions from an earlier run, not yet presented this return.
if [ ! -f "$(companion_review_flag "$root")" ] && companion_has_parked "$root"; then
  deny "You're back with parked ❓ decisions still open — present them FIRST as blocking multiple-choice (AskUserQuestion, your recommended option first) before resuming edits; that's the return contract. \`tq report\` lists them. (CLAUDE_COMPANION_GATES=0 overrides.)"
fi

# 2) design-preview: a visual prompt, no wireframe shown yet.
if [ -f "$(companion_design_flag "$sid")" ]; then
  deny "This is a visual/UI change — show the design before building it. Present 2-3 wireframe mockups via AskUserQuestion (recommended first; ╔═╗ container · ▒ input · █ emphasis; include the current state to compare), and build ONLY the chosen one. Presenting clears this gate. (CLAUDE_COMPANION_GATES=0 overrides.)"
fi
exit 0
