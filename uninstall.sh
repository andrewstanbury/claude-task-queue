#!/usr/bin/env bash
# Reverse of install.sh.
#   - Removes the plugin directory.
#   - Removes claude-task-queue hook entries from settings.json (leaves
#     everything else untouched).
#   - Does NOT delete the state directory by default — your queues are kept
#     so you can re-install without losing work. Pass --purge-state to
#     remove ~/.claude/state/task-queue as well.

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

rm -rf "$PLUGIN_DIR"

if [ -f "$SETTINGS" ]; then
  tmp="$(mktemp)"
  jq '
    if .hooks then
      .hooks
      |= (
        with_entries(
          .value |= map(select((.id // "") != "claude-task-queue"))
        )
        | with_entries(select(.value | length > 0))
      )
    else . end
    | if .hooks == {} then del(.hooks) else . end
  ' "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
fi

if [ "$purge_state" -eq 1 ]; then
  rm -rf "$STATE_DIR"
  printf 'claude-task-queue uninstalled (state purged).\n'
else
  printf 'claude-task-queue uninstalled. State preserved at %s — pass --purge-state to remove.\n' "$STATE_DIR"
fi
