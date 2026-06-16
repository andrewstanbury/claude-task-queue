#!/usr/bin/env bash
# Stop hook — the ALIGNMENT FLOOR. When Claude finishes a substantive change, if
# the project records its decisions and the change plausibly bears on one, block
# ONCE and put the recorded decisions in front of the model: honor them, or — if
# the change reverses/contradicts one — surface that to the owner in plain
# language and confirm before it lands. The semantic judgment is the model's; the
# hook only guarantees the decisions are checked at the moment of "done". Reversing
# a recorded decision unnoticed is an expensive rework/audit trigger; this is the
# OUTCOME-time complement to the review loop's INTENT-time alignment.
#
# Bounded like tidy's verification floor: at most CLAUDE_CHARTER_ALIGN_MAX
# (default 2) blocks per session, and never twice for the same tree, so it can
# never loop. Disable with CLAUDE_CHARTER_ALIGN_GATE=0. Best-effort: any internal
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
# shellcheck source=../lib/charter.sh
. "$PLUGIN_DIR/lib/charter.sh"

allow() { exit 0; }                                   # let the stop proceed

[ "${CLAUDE_CHARTER_ALIGN_GATE:-1}" = "0" ] && allow

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; sid=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"
root="$(charter_root_for_cwd "$cwd")"

# Only when there's a real change to judge: a dirty working tree. A clean repo (or
# a pure-conversation turn) means nothing landed → nothing to align.
if git -C "$root" rev-parse >/dev/null 2>&1; then
  [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] && allow
fi

# Only when the project records decisions to align against, and only when the
# change plausibly bears on one (cheap pre-filter — keeps routine edits silent).
[ -n "$(charter_decisions_path "$root" 2>/dev/null)" ] || allow
[ "$(charter_change_touches_decisions "$root" 2>/dev/null)" = "yes" ] || allow

# Per-session throttle state (cache dir, never the project): the tree we've already
# checked, and the block counter (loop/cost backstop).
cdir="$(charter_log_dir)/align"
key="$(printf '%s' "${sid:-nosession}" | sed 's:/:-:g')"
hfile="$cdir/hash-$key"            # tree fingerprint already prompted-for
cfile="$cdir/count-$key"           # blocks issued this session

cur="$(charter_tree_hash "$root" 2>/dev/null || true)"
# Already prompted for this exact change → don't nag again.
if [ -n "$cur" ] && [ -f "$hfile" ] && [ "$(cat "$hfile" 2>/dev/null || true)" = "$cur" ]; then
  allow
fi

max="${CLAUDE_CHARTER_ALIGN_MAX:-2}"
count=0
[ -f "$cfile" ] && count="$(cat "$cfile" 2>/dev/null || printf 0)"
count="${count//[^0-9]/}"; [ -n "$count" ] || count=0

# Record this tree as prompted-for + bump the counter up front, so a re-stop on an
# unchanged tree allows (the model answered) and we can never loop.
{ mkdir -p "$cdir" 2>/dev/null && [ -n "$cur" ] && printf '%s' "$cur" > "$hfile"; } 2>/dev/null || true

if [ "$count" -ge "$max" ]; then
  jq -cn --arg m "⚠️ Alignment gate: checked $count times this session — proceeding. Double-check this change honors the project's recorded decisions before it's trusted." \
    '{systemMessage: $m}'
  exit 0
fi
{ mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((count + 1))" > "$cfile"; } 2>/dev/null || true

dpath="$(charter_decisions_path "$root" 2>/dev/null || true)"
excerpt="$(charter_decisions_excerpt "$root" 2>/dev/null || true)"
jq -cn --arg r "Before this is done — check your change against the project's recorded decisions ($dpath). Re-litigating or silently reversing a recorded choice is an expensive rework/audit trap. If the change HONORS them, note that in one line and finish. If it REVERSES or CONTRADICTS one, stop and surface it to the owner in plain language — which decision, what the change does instead, and why — then get a plain-language yes before it lands. Recorded decisions:"$'\n\n'"$excerpt" \
  '{decision: "block", reason: $r}'
