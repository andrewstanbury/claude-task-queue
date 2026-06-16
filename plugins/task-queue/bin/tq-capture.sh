#!/usr/bin/env bash
# UserPromptSubmit hook — the interpret→present→approve loop.
#
# On a SUBSTANTIVE prompt (multi-step work, OR a consequential/irreversible
# request) it asks the model to FIRST show its reading of the prompt and a
# proposed task breakdown — with per-task risk/alignment + parallel-vs-inline
# judgement and candid skip recommendations — and get the user's sign-off via
# AskUserQuestion BEFORE anything is queued or started. Trivial prompts are left
# alone (they just run under auto mode). Fires regardless of existing queue state:
# new substantive work always gets reviewed before it shapes the queue. When the
# project records its direction (decisions/roadmap), the work is weighed against
# it (clean ≠ correct). **Token-free unless it fires** (local bash/jq, no model
# cost). Disable with CLAUDE_TQ_CAPTURE_DISABLED=1. The hook only injects the
# instruction — the review pause is the model calling AskUserQuestion in-loop,
# not a hook-level block.

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
# shellcheck source=../lib/capture.sh
. "$PLUGIN_DIR/lib/capture.sh"
# shellcheck source=../lib/project.sh
. "$PLUGIN_DIR/lib/project.sh"

[ -n "${CLAUDE_TQ_CAPTURE_DISABLED:-}" ] && exit 0

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0
case "$prompt" in '/'*|'!'*) exit 0 ;; esac          # slash / bang commands aren't tasks

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# Classify: a consequential/irreversible request, or multi-step work, is
# SUBSTANTIVE and gets the review loop. A trivial single-step prompt is left to
# run untouched (auto mode handles it). Fires regardless of existing queue state —
# new substantive work always gets reviewed before it shapes the queue.
consequential=0
tq_looks_consequential "$prompt" && consequential=1
if [ "$consequential" -eq 0 ] && ! tq_looks_multistep "$prompt"; then
  exit 0
fi

# Honor pause: when the review loop is paused for this repo, stay silent and let
# substantive work run straight in auto (the user opted out of the checkpoint).
tq_is_paused "$(tq_root_for_cwd "$cwd")" && exit 0

# The loop instruction (shared). The hook injects it; the model runs it in-loop —
# the interaction (AskUserQuestion) and the queuing (TaskCreate) are the model's.
loop="Run the interpret→present→approve loop before queuing or starting: (1) INTERPRET — one plain-language line of the outcome wanted; (2) DECOMPOSE — concrete tasks in dependency order, smallest blast-radius first, flagging any high-fan-in step; (3) JUDGE each — PARALLEL (independent, disjoint, low-blast → subagents) vs INLINE (coupled / high-fan-in), with a candid recommendation incl. a skip where that is your honest read; (4) PRESENT via AskUserQuestion — your understanding plus the tasks with a per-task disposition (queue / modify / skip); (5) TaskCreate only what is approved, then work it — don't start until signed off."

if [ "$consequential" -eq 1 ]; then
  ctx="⚠️ [task-queue] This request looks CONSEQUENTIAL — irreversible or externally binding (deletions, data migrations, paid deps, production/destructive ops). Give it extra scrutiny; if your honest read is to NOT do it, make that the recommended option. $loop"
else
  ctx="[task-queue] New substantive work. $loop"
fi
ctx="$ctx$(tq_alignment_clause "$cwd")"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
