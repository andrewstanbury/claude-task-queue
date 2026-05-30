#!/usr/bin/env bash
# claude-task-queue installer (v0.3). Two steps:
#   1. Copy the plugin to ~/.claude/plugins/task-queue/
#   2. Register the SessionStart "resume bridge" hook in settings.json
#      (idempotent; leaves any other hooks you have untouched).
#
# The hook is the only thing that enters model context — and only with a short
# note, and only when an earlier session left open tasks in the repo you start
# in. The `tq` CLI reader stays zero-token.
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

mkdir -p "$(dirname "$SETTINGS")"
[ -f "$SETTINGS" ] || printf '{}' > "$SETTINGS"

# Register the SessionStart "resume bridge" hook (idempotent). We drop any prior
# copy of our own hook first so re-running install never duplicates it; any other
# hooks you have are kept untouched.
resume_cmd="$PLUGIN_DIR/bin/tq-resume.sh"
tmp="$(mktemp)"
jq --arg cmd "$resume_cmd" '
  .hooks //= {}
  | .hooks.SessionStart //= []
  | .hooks.SessionStart |= map(select(
      ((.hooks // []) | map(.command) | index($cmd)) | not
    ))
  | .hooks.SessionStart += [ { hooks: [ { type: "command", command: $cmd } ] } ]
' "$SETTINGS" > "$tmp"
mv "$tmp" "$SETTINGS"
resume_note="SessionStart hook -> $resume_cmd"

cat <<EOF
claude-task-queue v0.3 installed (native-first: reader + resume bridge).
  plugin:   $PLUGIN_DIR
  reads:    $CLAUDE_HOME/tasks  (Claude Code's native task store)
  cache:    $STATE_DIR          (session->project / session->root caches)
  $resume_note

Add the CLI to your PATH so 'tq' works from any shell:
  ln -sf "$PLUGIN_DIR/bin/tq" /usr/local/bin/tq

Then:
  tq            # full to-do/doing/done table, grouped by project
  tq status     # the one-line status

Tasks are created by Claude itself (its native task tools) as it works. The
'tq' reader stays zero-token. The SessionStart resume bridge is the one place
that enters context — and only with a short note, and only when an earlier
session left open tasks in the repo you're starting in.
EOF
