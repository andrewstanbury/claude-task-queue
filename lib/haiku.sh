#!/usr/bin/env bash
# Haiku triage caller. Sends the user prompt plus context (project profile,
# active queue snapshot) to Claude Haiku via `claude -p --model haiku-4-5` and
# parses an ordered list of tasks back.
#
# On any failure (timeout, bad JSON, non-zero exit) we fall back to a single
# pending task that just restates the original prompt — that way the queue
# always gets populated and the user can decide how to proceed manually.
#
# Suppressing nested hooks: the recursive `claude -p` invocation would re-fire
# our own UserPromptSubmit + audit-rules + stack-lint hooks. We disable them
# for the inner call so triage stays cheap and predictable.

set -euo pipefail

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./queue.sh
. "$THIS_DIR/queue.sh"

# Build the JSON request body that gets sent to Haiku. Keeps the system prompt
# small + deterministic so the model returns parseable output.
tq_haiku_build_prompt() {
  local user_prompt="$1"
  local project_profile="$2"
  local queue_snapshot="$3"

  jq -n \
    --arg user "$user_prompt" \
    --arg profile "$project_profile" \
    --arg queue "$queue_snapshot" \
    '
    "You are a task decomposer for Claude Code.\n" +
    "Break the user prompt into an ordered list of small, individually-shippable tasks.\n" +
    "Order tasks for Claude'\''s cache: cluster tasks touching related files together. Prereqs first.\n" +
    "Each task gets: subject (imperative, <80 chars), est (S/M/L), tokenEst (rough int), blockedBy (list of prior task ids in this list, or []), attachedRules ([]), recommendedParallel (bool — true only if the task can run in parallel with the prior task w/o dependency).\n" +
    "Quality: every UI task should mention reusing existing primitives. Every input/auth task should flag OWASP. Every web a11y task should flag WCAG.\n" +
    "Output ONLY a JSON array. No prose, no markdown fences. Each element is { \"subject\": ..., \"est\": ..., \"tokenEst\": ..., \"blockedBy\": [...], \"attachedRules\": [...], \"recommendedParallel\": ... }.\n" +
    "If the prompt is a single trivial action, return a one-element array.\n\n" +
    "PROJECT PROFILE:\n" + $profile + "\n\n" +
    "EXISTING QUEUE (for context — do not duplicate):\n" + $queue + "\n\n" +
    "USER PROMPT:\n" + $user
    '
}

# Detect basic project profile (stack hints) from cwd. Cheap heuristics —
# Haiku doesn't need a full audit, just enough to choose the right rules.
tq_project_profile() {
  local cwd="${1:-$PWD}"
  local out=""
  [ -f "$cwd/package.json" ] && out+="js/ts (package.json present); "
  [ -f "$cwd/go.mod" ] && out+="go (go.mod present); "
  [ -f "$cwd/Cargo.toml" ] && out+="rust (Cargo.toml present); "
  [ -f "$cwd/requirements.txt" ] || [ -f "$cwd/pyproject.toml" ] && out+="python; "
  if [ -f "$cwd/package.json" ] && grep -q '"react-native"' "$cwd/package.json" 2>/dev/null; then
    out+="react-native; "
  elif [ -f "$cwd/package.json" ] && grep -q '"react"' "$cwd/package.json" 2>/dev/null; then
    out+="react/web; "
  fi
  printf '%s' "${out:-unknown stack}"
}

# Call Haiku, append parsed tasks to the queue, print appended ids one per
# line on stdout. Returns 0 on success (even partial), 1 on hard failure.
tq_haiku_triage() {
  local user_prompt="${1:?prompt required}"

  # Caller-level kill switch.
  [ "${CLAUDE_TQ_HAIKU_DISABLED:-0}" = "1" ] && return 1

  local profile queue_snapshot
  profile="$(tq_project_profile)"
  queue_snapshot="$(tq_list | head -50 || true)"
  [ -z "$queue_snapshot" ] && queue_snapshot="(empty)"

  local triage_prompt
  triage_prompt="$(tq_haiku_build_prompt "$user_prompt" "$profile" "$queue_snapshot")"

  # Suppress nested hook re-entry on the recursive `claude -p` call.
  local response
  response="$(
    CLAUDE_TQ_DISABLED=1 \
    CLAUDE_TQ_PRETOOL_DISABLED=1 \
    CLAUDE_INTENT_CONFIRM_DISABLED=1 \
    CLAUDE_AUDIT_RULES_DISABLED=1 \
    CLAUDE_STACK_LINT_DISABLED=1 \
    timeout 45 claude -p "$triage_prompt" --model haiku-4-5 2>/dev/null || true
  )"

  if [ -z "$response" ]; then
    return 1
  fi

  # The model occasionally wraps the array in ```json fences despite the
  # instruction. Strip them defensively before parsing.
  local cleaned
  cleaned="$(printf '%s' "$response" | sed -E 's/^```(json)?//; s/```$//' | tr -d '\r')"

  # Validate top-level shape.
  if ! printf '%s' "$cleaned" | jq -e 'type == "array"' >/dev/null 2>&1; then
    return 1
  fi

  # Append each task. Map model-supplied blockedBy ints (1-indexed within the
  # array) to our queue's id space — translate via an index→id table built
  # as we append.
  local idx=0
  local -a model_to_real=()
  local appended_any=0

  while IFS= read -r task_json; do
    [ -z "$task_json" ] && continue
    idx=$((idx + 1))

    local subject est token_est parallel
    subject="$(printf '%s' "$task_json" | jq -r '.subject // empty')"
    [ -z "$subject" ] && continue
    est="$(printf '%s' "$task_json" | jq -r '.est // "M"')"
    token_est="$(printf '%s' "$task_json" | jq -r '.tokenEst // 0')"
    parallel="$(printf '%s' "$task_json" | jq -r '.recommendedParallel // false')"

    # Translate model-relative blockedBy.
    local blocked_csv=""
    local raw_blocked
    raw_blocked="$(printf '%s' "$task_json" | jq -r '.blockedBy // [] | .[]' 2>/dev/null || true)"
    while IFS= read -r b; do
      [ -z "$b" ] && continue
      local model_b="$b"
      # 1-indexed → 0-indexed array offset
      local arr_idx=$((model_b - 1))
      if [ "$arr_idx" -ge 0 ] && [ "$arr_idx" -lt "${#model_to_real[@]}" ]; then
        blocked_csv+="${model_to_real[$arr_idx]},"
      fi
    done <<< "$raw_blocked"
    blocked_csv="${blocked_csv%,}"

    local attached_csv
    attached_csv="$(printf '%s' "$task_json" | jq -r '.attachedRules // [] | join(",")')"

    local real_id
    real_id="$(tq_append "$subject" "$est" "$token_est" "$blocked_csv" "$attached_csv" "$parallel")"
    model_to_real+=("$real_id")
    printf '%s\n' "$real_id"
    appended_any=1
  done < <(printf '%s' "$cleaned" | jq -c '.[]')

  [ "$appended_any" -eq 1 ]
}

# When invoked directly, read prompt from stdin and triage.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  prompt_in="$(cat)"
  if tq_haiku_triage "$prompt_in"; then
    exit 0
  else
    exit 1
  fi
fi
