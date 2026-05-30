#!/usr/bin/env bash
# Reverse of install.sh.
#   - Removes the plugin directory.
#   - Removes our SessionStart "resume bridge" hook from settings.json (only our
#     own entry; any other hooks you have are left untouched).
#   - Leaves the caches by default (tiny and harmless). Pass --purge-state to
#     remove ~/.claude/state/task-queue too.
#
# NOTE: this never deletes anything under ~/.claude/tasks — those are Claude
# Code's own native task files, not ours.

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PLUGIN_DIR="${CLAUDE_TQ_PLUGIN_DIR:-$CLAUDE_HOME/plugins/task-queue}"
SETTINGS="$CLAUDE_HOME/settings.json"
STATE_DIR="$CLAUDE_HOME/state/task-queue"

purge_state=0
for arg in "$@"; do
  case "$arg" in
    --purge-state) purge_state=1 ;;
    *) printf 'unknown flag: %s\n' "$arg" >&2; exit 64 ;;
  esac
done

resume_cmd="$PLUGIN_DIR/bin/tq-resume.sh"

rm -rf "$PLUGIN_DIR"

# Drop our own SessionStart hook entry, then tidy up: remove the SessionStart
# array if it's now empty, and the hooks object if it is. Leaves other hooks be.
if [ -f "$SETTINGS" ]; then
  tmp="$(mktemp)"
  jq --arg cmd "$resume_cmd" '
    if .hooks.SessionStart then
      .hooks.SessionStart |= map(select(
        ((.hooks // []) | map(.command) | index($cmd)) | not
      ))
    else . end
    | if (.hooks.SessionStart // []) == [] then del(.hooks.SessionStart) else . end
    | if (.hooks // {}) == {} then del(.hooks) else . end
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
fi

if [ "$purge_state" -eq 1 ]; then
  rm -rf "$STATE_DIR"
  printf 'claude-task-queue uninstalled (label cache purged).\n'
else
  printf 'claude-task-queue uninstalled. Label cache kept at %s — pass --purge-state to remove.\n' "$STATE_DIR"
fi
