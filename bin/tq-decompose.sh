#!/usr/bin/env bash
# UserPromptSubmit hook entry point. Read the freshly-submitted prompt and:
#   1. Skip if disabled, blank, /slash, or !bang.
#   2. Classify trivial vs non-trivial (lib/classify.sh).
#   3. Non-trivial → Haiku triage (lib/haiku.sh) → tasks land in the queue.
#                    Trivial → no queue write.
#   4. Inject a small system-reminder with the current queue snapshot so the
#      next assistant turn sees what's next without re-reading anything.
#
# Goal: replace claude-statusbar's confirm-intent.sh with something that
# (a) actually decomposes work instead of asking the model to do it every
# turn, and (b) carries durable, project-scoped state across /clear.

set -euo pipefail

[ "${CLAUDE_TQ_DISABLED:-0}" = "1" ] && exit 0

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/queue.sh
. "$PLUGIN_DIR/lib/queue.sh"
# shellcheck source=../lib/classify.sh
. "$PLUGIN_DIR/lib/classify.sh"
# shellcheck source=../lib/haiku.sh
. "$PLUGIN_DIR/lib/haiku.sh"

payload="$(cat)"
prompt="$(printf '%s' "$payload" | jq -r '.prompt // empty')"

# Nothing to interpret.
[ -z "$prompt" ] && exit 0

case "$prompt" in
  /*|!*) exit 0 ;;
esac

# Classify; trivial prompts skip Haiku but still get the queue-snapshot
# system-reminder injected (so the assistant always knows where it is).
appended_count=0
if tq_classify "$prompt"; then
  while IFS= read -r _id; do
    [ -n "$_id" ] && appended_count=$((appended_count + 1))
  done < <(tq_haiku_triage "$prompt" 2>/dev/null || true)
fi

# Build the system-reminder we inject for the next turn.
counts="$(tq_counts)"
pending_next="$(tq_next 2>/dev/null || true)"
in_progress_now="$(tq_in_progress 2>/dev/null || true)"
paused="false"
autopilot="false"
tq_is_paused && paused="true"
tq_is_autopilot && autopilot="true"

state_line="queue=$counts paused=$paused autopilot=$autopilot"
if [ -n "$in_progress_now" ]; then
  state_line+=" in_progress=$(printf '%s' "$in_progress_now" | jq -r '.id + ": " + .subject')"
fi
if [ -n "$pending_next" ]; then
  state_line+=" next=$(printf '%s' "$pending_next" | jq -r '.id + ": " + .subject + " (" + .est + ")"')"
fi

if [ "$appended_count" -gt 0 ]; then
  intro="claude-task-queue: appended $appended_count task(s) from this prompt."
else
  intro="claude-task-queue: queue state for this project."
fi

msg="$intro $state_line. Pause = $paused; autopilot = $autopilot. Work the next pending task; before starting state its est; pause for confirmation unless autopilot. Always pause before destructive/irreversible steps regardless. The queue is durable across /clear — DO NOT recreate tasks from scratch on resume; read the existing queue with the \`tq\` CLI or by inspecting the queue file directly."

jq -nc --arg m "$msg" '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: $m
  }
}'
