#!/usr/bin/env bats
#
# Tests for the conditional UserPromptSubmit capture hook (bin/tq-capture.sh).
# It must be SILENT unless the prompt is multi-step AND the session queue is
# empty. Everything faked via CLAUDE_TQ_* overrides.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CAPTURE="$ROOT/bin/tq-capture.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_LOG_DIR="$(mktemp -d)"
  unset CLAUDE_TQ_CAPTURE_DISABLED
}

teardown() { rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_LOG_DIR"; }

make_task() {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" '{id:$id, subject:"x", status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$1/$2.json"
}

run_capture() {
  local prompt="$1" sid="${2:-sess}" json
  json="$(jq -nc --arg p "$prompt" --arg s "$sid" '{prompt:$p, session_id:$s}')"
  printf '%s' "$json" | "$CAPTURE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "nudges on a multi-step prompt when the queue is empty" {
  run run_capture "Add the login form and then wire the auth endpoint and update the tests"
  [[ "$output" == *"capture the steps with TaskCreate"* ]]
}

@test "silent when the queue already has an open task" {
  make_task sess 1 pending
  run run_capture "Add the login form and then wire the auth endpoint and update tests"
  [ -z "$output" ]
}

@test "silent when all tasks are completed but a fresh multi-step prompt arrives" {
  make_task sess 1 completed     # completed files linger but aren't "open"
  run run_capture "Add the login form and then wire the auth endpoint and update tests"
  [[ "$output" == *"TaskCreate"* ]]   # completed ones don't count as a queue → nudge
}

@test "silent on a short prompt" {
  run run_capture "fix the typo"
  [ -z "$output" ]
}

@test "silent on a slash command even if long and multi-versed" {
  run run_capture "/refactor add build and update everything and then test it"
  [ -z "$output" ]
}

@test "can be disabled with CLAUDE_TQ_CAPTURE_DISABLED" {
  export CLAUDE_TQ_CAPTURE_DISABLED=1
  run run_capture "Add X and then build Y and update Z and refactor W"
  [ -z "$output" ]
}

@test "multi-step heuristic fires on connectives, lists, and 2+ verbs; not on a single short action" {
  src='. "$1/lib/tasks.sh"; . "$1/lib/capture.sh";'
  run bash -c "$src"' tq_looks_multistep "please add the thing and then remove the other thing" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "1. parse the input 2. validate it across the module" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "implement the parser and add tests for it" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "rename the file" || echo N' bash "$ROOT"
  [ "$output" = "N" ]
}
