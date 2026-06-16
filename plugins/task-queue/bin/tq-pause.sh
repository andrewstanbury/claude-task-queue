#!/usr/bin/env bash
# tq-pause — pause or resume task auto-advance for the current repo.
#
#   bash bin/tq-pause.sh on       # pause: TaskCompleted stops nudging the next task
#   bash bin/tq-pause.sh off      # resume: auto-advance again
#   bash bin/tq-pause.sh status   # print "paused" or "active" (default action)
#
# Designed to be run by the model on a natural-language request ("pause the
# queue"). The pause is a single flag file scoped to the repo root of the
# current directory, so it persists across sessions until you resume.
#
# This writes the plugin's OWN flag file — never Claude Code's task store.

set -uo pipefail

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

action="${1:-status}"
root="$(tq_root_for_cwd "$PWD")"
flag="$(tq_pause_file "$root")"

case "$action" in
  on|pause)
    mkdir -p "$(tq_pause_dir)" 2>/dev/null || true
    : > "$flag"
    printf 'paused — auto-advance is off for %s\n' "$root"
    ;;
  off|resume)
    rm -f "$flag" 2>/dev/null || true
    printf 'active — auto-advance resumed for %s\n' "$root"
    ;;
  status)
    if tq_is_paused "$root"; then printf 'paused (%s)\n' "$root"
    else printf 'active (%s)\n' "$root"; fi
    ;;
  *)
    printf 'usage: tq-pause.sh on|off|status\n' >&2
    exit 2
    ;;
esac
