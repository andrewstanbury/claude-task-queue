#!/usr/bin/env bash
# claude-task-queue installer (v0.2).
#
# This plugin is a READ-ONLY viewer over Claude Code's native task store. It
# installs no hooks and spends no tokens. Install does two things:
#   1. Copy the plugin to ~/.claude/plugins/task-queue/
#   2. Set "statusLine" in ~/.claude/settings.json to our renderer —
#      but ONLY if you don't already have a status line (we never clobber one;
#      compose manually instead — see the note printed at the end).
#
# Override locations via:
#   CLAUDE_HOME=/path           where settings.json lives (default ~/.claude)
#   CLAUDE_TQ_PLUGIN_DIR=/path  where the plugin is copied

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

mkdir -p "$CLAUDE_HOME" "$STATE_DIR" "$(dirname "$PLUGIN_DIR")"

# Copy the plugin tree, excluding git internals, tests, and scratch.
rsync -a --delete \
  --exclude='.git/' \
  --exclude='tests/' \
  --exclude='*.bak' \
  "$SRC_DIR/" "$PLUGIN_DIR/"

chmod +x "$PLUGIN_DIR"/bin/* "$PLUGIN_DIR"/install.sh "$PLUGIN_DIR"/uninstall.sh

# Set our status line ONLY if none is configured — never overwrite an existing
# one (you may be running claude-statusbar or another). settings.json contract:
#   "statusLine": { "type": "command", "command": "<path>" }
mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"

existing="$(jq -r '.statusLine.command // .statusLine // empty' "$SETTINGS" 2>/dev/null || true)"
status_cmd="$PLUGIN_DIR/bin/tq-status.sh"
status_note=""

if [ -z "$existing" ]; then
  tmp="$(mktemp)"
  jq --arg cmd "$status_cmd" \
    '.statusLine = { type: "command", command: $cmd }' \
    "$SETTINGS" > "$tmp"
  mv "$tmp" "$SETTINGS"
  status_note="statusLine set -> $status_cmd"
elif [ "$existing" = "$status_cmd" ]; then
  status_note="statusLine already points at this plugin (no change)."
else
  status_note=$(cat <<NOTE
You already have a status line:
    $existing
  Left it untouched. To show the queue too, call this from your status script:
    $status_cmd
NOTE
)
fi

cat <<EOF
claude-task-queue v0.2 installed (read-only, zero-token).
  plugin:   $PLUGIN_DIR
  reads:    $CLAUDE_HOME/tasks  (Claude Code's native task store)
  cache:    $STATE_DIR          (session->project labels only)
  $status_note

Add the CLI to your PATH so 'tq' works from any shell:
  ln -sf "$PLUGIN_DIR/bin/tq" /usr/local/bin/tq

Then:
  tq            # full to-do/doing/done table, grouped by project
  tq status     # the one-line status

Tasks are created by Claude itself (its native task tools) as it works — this
plugin only reads them, so there is nothing to populate and no tokens spent.
EOF
