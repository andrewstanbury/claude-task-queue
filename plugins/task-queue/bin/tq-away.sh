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
# rather than guessing or executing it. Like agent it's a single flag file scoped
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

# `toggle` (the /task-queue:autopilot command) flips based on the current state.
[ "$action" = "toggle" ] && { tq_is_away "$root" && action="off" || action="on"; }

case "$action" in
  on|enable)
    mkdir -p "$(tq_away_dir)" 2>/dev/null || true
    date +%s > "$flag" 2>/dev/null || : > "$flag"   # stamp the on-time (for staleness + digest)
    tq_review_clear "$root"                          # re-enabling resumes the queue → drop any pending return-review gate
    printf 'Autopilot ON — running autonomously for %s: the queue auto-continues, asking is blocked, and anything that needs you is PARKED for review. Off-switches: CLAUDE_TQ_AWAY_ASK_GUARD=0 (allow asks), CLAUDE_TQ_AWAY_CONTINUE=0 (stop auto-continue).\n' "$root"
    ;;
  off|disable)
    since="$(tq_away_since "$root")"                 # read before removing the flag
    rm -f "$flag" 2>/dev/null || true
    # Arm the return-review gate when there's a parked pile: edits stay blocked until
    # the owner has reviewed it (tq-review-guard.sh). No pile → no gate.
    if tq_repo_has_parked "$root"; then tq_review_set "$root"; else tq_review_clear "$root"; fi
    printf 'Autopilot OFF — the normal review loop is back on for %s.\n' "$root"
    tq_away_digest "$root" "$since" 2>/dev/null || true
    ;;
  status)
    if tq_is_away "$root"; then printf 'on (%s)\n' "$root"
    else printf 'off (%s)\n' "$root"; fi
    ;;
  *)
    printf 'usage: tq-away.sh on|off|toggle|status\n' >&2
    exit 2
    ;;
esac
