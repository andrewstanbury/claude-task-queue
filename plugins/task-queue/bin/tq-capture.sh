#!/usr/bin/env bash
# UserPromptSubmit hook — proactively nudge task capture, but ONLY when it helps.
#
# Silent on almost every prompt. It speaks up only when the prompt looks like
# multi-step work AND the session's task queue is empty — i.e. exactly when work
# should be captured but hasn't been. When it does fire, and the project records
# its direction (decisions/ADRs, roadmap/backlog), it also asks the model to
# weigh the work against that direction before capturing — alignment at capture
# time (clean ≠ correct). **Token-free unless it fires** (the checks are local
# bash/jq, no model cost), which is what makes it safe to run per prompt — unlike
# the old unconditional UserPromptSubmit that was removed.
# Disable entirely with CLAUDE_TQ_CAPTURE_DISABLED=1.

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
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0
case "$prompt" in '/'*|'!'*) exit 0 ;; esac          # slash / bang commands aren't tasks

[ "$(tq_open_count "$sid")" -eq 0 ] || exit 0         # already have a queue → don't nudge
tq_looks_multistep "$prompt" || exit 0                # not multi-step → stay silent

ctx="[task-queue] This looks like multi-step work and your task queue is empty — capture the steps with TaskCreate in dependency order before starting, so they show up in the queue and auto-advance as you finish each. Sequence to contain blast radius: smallest-reach steps first, and flag any step touching a widely-depended-on (high-fan-in) module so its dependents get covered."

# Alignment (clean ≠ correct): if the project records its direction, weigh the
# work against it AS it's captured, so a new task doesn't silently contradict a
# recorded decision or drift from the backlog. This is the orchestration arm of
# charter's decisions anchor. Costs nothing unless the nudge already fires — the
# docs are only resolved on this path, with local file checks (no model cost).
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"
dpath="$(tq_decisions_path "$root" 2>/dev/null || true)"
rpath="$(tq_roadmap_path "$root" 2>/dev/null || true)"
anchor=""
[ -n "$dpath" ] && anchor="recorded decisions ($dpath)"
[ -n "$rpath" ] && { [ -n "$anchor" ] && anchor="$anchor and the backlog ($rpath)" || anchor="the backlog ($rpath)"; }
[ -n "$anchor" ] && ctx="$ctx"$' '"First weigh it against $anchor — flag any drift or contradiction (don't reverse a recorded decision) before you capture."

tq_log "capture" "nudged (multi-step, empty queue$( [ -n "$anchor" ] && printf ', aligned' ))" "$sid"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
