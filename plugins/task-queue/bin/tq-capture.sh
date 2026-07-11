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

# Missing jq → clean silent no-op (all parsing + the final emit use jq). Guard
# BEFORE the lib source, since a sourced lib enables `set -e`.
command -v jq >/dev/null 2>&1 || exit 0

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
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"
set +e   # tasks.sh enables `set -e`; this per-prompt hook is best-effort — a future
         # unguarded command must degrade to "no context injected", never break the prompt.

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

# A NEW prompt resets the away/solo auto-continue budget: each ask gets a fresh
# allowance of Stop-hook continuations (the counter in tq-verify bounds one prompt's
# autonomous drain, so it can't carry over and starve the next prompt). Best-effort.
rm -f "$(tq_away_continue_file "$sid")" 2>/dev/null || true

# ...and, if autopilot is ON, mark the owner PRESENT for this turn: a prompt is proof
# they're back at the keyboard, so THIS turn stays interactive (asks allowed, loop
# fires) even though autopilot keeps draining autonomously afterwards. Without this a
# note dropped mid-autopilot traps the session in "can't ask you, keep parking".
away=0
tq_is_away "$root" && { away=1; tq_mark_present "$sid"; }

# RETURN-REVIEW nudge: when autopilot turned OFF leaving a parked ❓ pile, tq-away.sh
# armed a review-pending marker and the PreToolUse guard blocks EDITS until it clears.
# But the guard only bites when the model tries to write — a turn of read-only work (or
# a zero-token `off` with no model turn) could sail past the one-time digest without ever
# presenting the pile. So while the marker is armed we re-raise the instruction on EVERY
# prompt (the moment the owner is back and typing), anchored FIRST, until the pile is
# empty. Conditional on the armed marker → zero steady-state per-prompt cost. Honors the
# same CLAUDE_TQ_REVIEW_GATE=0 escape as the guard. Self-heals a stale marker (pile
# cleared some other way) so it can't nag forever.
reviewnudge=""
if [ "${CLAUDE_TQ_REVIEW_GATE:-1}" != "0" ] && tq_review_pending "$root"; then
  if tq_repo_has_parked "$root"; then
    reviewnudge="🧷 [task-queue] Return-review PENDING — autopilot parked ❓ decisions for you. Present them FIRST this turn, BEFORE any other work: a blocking AskUserQuestion per ❓ [parked] item (2-3 concrete options, your recommended one first), apply their pick, and resolve each ❓ (TaskUpdate). Editing stays blocked until the ❓ pile is empty. (⏳ [blocked] items are just relayed, not gated — leave them parked.)"
  else
    tq_review_clear "$root"                          # pile already empty → retire the marker
  fi
fi

# OPEN-QUESTIONS reminder: if the user has answer-owed questions still open from
# earlier in this conversation (❓ tasks), surface them NOW — a new prompt is exactly
# when they get buried. Fires regardless of whether THIS prompt is substantive,
# trivial, or in solo mode. The model re-raises them and clears each (TaskUpdate) once
# answered or dropped. Disable with CLAUDE_TQ_OPEN_Q=0.
qreminder=""
if [ "${CLAUDE_TQ_OPEN_Q:-1}" != "0" ]; then
  openq="$(tq_open_questions "$sid" 2>/dev/null || true)"
  if [ -n "$openq" ]; then
    qn="$(printf '%s\n' "$openq" | grep -c .)"
    # CAP the list — autopilot parks decisions as ❓, so the pile grows, and this fires
    # EVERY prompt; show the first few and count the rest so a big pile can't bloat each
    # turn. Same shape as the SessionStart resume cap; a fixed 4 needs no env knob.
    qlist="$(printf '%s\n' "$openq" | head -n 4 | sed 's/^/  • /')"
    more=$(( qn - 4 ))
    [ "$more" -gt 0 ] && qlist="$qlist"$'\n'"  …and $more more (see the ❓ tasks)"
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
# Solo mode suppresses the loop. Either way the open-questions reminder above goes out.
consequential=0; design=0; paused=0
tq_looks_consequential "$prompt" && consequential=1
tq_looks_design "$prompt" && design=1
# Autopilot suppresses the loop ONLY while the owner is genuinely absent: the
# present-and-approve checkpoint can't fire mid-drain (the ask-guard hard-blocks
# AskUserQuestion), so injecting it would only spend tokens on an approval the model
# can't act on. But a fresh prompt means the owner is PRESENT for this turn (stamped
# above): the guard now lets the ask through, so keep the loop and flag the turn as
# owner-driven (present). Only the autonomous drain that follows stays suppressed.
present=0
if [ "$away" -eq 1 ]; then
  if tq_owner_present "$sid"; then present=1; else paused=1; fi
fi

# Design-preview gate: on a PRESENT visual/design turn, arm the per-session marker so
# the PreToolUse design guard blocks edits until a wireframe preview has been shown
# (show-before-build, so a visual change can't be coded before the owner sees it).
# Clear it otherwise — a non-design prompt (owner moved on) or an absent owner (autopilot
# parks design decisions, it doesn't gate the autonomous drain). Best-effort side effect.
if [ "$design" -eq 1 ] && [ "$paused" -eq 0 ]; then
  tq_design_set "$sid"
