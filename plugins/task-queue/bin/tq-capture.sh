#!/usr/bin/env bash
# UserPromptSubmit hook — the interpret→decompose→queue loop (split from interrupt).
#
# Fires on EVERY prompt (owner decision 2026-06-26 — the precision "only multi-step
# fires" filter was removed so all prompts route through the queue), but SPLIT from
# the interrupt (2026-06-27): the DEFAULT path injects a lean re-anchor — interpret,
# decompose, TaskCreate, work it IN AUTO — and hands the sign-off (AskUserQuestion)
# decision to the model, which has read the prompt and can judge blast radius a
# regex can't. It surfaces a present-and-approve only on real signal (ambiguous,
# high blast-radius, or it'd recommend against the ask). The full procedure +
# critique posture it re-anchors to ride the SessionStart policy, stated ONCE per
# session (tq-resume.sh) — not re-injected per prompt, which keeps the per-prompt
# budget lean while preserving 100% capture. The HEAVY present-and-approve + critique
# variant fires only on the deterministic high-stakes signal — CONSEQUENTIAL
# (irreversible/binding) and DESIGN (visual, show-first) — where the cost of getting
# it wrong justifies the tokens and the interruption. Slash/bang and empty prompts
# are skipped (not user work). When the project records its direction
# (decisions/roadmap), the work is weighed against it (clean ≠ correct).
# **Token-free to classify** (local bash/jq, no model cost). Disable with
# CLAUDE_TQ_CAPTURE_DISABLED=1. The hook only injects the instruction — the review
# pause is the model calling AskUserQuestion in-loop, not a hook-level block.

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
root="$(tq_root_for_cwd "$cwd")"

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
    # Terse on purpose: the how-to (re-raise, mark done via TaskUpdate) lives in the
    # SessionStart policy, so this recurring per-prompt nudge carries only the LIST.
    qreminder="↩ [task-queue] $qn unanswered question(s) still open — re-raise before continuing:"$'\n'"$qlist"
  fi
fi

# Classify for ROUTING, not gating: EVERY prompt gets a loop instruction (owner
# decision 2026-06-26 — all prompts are interpreted, decomposed, and queued; the
# old multi-step "trivial stays silent" filter was removed). consequential/design
# select WHICH variant fires: the deterministic high-stakes signal gets the HEAVY
# present-and-approve + critique; everything else gets the LEAN re-anchor that
# delegates the interrupt decision to the model (split-from-interrupt, 2026-06-27).
# Pause suppresses the loop. Either way the open-questions reminder above goes out.
consequential=0; design=0; paused=0
tq_looks_consequential "$prompt" && consequential=1
tq_looks_design "$prompt" && design=1
# (Godot design-preview suppression removed at owner's request — UI/visual prompts
# now get the wireframe demonstrate-before-build flow in Godot projects too.)
tq_is_paused "$root" && paused=1

loopctx=""
if [ "$paused" -eq 0 ]; then
  # Record the INTENT OF RECORD for the outcome gate (tq-verify, Stop): the owner's
  # own words, replayed at "done" to check the change against the request. Best-
  # effort side effect; disabled with CLAUDE_TQ_INTENT_GATE=0.
  if [ "${CLAUDE_TQ_INTENT_GATE:-1}" != "0" ]; then
    { mkdir -p "$(tq_state_dir)" 2>/dev/null && printf '%s' "$prompt" > "$(tq_intent_file "$sid")"; } 2>/dev/null || true
  fi

  # Two instructions. The hook injects one; the model runs it in-loop — the
  # interaction (AskUserQuestion) and the queuing (TaskCreate) are the model's.
  #
  # `reanchor` — the DEFAULT path (split-loop-from-interrupt, 2026-06-27). It does
  # NOT re-inject the full procedure (that rides the SessionStart policy, once);
  # it re-anchors to it and hands the INTERRUPT decision to the model, which —
  # unlike a per-prompt regex — has actually read the prompt and can judge blast
  # radius. So: interpret + queue + run in auto; surface AskUserQuestion only on
  # real signal. This keeps the per-prompt budget lean while preserving 100% capture.
  reanchor="New work — interpret it (one plain line), decompose into tasks in dependency order (smallest blast-radius first), TaskCreate them, and work it IN AUTO, per the queue loop from this session's SessionStart policy. Pause for AskUserQuestion sign-off ONLY on real signal — genuinely ambiguous, high blast-radius, or you'd recommend against it; otherwise just proceed. Be selective; don't manufacture pushback."

  # `loop` — the HEAVY variant, for the deterministic high-stakes signal only
  # (consequential below). Here the full present-and-approve + critique earns its
  # tokens because the cost of getting it wrong is high and irreversible.
  loop="EVALUATE before executing — don't just comply: steelman the ask, then challenge it. Flag any contradiction with the project's recorded constraints or the owner's own earlier requests, and any way the ask (or a constraint behind it) forces a poor or over-engineered design; if your honest read is that part or all shouldn't be done, recommend against it. Be SELECTIVE — raise a concern only on real signal; manufactured objections train rubber-stamping. Then run the interpret→present→approve loop before queuing or starting, scaled to the work: (1) INTERPRET — one plain-language line of the outcome wanted; (2) DECOMPOSE — concrete tasks in dependency order, smallest blast-radius first, flagging any high-fan-in step; (3) JUDGE each — PARALLEL (independent, disjoint, low-blast → subagents) vs INLINE (coupled / high-fan-in), with a candid recommendation incl. a skip where that is your honest read; (4) PRESENT — for a few obvious low-risk tasks a brief inline plan + one-line confirmation is enough; use AskUserQuestion (per-task queue / modify / skip) for larger or higher-risk work; (5) APPROVE — TaskCreate only what is approved, then work it; don't start until signed off."

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
    loopctx="[task-queue] $reanchor"
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
