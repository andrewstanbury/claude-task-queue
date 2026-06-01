#!/usr/bin/env bash
# Notification hook — when Claude goes idle waiting for the user AND the repo has
# open decisions, emit a terminal/desktop alert naming them, so the user is pinged
# exactly when there's a question to answer (the case they kept missing while
# typing ahead). Silent when there are no open decisions.
#
# Uses allow-listed terminal escape sequences (OSC 777 + OSC 9, plus BEL) so it
# works across common terminals; unsupported ones ignore them. Read-only over the
# ledger; never touches the project. Disable with CLAUDE_TQ_DECISIONS_DISABLED=1.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/decisions.sh
. "$PLUGIN_DIR/lib/decisions.sh"
set +e   # tasks.sh enables errexit; a hook must be best-effort, never abort midway

[ -n "${CLAUDE_TQ_DECISIONS_DISABLED:-}" ] && exit 0

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
ntype="$(printf '%s' "$input" | jq -r '.notification_type // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# Only alert on idle/waiting notifications (not auth/info ones); unknown type is a
# safe default to alert on.
case "$ntype" in idle_prompt|permission_prompt|""|elicitation_dialog) ;; *) exit 0 ;; esac

root="$(tq_root_for_cwd "$cwd")"
n="$(tq_decision_count "$root")"
[ "${n:-0}" -gt 0 ] || exit 0                          # nothing pending → silent

first="$(tq_decision_list "$root" 2>/dev/null | head -n1 | cut -f2)"
title="Claude Code — $n open decision$( [ "$n" -ne 1 ] && printf 's' )"
body="Waiting on your answer: ${first:-a question}"

# OSC 777 (urxvt/Ghostty/Warp), OSC 9 (Windows Terminal/iTerm2/WezTerm), + BEL.
seq="$(printf '\033]777;notify;%s;%s\007\033]9;%s\007\a' "$title" "$body" "$body")"

jq -cn --arg s "$seq" '{terminalSequence: $s}'
