#!/usr/bin/env bash
# /tq — the single task-queue control command. One explorable entry point that
# replaces the old per-mode slash commands. Bare `tq` prints the plain-language menu
# + current mode state; a subcommand toggles or acts. A THIN dispatcher over the
# bin/ scripts — no logic of its own, so each mode's behavior stays defined in one
# place (the merged pause+away lives in tq-away.sh, surfaced here as `solo`).
#
#   /tq                      show the modes + open work (the menu)
#   /tq solo on|off          autonomous mode (was away + pause): run without you
#   /tq checkpoint on|off    arm/disarm crash-checkpoint snapshots
#   /tq undo                 recover the working tree from the last checkpoint
#   /tq agent on|off         fan independent tasks out to subagents

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
BIN="$(cd "$(dirname "$SELF")" && pwd)"

sub="${1:-}"
[ "$#" -gt 0 ] && shift
case "$sub" in
  ""|menu|help|status) exec "$BIN/tq-status.sh" ;;
  solo)                exec "$BIN/tq-away.sh" "$@" ;;
  checkpoint)          exec "$BIN/tq-checkpoint.sh" "$@" ;;
  undo|restore)        exec "$BIN/tq-checkpoint.sh" restore ;;
  agent)               exec "$BIN/tq-agent.sh" "$@" ;;
  *)
    printf 'usage: /tq [solo on|off] [checkpoint on|off] [agent on|off] [undo] [status]\n' >&2
    printf 'bare /tq shows the current modes + open work.\n' >&2
    exit 2 ;;
esac
