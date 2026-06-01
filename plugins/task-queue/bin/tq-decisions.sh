#!/usr/bin/env bash
# UserPromptSubmit hook — re-surface OPEN decisions every prompt so a question the
# model asked can't be silently lost when the user queues prompts ahead.
#
# Silent unless the repo has open decisions in the ledger (the model logs them
# with bin/tq-ask.sh). When it fires it re-injects them + the protocol: re-ask via
# AskUserQuestion, resolve on an answer, and proceed with the recommended option
# if one is still unanswered after being surfaced — so work never stalls.
# **Token-free unless it fires.** Disable with CLAUDE_TQ_DECISIONS_DISABLED=1.

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
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"

rows="$(tq_decision_list "$root" 2>/dev/null || true)"
[ -n "$rows" ] || exit 0                              # no open decisions → silent

ask="$PLUGIN_DIR/bin/tq-ask.sh"
list=""
while IFS=$'\t' read -r id q rec; do
  [ -n "$id" ] || continue
  list="$list"$'\n'"  #$id $q$( [ -n "$rec" ] && printf ' — recommended: %s' "$rec" )"
done <<< "$rows"

ctx="⚠️ [task-queue] OPEN DECISION(S) the user has not resolved (a question may have been queued past):$list"$'\n'"Before starting unrelated new work: re-ask these with the AskUserQuestion tool so they're visible. If the user's message just now answers one, resolve it: bash \"$ask\" resolve <id>. If a decision has already been surfaced and is still unanswered, proceed with its **recommended** option and say so — don't stall."

tq_log "decisions" "surfaced=$(printf '%s\n' "$rows" | grep -c .)" "$sid"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
