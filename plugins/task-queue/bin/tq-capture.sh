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

cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# Consent on the consequential (takes precedence — fires regardless of queue
# state or step count). An irreversible / externally-binding request shouldn't
# silently shape the queue: have the model show its reading of the prompt and get
# the owner's go-ahead BEFORE any of it is queued or started. The hook only
# surfaces the instruction — the review pause is the model voluntarily calling
# AskUserQuestion in-loop, NOT a hook-level block (the heavyweight destructive
# gate stays out per docs/ROADMAP.md "Decided against"; this is its prompt-time,
# decomposition-review complement to charter's just-in-time action surfacing).
if tq_looks_consequential "$prompt"; then
  ctx="[task-queue] This prompt looks CONSEQUENTIAL — irreversible or externally binding (e.g. deletions, data migrations, paid deps, production or destructive ops). Before queuing or starting ANY of it: decompose it into the concrete tasks you would run, then present them to the owner for sign-off via AskUserQuestion — one disposition per task (add to queue / modify / skip) plus your honest recommendation, which may be that none of it should be queued. TaskCreate ONLY what they approve, and don't start the work until they have. If your honest read is 'don't do this', make that the recommended option."
  ctx="$ctx$(tq_alignment_clause "$cwd")"
  jq -cn --arg c "$ctx" \
    '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
  exit 0
fi

[ "$(tq_open_count "$sid")" -eq 0 ] || exit 0         # already have a queue → don't nudge
tq_looks_multistep "$prompt" || exit 0                # not multi-step → stay silent

ctx="[task-queue] This looks like multi-step work and your task queue is empty — capture the steps with TaskCreate in dependency order before starting, so they show up in the queue and auto-advance as you finish each. Sequence to contain blast radius: smallest-reach steps first, and flag any step touching a widely-depended-on (high-fan-in) module so its dependents get covered."

# Alignment (clean ≠ correct): if the project records its direction, weigh the
# work against it AS it's captured, so a new task doesn't silently contradict a
# recorded decision or drift from the backlog. Costs nothing unless the nudge
# already fires — the docs are only resolved here, with local file checks.
align="$(tq_alignment_clause "$cwd")"
ctx="$ctx$align"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "UserPromptSubmit", additionalContext: $c}}'