else
  tq_design_clear "$sid"
fi

# Agent-mode fan-out: when agent-mode is on and 2+ queued tasks are unblocked and
# independent (startable now, not ❓), NAME them and tell the model to fan them out to
# parallel subagents this turn. This is the timely, specific form of agent-mode — the
# hook does the independence analysis; the model still makes the Task calls (no hook can
# spawn agents). Rides alongside the loop; off unless the repo opted into agent-mode.
fanout=""
if tq_is_agent_mode "$root"; then
  ready="$(tq_ready_tasks "$sid" 2>/dev/null || true)"
  rn="$(printf '%s\n' "$ready" | grep -c . || true)"
  if [ "${rn:-0}" -ge 2 ]; then
    rlist="$(printf '%s\n' "$ready" | head -n 6 | sed 's/^/  • /')"
    [ "$rn" -gt 6 ] && rlist="$rlist"$'\n'"  …and $((rn - 6)) more"
    fanout="🤖 [task-queue] Agent-mode: $rn queued tasks are unblocked and independent — FAN THEM OUT to parallel subagents now (one Task each), unless they touch the same files (keep those inline):"$'\n'"$rlist"
  fi
fi

loopctx=""
if [ "$paused" -eq 0 ]; then
  # Record the INTENT OF RECORD for the outcome gate (tq-verify, Stop): the owner's
  # own words, replayed at "done" to check the change against the request. Best-
  # effort side effect; disabled with CLAUDE_TQ_INTENT_GATE=0.
  if [ "${CLAUDE_TQ_INTENT_GATE:-1}" != "0" ]; then
    { mkdir -p "$(tq_state_dir)" 2>/dev/null && printf '%s' "$prompt" > "$(tq_intent_file "$sid")"; } 2>/dev/null || true
  fi

  # AUTO-SEED the live queue (reliability fallback). The status line is only useful if
  # it reflects that you asked for work — but on models with the native task tools gated
  # off (Opus 4.8 / Sonnet 5 / Fable 5) the queue depends on the MODEL shelling out to
  # `tq`, which it does inconsistently, leaving the bar at 📋 0 on a real request. So when
  # a work prompt arrives and the queue is EMPTY, write ONE pending task capturing the
  # prompt — THROUGH bin/tq, the single writer (invariant preserved), stdout silenced so
  # it can't corrupt this hook's JSON. Fires only on an empty queue → a safety net, not a
  # second writer racing the model (which then refines/splits this seed per the reanchor).
  # Skipped while the return-review gate is armed (new work stays queued until ❓ clears).
  # Best-effort; disable with CLAUDE_TQ_AUTOSEED=0.
  if [ "${CLAUDE_TQ_AUTOSEED:-1}" != "0" ] && [ -z "$reviewnudge" ] && ! tq_has_open_tasks "$sid"; then
    seed="$(printf '%s' "$prompt" | tr '\n' ' ' | sed 's/  */ /g')"
    [ "${#seed}" -gt 72 ] && seed="${seed:0:71}…"
    CLAUDE_TQ_SESSION_ID="$sid" "$PLUGIN_DIR/bin/tq" add "$seed" >/dev/null 2>&1 || true
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
  reanchor="New work — interpret it (one plain line), decompose into tasks in dependency order (smallest blast-radius first), TaskCreate them, and work it IN AUTO, per the queue loop from this session's SessionStart policy. Pause for AskUserQuestion sign-off ONLY on real signal — ambiguous, high blast-radius, an architectural/assumption fork (present recommended options), or you'd recommend against it; otherwise just proceed. Challenge the ask itself when your honest read says so. Be selective — don't manufacture pushback."

  # `reanchor_lean` — the DEFAULT path when the standing policy is recorded in the
  # repo's CLAUDE.md (always loaded), so a full re-anchor every prompt would just
  # re-spend tokens on what the model already has. A terse POINTER instead: the single
  # biggest per-prompt saving. The heavy consequential/design variants below still
  # fire in full (their just-in-time detail isn't in CLAUDE.md).
  reanchor_lean="New work → interpret, decompose (smallest blast-radius first), TaskCreate, work in auto; AskUserQuestion only on real signal (ambiguous / high blast-radius / design or architectural fork / you'd advise against). Per CLAUDE.md policy."

  # `loop` — the HEAVY variant, for the deterministic high-stakes signal only
  # (consequential below). Here the full present-and-approve + critique earns its
  # tokens because the cost of getting it wrong is high and irreversible.
  loop="EVALUATE before executing — don't just comply: steelman the ask, then challenge it. Flag any contradiction with the project's recorded constraints or the owner's own earlier requests, and any way the ask (or a constraint behind it) forces a poor or over-engineered design; if your honest read is that part or all shouldn't be done, recommend against it. Be SELECTIVE — raise a concern only on real signal; manufactured objections train rubber-stamping. Then run the interpret→present→approve loop before queuing or starting, scaled to the work: (1) INTERPRET — one plain-language line of the outcome wanted; (2) DECOMPOSE — concrete tasks in dependency order, smallest blast-radius first, flagging any high-fan-in step; (3) JUDGE each — PARALLEL (independent, disjoint, low-blast → subagents) vs INLINE (coupled / high-fan-in), with a candid recommendation incl. a skip where that is your honest read; (4) PRESENT — for a few obvious low-risk tasks a brief inline plan + one-line confirmation is enough; use AskUserQuestion (per-task queue / modify / skip) for larger or higher-risk work, naming on any conflicting option the recorded requirement it would retire so it isn't picked blind; (5) APPROVE — TaskCreate only what is approved, then work it; don't start until signed off."

  # Visual changes get the "demonstrate before build" treatment — show the design as
  # a wireframe so the owner (non-technical) can SEE and pick before any code is
  # written. Rides AskUserQuestion's native keyboard nav + preview — no custom UI.
  design_loop="This is a VISUAL/design change, and the owner is non-technical — they verify by SEEING, not by reading code, so SHOW the design before you build it: (1) INTERPRET the design intent in one plain line; (2) produce a RECOMMENDED design plus 2-3 meaningfully different alternatives; (3) PRESENT them with AskUserQuestion, giving each option a 'preview' that is a FAITHFUL WIREFRAME mockup of that layout — real elements in their relative position/size with real labels — drawn in the project's WIREFRAME convention so it reads by visual weight: a heavy box border (╔═╗ ║ ╚╝) for a container/card/panel, ▒ shading for an input or editable field, █ fill for the primary/emphasis element (e.g. the main button or active item), and plain text for labels and secondary links. When a screen already exists, include one preview of the CURRENT state in the same convention to compare against; put the recommended option FIRST and mark its label '(Recommended)'. The owner moves between options with the arrow keys and presses Enter to pick one; (4) build ONLY the selected option (decompose it into tasks first if it's multi-step). Do not write code until they've chosen."

  if [ "$consequential" -eq 1 ]; then
    loopctx="⚠️ [task-queue] This request looks CONSEQUENTIAL — irreversible or externally binding (deletions, data migrations, paid deps, production/destructive ops). Give it extra scrutiny and use the FULL AskUserQuestion present-and-approve regardless of size; if your honest read is to NOT do it, make that the recommended option. $loop"
    [ "$design" -eq 1 ] && loopctx="$loopctx It also changes the UI: present the proposed design as faithful WIREFRAME mockups in the AskUserQuestion preview — heavy border (╔═╗) for a container, ▒ for an input field, █ for the primary element — recommended option first, arrow-keys + Enter to pick, so the owner can see it before you build."
    loopctx="$loopctx$(tq_alignment_clause "$cwd")"
  elif [ "$design" -eq 1 ]; then
    loopctx="[task-queue] Design change. $design_loop$(tq_alignment_clause "$cwd")"
  elif tq_policy_documented "$root"; then
    # DEFAULT path, policy already in the always-loaded CLAUDE.md: a terse POINTER, not
    # the full re-anchor — the biggest per-prompt token saving. No alignment clause
    # either (SessionStart already hydrates the backlog + weighs recorded decisions).
    loopctx="[task-queue] $reanchor_lean"
  else
    # DEFAULT path, policy NOT documented: carry the full re-anchor + alignment clause.
    loopctx="[task-queue] $reanchor$(tq_alignment_clause "$cwd")"
  fi

  # Owner-driven turn under autopilot: the standing SessionStart banner says "never
  # ask", but a prompt just arrived — they're here for THIS turn. Prepend a note that
  # overrides the banner (ask if you genuinely need their call; parking resumes for the
  # autonomous drain after). Only fires in the away+present case, so the normal-path
  # budgets are untouched.
  if [ "$present" -eq 1 ]; then
    loopctx="🙋 [task-queue] Autopilot is ON but a prompt just arrived — the owner is AT the keyboard for THIS turn, overriding the standing \"never ask\" banner: engage normally and ASK (AskUserQuestion) if you genuinely need their call; parking resumes for the drain after. $loopctx"
  fi
fi

# Combine the injected blocks. The return-review nudge LEADS when armed (it must be the
# model's first action this turn); then the open-questions reminder + agent fan-out (both
# ride alongside, if any); then the loop instruction. When the review nudge IS armed the
# loop instruction is DROPPED: "queue this new work" directly contradicts "present the ❓
# pile FIRST, before any other work" (editing is blocked anyway until the pile clears), so
# injecting it only spends tokens on an instruction the model can't act on this turn. The
# loop's side effects (intent record, design-gate arming) already ran above, unaffected.
ctx="$reviewnudge"
if [ -n "$qreminder" ]; then
  [ -n "$ctx" ] && ctx="$ctx"$'\n\n'
  ctx="$ctx$qreminder"
fi
if [ -n "$fanout" ]; then
  [ -n "$ctx" ] && ctx="$ctx"$'\n\n'
  ctx="$ctx$fanout"
fi
if [ -n "$loopctx" ] && [ -z "$reviewnudge" ]; then
  [ -n "$ctx" ] && ctx="$ctx"$'\n\n'
  ctx="$ctx$loopctx"
fi
[ -n "$ctx" ] || exit 0

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
