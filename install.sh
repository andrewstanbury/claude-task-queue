#!/usr/bin/env bash
# claude-task-queue installer.
#
# Idempotent: re-running upgrades the plugin in place + merges hook entries
# without clobbering anything else in ~/.claude/settings.json.
#
# Layout after install:
#   ~/.claude/plugins/task-queue/   (this repo's contents)
#   ~/.claude/state/task-queue/     (created on first hook fire)
#   ~/.claude/settings.json         (hooks merged in)
#
# Override locations via:
#   CLAUDE_HOME=/path           where settings.json lives (default ~/.claude)
#   CLAUDE_TQ_PLUGIN_DIR=/path  where the plugin is copied (default $CLAUDE_HOME/plugins/task-queue)

set -euo pipefail

CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
PLUGIN_DIR="${CLAUDE_TQ_PLUGIN_DIR:-$CLAUDE_HOME/plugins/task-queue}"
SETTINGS="$CLAUDE_HOME/settings.json"
STATE_DIR="$CLAUDE_HOME/state/task-queue"

SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v jq >/dev/null 2>&1; then
  printf 'error: jq is required. Install jq and re-run.\n' >&2
  exit 1
fi

if ! command -v sha1sum >/dev/null 2>&1; then
  printf 'error: sha1sum is required. Install it (coreutils on Linux, brew install coreutils on macOS) and re-run.\n' >&2
  exit 1
fi

mkdir -p "$CLAUDE_HOME" "$STATE_DIR" "$(dirname "$PLUGIN_DIR")"

# Copy the plugin tree, excluding git internals and the user's state dir.
rsync -a --delete \
  --exclude='.git/' \
  --exclude='tests/' \
  --exclude='*.bak' \
  --exclude='.tq-sandbox/' \
  "$SRC_DIR/" "$PLUGIN_DIR/"

chmod +x "$PLUGIN_DIR"/bin/* "$PLUGIN_DIR"/install.sh "$PLUGIN_DIR"/uninstall.sh

# Merge hook entries into settings.json without clobbering existing keys.
# settings.json hook contract used here:
#   {
#     "hooks": {
#       "UserPromptSubmit": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "..." } ] } ],
#       "PreToolUse":       [ { "matcher": "*", "hooks": [ { "type": "command", "command": "..." } ] } ]
#     }
#   }
# We add ONE entry per event tagged with "id": "claude-task-queue" so we can
# upsert (replace by id on re-install) instead of duplicating.

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"

tmp="$(mktemp)"
jq \
  --arg decompose "$PLUGIN_DIR/bin/tq-decompose.sh" \
  --arg pretool "$PLUGIN_DIR/bin/tq-pretool.sh" \
  '
  def upsert_hook(event; cmd):
    .hooks //= {}
    | .hooks[event] //= []
    | .hooks[event] |= (
        map(select((.id // "") != "claude-task-queue"))
        + [{
            id: "claude-task-queue",
            matcher: "*",
            hooks: [{ type: "command", command: cmd }]
          }]
      );
  upsert_hook("UserPromptSubmit"; $decompose)
  | upsert_hook("PreToolUse"; $pretool)
  ' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"

cat <<EOF
claude-task-queue installed.
  plugin:   $PLUGIN_DIR
  state:    $STATE_DIR
  settings: $SETTINGS (hooks merged with id "claude-task-queue")

Add the CLI to your PATH so 'tq' works from any shell:
  ln -sf "$PLUGIN_DIR/bin/tq" /usr/local/bin/tq

Or use the full path:
  $PLUGIN_DIR/bin/tq status

Disable temporarily:
  CLAUDE_TQ_DISABLED=1            (skip decompose hook)
  CLAUDE_TQ_PRETOOL_DISABLED=1    (skip pretool gate)
  CLAUDE_TQ_HAIKU_DISABLED=1      (skip Haiku triage, fall back to single-task)
EOF
