#!/usr/bin/env bash
# tq-pause — pause or resume the interpret→present→approve review loop for the repo.
#
#   bash bin/tq-pause.sh on       # pause: substantive prompts run straight in auto
#   bash bin/tq-pause.sh off      # resume: the review loop intercepts again
#   bash bin/tq-pause.sh status   # print "paused" or "active" (default action)
#
# Designed to be run by the model on a natural-language request ("stop reviewing,
# just let me work" / "pause the queue"). The pause is a single flag file scoped to
# the repo root of the current directory, so it persists across sessions until resumed.
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
    printf 'paused — the review loop is off for %s; substantive prompts run straight in auto\n' "$root"
    ;;
  off|resume)
    rm -f "$flag" 2>/dev/null || true
    printf 'active — the review loop is back on for %s\n' "$root"
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
