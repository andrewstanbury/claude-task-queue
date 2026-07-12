#!/usr/bin/env bash
# PreToolUse[AskUserQuestion] — while autopilot is ON, DENY the question. The owner is away,
# so asking would stall the drain; the model must decide-if-reversible or PARK the decision as
# a `❓` task instead. This makes autopilot's "never ask" mechanical, not advisory. Silent
# (allow) when autopilot is off. Best-effort: any error degrades to allow.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"

# Autopilot OFF: an AskUserQuestion IS the model presenting — so it satisfies the R27 work-gates.
# Clear the design-preview flag (the wireframe is being shown) and set the return-review flag
# (the ❓ pile is being presented). work-guard then stops blocking Write|Edit. Best-effort.
if ! companion_autopilot_on "$root"; then
  rm -f "$(companion_design_flag "$sid")" 2>/dev/null || true
  { mkdir -p "$(dirname "$(companion_review_flag "$root")")" 2>/dev/null \
    && : > "$(companion_review_flag "$root")"; } 2>/dev/null || true
  exit 0
fi

jq -cn '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny",
  permissionDecisionReason: "Autopilot is ON — the owner is away, so do not ask. Decide it yourself if it is reversible and low-cost (record the call), otherwise PARK it: `tq add \"❓ [parked] <the decision>\"` (or `⏳ [blocked] <owner-only action>`) and move on to the next task. The parked items are presented when the owner returns."}}'
