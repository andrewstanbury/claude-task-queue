#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) guard — enforce the RETURN-REVIEW.
#
# When autopilot turns OFF with a parked ❓ pile, tq-away.sh sets a per-repo
# review-pending marker. Until every parked ❓ is resolved, this hook DENIES edits and
# tells the model to walk the pile WITH the owner first (a blocking AskUserQuestion per
# item, recommended option first) — so the owner reviews what autopilot decided before
# any more code lands. It self-clears the marker the moment the pile is empty, so normal
# editing resumes automatically. Silent no-op when no review is pending, or when
# disabled (CLAUDE_TQ_REVIEW_GATE=0).
#
# Best-effort: any internal error degrades to "allow" — a companion must never break the
# action it hooks. Wired by hooks/hooks.json as a PreToolUse matcher.

set -uo pipefail
# Drain stdin before allowing, so the writer piping the payload can't hit a broken pipe
# when we exit without reading it. Skipped on a TTY (no piped input) so a manual run
# can't block.
allow() { [ -t 0 ] || cat >/dev/null 2>&1; exit 0; }  # let the edit proceed
[ "${CLAUDE_TQ_REVIEW_GATE:-1}" = "0" ] && allow

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
set +e   # tasks.sh enables `set -e`; this hook is best-effort — never break the call.

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""
[ -n "$input" ] && cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"

tq_review_pending "$root" || allow          # no pending review → editing is fine
if ! tq_repo_has_parked "$root"; then       # pile cleared → retire the gate, resume editing
  tq_review_clear "$root"
  allow
fi

reason="🧷 Parked-review pending — autopilot left decisions for you to make. Review them FIRST: present each open '❓ [parked]' task to the owner as a blocking AskUserQuestion (2-3 concrete options, your recommended one first), apply their pick, and resolve the ❓ (TaskUpdate) — BEFORE editing code. Editing is blocked until the parked pile is empty (it clears itself then). (Owner: CLAUDE_TQ_REVIEW_GATE=0 disables this gate.)"
jq -cn --arg r "$reason" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
