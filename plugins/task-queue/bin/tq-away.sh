#!/usr/bin/env bash
# tq-away — toggle away-mode (owner stepped away → run fully autonomous) for the repo.
#
#   bash bin/tq-away.sh on       # owner is away: run in auto, never block, PARK what needs them
#   bash bin/tq-away.sh off      # owner is back: normal review loop resumes
#   bash bin/tq-away.sh status   # print "on" or "off" (default action)
#
# Run by the model on a natural-language request ("I'm stepping away, keep going" /
# "I'm back"). When ON, the SessionStart policy tells the model NOT to block on the
# owner — no AskUserQuestion, no "please run this test" — but to self-verify and PARK
# anything that genuinely needs the owner (a design fork, an ambiguous choice, an
# owner-only test, or an irreversible/binding action) as a ❓ task for review on return,
# rather than guessing or executing it. Like pause/agent it's a single flag file scoped
# to the repo root, persisting across sessions until turned off.
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
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"

action="${1:-status}"
root="$(tq_root_for_cwd "$PWD")"
flag="$(tq_away_file "$root")"

case "$action" in
  on|enable)
    mkdir -p "$(tq_away_dir)" 2>/dev/null || true
    date +%s > "$flag" 2>/dev/null || : > "$flag"   # stamp the on-time (for staleness + digest)
    printf 'away-mode ON — running autonomous for %s; anything needing you is PARKED for review, not asked\n' "$root"
    ;;
  off|disable)
    since="$(tq_away_since "$root")"                 # read before removing the flag
    rm -f "$flag" 2>/dev/null || true
    printf 'away-mode OFF — the review loop is back on for %s\n' "$root"
    tq_away_digest "$root" "$since" 2>/dev/null || true
    ;;
  status)
    if tq_is_away "$root"; then printf 'on (%s)\n' "$root"
    else printf 'off (%s)\n' "$root"; fi
    ;;
  *)
    printf 'usage: tq-away.sh on|off|status\n' >&2
    exit 2
    ;;
esac
