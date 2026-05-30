#!/usr/bin/env bash
# Status-line entry point. Prints ONE line summarizing open work across all of
# Claude Code's native task lists (every session / project), plus the current
# "doing" task. Always exits 0; prints nothing when there is no open work.
#
# Wire it up as your status line in ~/.claude/settings.json:
#   "statusLine": { "type": "command", "command": ".../bin/tq-status.sh" }
# or call its output from claude-statusbar's status.sh to compose with git/etc.
#
# This never enters the model's context, so it costs ZERO tokens per turn.

set -euo pipefail

# Resolve symlinks so a PATH-installed entrypoint finds lib/ in the real plugin
# dir. Portable readlink loop (no GNU-only `readlink -f`).
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

# Drain any stdin the status-line host hands us (session JSON) — we render
# globally and don't need it, but reading avoids a broken-pipe surprise.
[ -t 0 ] || cat >/dev/null 2>&1 || true

tq_status_line || true
