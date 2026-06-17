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
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"

# OPEN-QUESTIONS reminder: if the user has answer-owed questions still open from
# earlier in this conversation (❓ tasks), surface them NOW — a new prompt is exactly
# when they get buried. Fires regardless of whether THIS prompt is substantive,
# trivial, or paused. The model re-raises them and clears each (TaskUpdate) once
# answered or dropped. Disable with CLAUDE_TQ_OPEN_Q=0.
qreminder=""
if [ "${CLAUDE_TQ_OPEN_Q:-1}" != "0" ]; then
  openq="$(tq_open_questions "$sid" 2>/dev/null || true)"
  if [ -n "$openq" ]; then
    qn="$(printf '%s\n' "$openq" | grep -c .)"
    qlist="$(printf '%s\n' "$openq" | sed 's/^/  • /')"
    qreminder="↩ [task-queue] Before this — the user has $qn unanswered question(s) still open from earlier (they may have moved on without answering):"$'\n'"$qlist"$'\n'"Re-raise them in plain language so they're not lost; mark each done (TaskUpdate) once it's answered or explicitly dropped."
  fi
fi

# Classify: a consequential/irreversible request, multi-step work, or a VISUAL
# change is SUBSTANTIVE and gets the review loop. A trivial single-step prompt runs
# untouched (auto handles it). Pause suppresses the loop. Either way the open-
# questions reminder above still goes out.
consequential=0; design=0; substantive=1; paused=0
tq_looks_consequential "$prompt" && consequential=1
tq_looks_design "$prompt" && design=1
if [ "$consequential" -eq 0 ] && [ "$design" -eq 0 ] && ! tq_looks_multistep "$prompt"; then substantive=0; fi
tq_is_paused "$(tq_root_for_cwd "$cwd")" && paused=1

loopctx=""
if [ "$substantive" -eq 1 ] && [ "$paused" -eq 0 ]; then
  # Record the INTENT OF RECORD for the outcome gate (tq-verify, Stop): the owner's
  # own words, replayed at "done" to check the change against the request. Best-
  # effort side effect; disabled with CLAUDE_TQ_INTENT_GATE=0.
  if [ "${CLAUDE_TQ_INTENT_GATE:-1}" != "0" ]; then
    { mkdir -p "$(tq_state_dir)" 2>/dev/null && printf '%s' "$prompt" > "$(tq_intent_file "$sid")"; } 2>/dev/null || true
  fi

  # The loop instruction (shared). The hook injects it; the model runs it in-loop —
  # the interaction (AskUserQuestion) and the queuing (TaskCreate) are the model's.
  loop="Run the interpret→present→approve loop before queuing or starting, scaled to the work: (1) INTERPRET — one plain-language line of the outcome wanted; (2) DECOMPOSE — concrete tasks in dependency order, smallest blast-radius first, flagging any high-fan-in step; (3) JUDGE each — PARALLEL (independent, disjoint, low-blast → subagents) vs INLINE (coupled / high-fan-in), with a candid recommendation incl. a skip where that is your honest read; (4) PRESENT — for a few obvious low-risk tasks a brief inline plan + one-line confirmation is enough; use AskUserQuestion (per-task queue / modify / skip) for larger or higher-risk work; (5) APPROVE — TaskCreate only what is approved, then work it; don't start until signed off."

  # Visual changes get the "demonstrate before build" treatment — show the design as
  # a wireframe so the owner (non-technical) can SEE and pick before any code is
  # written. Rides AskUserQuestion's native keyboard nav + preview — no custom UI.
  design_loop="This is a VISUAL/design change, and the owner is non-technical — they verify by SEEING, not by reading code, so SHOW the design before you build it: (1) INTERPRET the design intent in one plain line; (2) produce a RECOMMENDED design plus 2-3 meaningfully different alternatives; (3) PRESENT them with AskUserQuestion, giving each option a 'preview' that is a FAITHFUL WIREFRAME mockup of that layout — real elements in their relative position/size with real labels — drawn in the project's WIREFRAME convention so it reads by visual weight: a heavy box border (╔═╗ ║ ╚╝) for a container/card/panel, ▒ shading for an input or editable field, █ fill for the primary/emphasis element (e.g. the main button or active item), and plain text for labels and secondary links. When a screen already exists, include one preview of the CURRENT state in the same convention to compare against; put the recommended option FIRST and mark its label '(Recommended)'. The owner moves between options with the arrow keys and presses Enter to pick one; (4) build ONLY the selected option (decompose it into tasks first if it's multi-step). Do not write code until they've chosen."

  if [ "$consequential" -eq 1 ]; then
    loopctx="⚠️ [task-queue] This request looks CONSEQUENTIAL — irreversible or externally binding (deletions, data migrations, paid deps, production/destructive ops). Give it extra scrutiny and use the FULL AskUserQuestion present-and-approve regardless of size; if your honest read is to NOT do it, make that the recommended option. $loop"
    [ "$design" -eq 1 ] && loopctx="$loopctx It also changes the UI: present the proposed design as faithful WIREFRAME mockups in the AskUserQuestion preview — heavy border (╔═╗) for a container, ▒ for an input field, █ for the primary element — recommended option first, arrow-keys + Enter to pick, so the owner can see it before you build."
  elif [ "$design" -eq 1 ]; then
    loopctx="[task-queue] Design change. $design_loop"
  else
    loopctx="[task-queue] New substantive work. $loop"
  fi
  loopctx="$loopctx$(tq_alignment_clause "$cwd")"
fi

# Combine the open-questions reminder (always, if any) with the loop instruction.
ctx="$qreminder"
if [ -n "$loopctx" ]; then
  [ -n "$ctx" ] && ctx="$ctx"$'\n\n'
  ctx="$ctx$loopctx"
fi
[ -n "$ctx" ] || exit 0

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
