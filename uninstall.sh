#!/usr/bin/env bash
# Reverse of install.sh.
#   - Removes the plugin directory.
#   - Removes our "statusLine" from settings.json ONLY if it still points at
#     this plugin (never touches a status line you've since changed).
#   - Leaves the label cache by default (it's tiny and harmless). Pass
#     --purge-state to remove ~/.claude/state/task-queue too.
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

status_cmd="$PLUGIN_DIR/bin/tq-status.sh"

rm -rf "$PLUGIN_DIR"

if [ -f "$SETTINGS" ]; then
  current="$(jq -r '.statusLine.command // .statusLine // empty' "$SETTINGS" 2>/dev/null || true)"
  if [ "$current" = "$status_cmd" ]; then
    tmp="$(mktemp)"
    jq 'del(.statusLine)' "$SETTINGS" > "$tmp"
    mv "$tmp" "$SETTINGS"
  fi
fi

if [ "$purge_state" -eq 1 ]; then
  rm -rf "$STATE_DIR"
  printf 'claude-task-queue uninstalled (label cache purged).\n'
else
  printf 'claude-task-queue uninstalled. Label cache kept at %s — pass --purge-state to remove.\n' "$STATE_DIR"
fi
