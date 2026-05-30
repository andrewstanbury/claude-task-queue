#!/usr/bin/env bash
# TaskCompleted hook — auto-advance the live queue.
#
# Fires only when the model marks a task completed (event-driven, so it adds
# nothing per prompt). It reads the current session's native task list and, if
# there's a clear next step, injects a one-line note naming the next unblocked
# task — so the model keeps moving down the queue in dependency order without
# being asked. Silent when work is already in_progress or nothing is actionable.
#
# Read-only: like the SessionStart bridge, it never writes the native store. The
# model still owns advancing; we only point at what's next.
#
# Wired by hooks/hooks.json on TaskCompleted; invoked as
# "${CLAUDE_PLUGIN_ROOT}/bin/tq-next.sh". Claude Code hands it the event JSON on
# stdin: { session_id, task_id, task_title, ... }.

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

# Read the TaskCompleted payload.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
sid=""
done_id=""
if [ -n "$input" ]; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  done_id="$(printf '%s' "$input" | jq -r '.task_id // empty' 2>/dev/null || true)"
fi

next="$(tq_next_context "$sid" "$done_id" 2>/dev/null || true)"
[ -n "$next" ] || exit 0                 # nothing actionable — stay silent

IFS=$'\t' read -r nid nsubj nopen <<<"$next"
ctx="[task-queue] Next unblocked task: #${nid} — ${nsubj} (${nopen} open). Pick it up next unless the user redirects."

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "TaskCompleted", additionalContext: $c}}'
