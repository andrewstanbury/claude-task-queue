#!/usr/bin/env bash
# Stop hook — the INTENT→OUTCOME gate (the owner loop's CLOSE). The review loop
# captures the owner's plain-language ask at prompt time (tq-capture); this replays
# it at "done" against the actual change, forcing a check that the OUTCOME matches
# the INTENT before Claude declares the work finished. The owner is non-technical
# and verifies by SEEING it work, not by reading code — so "I built the wrong thing
# / only part of it / something extra" has to be surfaced in plain language here.
#
# Fires ONCE per captured intent (consumed on a dirty Stop), so it can't loop.
# Silent when there's no captured intent (a trivial/conversational turn), on a
# clean tree (nothing landed yet — the intent is kept for a later Stop), outside a
# git repo, or when disabled (CLAUDE_TQ_INTENT_GATE=0). Best-effort: any internal
# error degrades to "allow the stop" (a companion must never break the action).

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
set +e   # tasks.sh enables `set -e`; this hook is best-effort — a failing git
         # call (e.g. `diff HEAD` in a repo with no commits) must NOT break the stop.

allow() { exit 0; }                                   # let the stop proceed

[ "${CLAUDE_TQ_INTENT_GATE:-1}" = "0" ] && allow

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; sid=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# No captured intent for this session → trivial/conversational turn, nothing to
# verify against.
ifile="$(tq_intent_file "$sid")"
[ -f "$ifile" ] || allow

root="$(tq_root_for_cwd "$cwd")"

# Only verify once a change has actually LANDED. On a clean tree the work isn't
# done yet (or the turn was pure analysis) — keep the intent for a later Stop. No
# git → there's no outcome to summarize, so don't gate.
git -C "$root" rev-parse >/dev/null 2>&1 || allow
[ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] && allow

intent="$(head -c 1200 "$ifile" 2>/dev/null || true)"
rm -f "$ifile" 2>/dev/null || true                    # consume → fire once per ask
[ -n "$intent" ] || allow

# Summarize the OUTCOME side: the diffstat + any new files, bounded.
stat="$(git -C "$root" diff --stat HEAD 2>/dev/null | tail -n 41)"
unt="$(git -C "$root" ls-files --others --exclude-standard 2>/dev/null | head -n 20 | sed 's/^/  + /')"
changed="$stat"
if [ -n "$unt" ]; then
  [ -n "$changed" ] && changed="$changed"$'\n'
  changed="${changed}new files:"$'\n'"$unt"
fi
[ -n "$changed" ] || changed="(no tracked file changes detected)"

jq -cn --arg r "Outcome check before you call this done. The owner asked, in their words:"$'\n\n'"  $intent"$'\n\n'"What actually changed:"$'\n\n'"$changed"$'\n\n'"Verify the OUTCOME matches the ask before declaring done — the owner is non-technical and verifies by SEEING it work, not by reading code. If you built only PART of what they asked, took a DIFFERENT approach than implied, or changed something they did NOT ask for, surface that in plain language and confirm. If it matches, give the owner a one-line plain-language recap of what now works (demonstrate, don't just assert)." \
  '{decision: "block", reason: $r}'
