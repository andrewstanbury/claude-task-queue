#!/usr/bin/env bash
# PreToolUse[AskUserQuestion] — while autopilot is ON, DENY the question. Autopilot means keep
# going without stopping (R36); asking = stopping, so the model must decide-if-reversible-mechanic
# or PARK the decision/design choice as a `❓` task instead. This makes autopilot's "don't stop to
# ask" mechanical, not advisory. Silent (allow) when autopilot is off. Best-effort: degrades to allow.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(companion_root "$cwd")"
companion_autopilot_on "$root" || exit 0

# Same denial either way (asking = stopping), but the GUIDANCE differs by mode (R59). Default:
# park every decision. Decisive: auto-pick your recommended option for REVERSIBLE decisions
# (taste included — overrides R33) and record it; park/block ONLY the irreversible-critical.
if companion_decisive_on "$root"; then
  reason="Autopilot is ON + DECISIVE mode (R59) — keep going, do not stop to ask. For any REVERSIBLE decision, incl. design/wording/direction: DECIDE it yourself — pick your own recommended option (the one you'd have marked (Recommended)), RECORD it with a breadcrumb (\`tq note <id> \"decided: <pick> + one-line why\"\`, or a fresh \`tq add\` for the chosen task), and proceed. Do NOT park a reversible decision — the audit trail (your recorded picks) is the safety net, walked later by /companion:review. PARK (❓) or BLOCK (⏳) ONLY when the action is IRREVERSIBLE, externally-binding, or data-destructive (a push, a delete, spending money, anything you can't cleanly undo) — those still carry the FULL option payload in the subject: \`tq add \"❓ [parked] <choice> — options: A) …(cost) B) …(cost); rec:<pick>+why\"\`. When unsure whether it's reversible, treat it as irreversible and park."
else
  reason="Autopilot is ON — keep going, do not stop to ask (asking = stopping; the owner may be present and adding tasks). Decide it yourself ONLY if it is a reversible, taste-neutral mechanic (record the call). A visual/design/direction/wording choice belongs to the owner — PARK it even if it is reversible (do NOT pick for them). Park with the FULL payload you would have asked live, not a thin guess — it all goes in the subject (the parked-pile review, /companion:review, reads it back via \`tq list\`): \`tq add \"❓ [parked] <the choice> — options: A) … (cost) B) … (cost) C) … (cost); rec: <your pick> + why\"\` (or \`⏳ [blocked] <owner-only action>\`), then move on. A \`❓\` with a one-line guess instead of the options makes the later review a rubber-stamp — carry the 2–4 options + each cost + your recommendation. The owner reviews parked items whenever they check in."
fi

jq -cn --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
