#!/usr/bin/env bash
# SessionStart hook — prime the session's task queue. The whole plugin.
#
# Does two cheap things ONCE per session (no per-prompt cost):
#   1. Policy — tell the model to treat its native task list as the live work
#      queue: capture described work with TaskCreate, work it in dependency
#      order, batch related tasks, stay inline, advance without draining. Said
#      once here, this governs the whole session — far cheaper than re-injecting
#      every turn, and Claude Code's own task nudges reinforce it.
#   2. Resume — surface this repo's still-open tasks from earlier sessions so the
#      model re-adopts them into the (otherwise empty) native list.
#
# Read-only: it never writes the native store. The model owns the tasks; we only
# read them and state the policy. Claude Code renders the resulting task list as
# the visible queue in the CLI — we add no UI of our own.
#
# Wired by hooks/hooks.json on SessionStart; invoked as
# "${CLAUDE_PLUGIN_ROOT}/bin/tq-resume.sh" with CLAUDE_TQ_STATE_DIR pointed at
# "${CLAUDE_PLUGIN_DATA}" so the root cache survives plugin updates.

set -euo pipefail

# Resolve symlinks so a relocated/PATH-installed entrypoint still finds lib/.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"

POLICY='[task-queue] Treat your native task list as the live work queue. When a prompt describes a task, fix, or multi-step request, capture the items with TaskCreate before starting (skip trivial or conversational prompts) so they show up in the queue. Work the queue in dependency order (honor blockedBy), batch same-area tasks to save context, prefer inline over subagents, and advance as you go without draining the backlog unprompted.'

# SessionStart hands us JSON on stdin: { session_id, cwd, source, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
sid=""
cwd=""
if [ -n "$input" ]; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

root="$(tq_root_for_cwd "$cwd")"
resume="$(tq_resume_context "$root" "$sid" 2>/dev/null || true)"

ctx="$POLICY"
[ -n "$resume" ] && ctx="$ctx"$'\n\n'"$resume"

if [ -n "$resume" ]; then
  tq_log "session-start" "resume note surfaced" "$sid"
else
  tq_log "session-start" "policy only (no carry-over)" "$sid"
fi

# Emit as SessionStart additionalContext (added to the session's context once).
jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
