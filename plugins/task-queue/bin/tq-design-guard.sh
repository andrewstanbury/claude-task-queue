#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) guard — enforce the DESIGN-PREVIEW.
#
# When the owner asks for a visual/design change (classified by tq-capture.sh), a
# per-session design-pending marker is armed. This hook DENIES edits until a wireframe
# preview has been shown — the ask-guard clears the marker when an AskUserQuestion fires
# (that IS the preview). So a visual change can't be built before the owner (non-technical,
# verifies by SEEING) has seen and picked it — the "avoid rework" guarantee, made real
# instead of advisory. Stands down during an autopilot autonomous drain (owner absent →
# design decisions are parked, not gated). Silent when no design preview is pending, or
# when disabled (CLAUDE_TQ_DESIGN_GATE=0).
#
# Best-effort: any internal error degrades to "allow" — a companion must never break the
# action it hooks. Wired by hooks/hooks.json as a PreToolUse matcher.

set -uo pipefail
allow() { [ -t 0 ] || cat >/dev/null 2>&1; exit 0; }  # let the edit proceed
[ "${CLAUDE_TQ_DESIGN_GATE:-1}" = "0" ] && allow

# Resolve symlinks so a relocated/PATH-installed entrypoint still finds lib/.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"
# shellcheck source=../lib/capture.sh
. "$PLUGIN_DIR/lib/capture.sh"
set +e   # tasks.sh enables `set -e`; this hook is best-effort — never break the call.

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; sid=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"

tq_design_pending "$sid" || allow                        # no design preview pending → edit freely
tq_is_away "$root" && ! tq_owner_present "$sid" && allow  # autopilot drain: park design, don't gate

reason="🎨 Design-preview pending — this is a VISUAL change and the owner verifies by SEEING, not reading code. SHOW it FIRST: present a recommended layout + 2-3 alternatives as faithful WIREFRAME mockups in a blocking AskUserQuestion (heavy border ╔═╗ for a container, ▒ for an input field, █ for the primary element), recommended option first; the owner picks, THEN you build it. Editing is blocked until you've shown the preview. (Owner: CLAUDE_TQ_DESIGN_GATE=0 disables this gate.)"
jq -cn --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
