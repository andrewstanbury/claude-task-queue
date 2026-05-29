#!/usr/bin/env bash
# Decide whether a freshly-submitted prompt warrants Haiku triage. Cheap, fully
# local — we only pay for the Haiku call on prompts that look like multi-step
# work. Trivial / slash / bang / direct-confirmation prompts skip the call.
#
# Exit codes are advisory:
#   0 → non-trivial — caller should run Haiku
#   1 → trivial — caller should skip
#
# Heuristics (intentionally simple — over-classifying as non-trivial just adds
# Haiku cost, never harms correctness):
#   - skip blank / /slash / !bang prompts outright
#   - skip very short prompts (≤4 words) — typically yes/no answers
#   - flag if prompt contains any of the action verbs in the pattern below
#   - flag if prompt is over 25 words even without an explicit verb
#   - flag if prompt contains 2+ "and"s (compound request)
#
# Deliberately NOT using `set -euo pipefail`: this is a sourced library, and
# `pipefail` interacts badly with `grep` returning 1 on no-match (the and_count
# branch would abort before the verb check ran). The function's own logic
# handles all the conditions explicitly via `return` codes.

tq_classify() {
  local prompt="${1:-}"
  local trimmed
  trimmed="$(printf '%s' "$prompt" | sed -E 's/^[[:space:]]+|[[:space:]]+$//g')"

  # Blank / slash / bang — never trigger.
  case "$trimmed" in
    "") return 1 ;;
    /*) return 1 ;;
    !*) return 1 ;;
  esac

  local word_count
  word_count="$(printf '%s' "$trimmed" | wc -w | tr -d '[:space:]')"

  # Direct confirmations / very short answers.
  if [ "$word_count" -le 4 ]; then
    return 1
  fi

  # Compound request (two or more conjunctions). Word-boundary match so "AND"
  # in the middle of identifiers is ignored.
  local and_count
  and_count="$(printf '%s' " $trimmed " | tr '[:upper:]' '[:lower:]' \
    | grep -oE ' and ' | wc -l | tr -d '[:space:]')"
  if [ "$and_count" -ge 2 ]; then
    return 0
  fi

  # Action verbs that almost always mean "do work."
  local lower
  lower="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$lower" | grep -qE '\b(build|implement|add|fix|refactor|design|create|set up|setup|wire|extend|migrate|rewrite|audit|review|investigate|debug|optimize|integrate|deploy|ship|release|test|write|update|generate)\b'; then
    return 0
  fi

  # Long-prompt fallback.
  if [ "$word_count" -ge 25 ]; then
    return 0
  fi

  return 1
}

# Detect an explicit planning trigger: a "plan:" or "plan " prefix means the
# user is deliberately asking to (re)decompose, so triage should fire even when
# actionable work already exists. Prints the prompt with the trigger stripped
# on a match, or the prompt unchanged on no match — so the caller can capture
# the text and the decision in one call:
#
#   if triage_text="$(tq_plan_trigger "$prompt")"; then plan_trigger=1; fi
#
# Returns 0 on a trigger match, 1 otherwise.
tq_plan_trigger() {
  local prompt="${1:-}"
  local lower
  lower="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]')"
  case "$lower" in
    plan:*|"plan "*)
      printf '%s' "$prompt" | sed -E 's/^[[:space:]]*[Pp][Ll][Aa][Nn][[:space:]:]+//'
      return 0
      ;;
  esac
  printf '%s' "$prompt"
  return 1
}

# Decide whether to run the paid Haiku triage. Pure boolean logic over three
# already-computed signals, so it's unit-testable without touching Haiku:
#   $1 non_trivial    (1/0) — classifier said this is real work
#   $2 plan_trigger   (1/0) — user prefixed "plan:"
#   $3 has_actionable (1/0) — queue already has an unblocked pending task
#
# Triage fires when the user explicitly asked to plan, OR the work is
# non-trivial AND there's nothing actionable queued. This is the core fix for
# "every non-trivial prompt forks Haiku and stacks more tasks": once a plan
# exists, follow-up prompts no longer silently spawn work.
tq_should_triage() {
  local non_trivial="${1:-0}" plan_trigger="${2:-0}" has_actionable="${3:-0}"
  [ "$plan_trigger" = "1" ] && return 0
  [ "$non_trivial" = "1" ] && [ "$has_actionable" = "0" ] && return 0
  return 1
}

# Allow direct sourcing or invocation.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  prompt="$(cat)"
  if tq_classify "$prompt"; then
    printf 'non-trivial\n'
    exit 0
  else
    printf 'trivial\n'
    exit 1
  fi
fi
