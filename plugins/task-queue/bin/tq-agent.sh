#!/usr/bin/env bash
# tq-agent — toggle opt-in agent-mode (parallel subagent fan-out) for this repo.
#
#   bash bin/tq-agent.sh on       # permit fanning independent tasks to subagents
#   bash bin/tq-agent.sh off      # back to inline-only (the default)
#   bash bin/tq-agent.sh status   # print "on" or "off" (default action)
#
# Agent-mode is OFF by default (subagents cost more tokens). When ON, the
# SessionStart policy tells the model it MAY fan independent, non-conflicting
# tasks out to subagents via the Task tool. Like pause, it's a single flag file
# scoped to the repo root, persisting across sessions.
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
flag="$(tq_agent_file "$root")"

case "$action" in
  on|enable)
    mkdir -p "$(tq_agent_dir)" 2>/dev/null || true
    : > "$flag"
    printf 'agent-mode ON — independent tasks may fan out to subagents for %s\n' "$root"
    ;;
  off|disable)
    rm -f "$flag" 2>/dev/null || true
    printf 'agent-mode OFF — inline only (default) for %s\n' "$root"
    ;;
  status)
    if tq_is_agent_mode "$root"; then printf 'on (%s)\n' "$root"
    else printf 'off (%s)\n' "$root"; fi
    ;;
  *)
    printf 'usage: tq-agent.sh on|off|status\n' >&2
    exit 2
    ;;
esac
