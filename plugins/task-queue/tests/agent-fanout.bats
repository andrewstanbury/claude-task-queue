#!/usr/bin/env bats
#
# Tests for the agent-mode FAN-OUT injection in bin/tq-capture.sh: when agent-mode is on
# and 2+ queued tasks are unblocked + independent (startable now, not ❓), the capture
# hook names them and tells the model to fan them to parallel subagents. The hook does
# the independence analysis (tq_ready_tasks); the model makes the Task calls. Faked via
# CLAUDE_TQ_* overrides.

setup() {
  unset CLAUDE_TQ_AGENT_MODE
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CAPTURE="$ROOT/bin/tq-capture.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  SID="sess"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$SID"
}
teardown() { rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$(dirname "$REPO")"; }

task() {  # id subject status [blockedBy-csv]
  local bb="[]"; [ -n "${4:-}" ] && bb="$(printf '%s' "$4" | jq -R 'split(",")')"
  jq -n --arg id "$1" --arg s "$2" --arg st "$3" --argjson bb "$bb" \
    '{id:$id, subject:$s, status:$st, blocks:[], blockedBy:$bb}' \
    > "$CLAUDE_TQ_TASKS_DIR/$SID/$1.json"
}
run_capture() {
  local json; json="$(jq -nc --arg p "$1" --arg s "$SID" --arg c "$REPO" '{prompt:$p, session_id:$s, cwd:$c}')"
  printf '%s' "$json" | "$CAPTURE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "fan-out: names 2+ independent unblocked tasks for parallel subagents" {
  task 1 "build the header" pending
  task 2 "build the footer" pending
  export CLAUDE_TQ_AGENT_MODE=on
  run run_capture "thanks"
  [[ "$output" == *"FAN THEM OUT"* ]]
  [[ "$output" == *"build the header"* ]]
  [[ "$output" == *"build the footer"* ]]
}

@test "fan-out: silent when a task is still blocked (fewer than 2 ready)" {
  task 1 "build the header" pending
  task 2 "wire it up" pending "1"          # blocked by the still-open task 1
  export CLAUDE_TQ_AGENT_MODE=on
  run run_capture "thanks"
  [[ "$output" != *"FAN THEM OUT"* ]]
}

@test "fan-out: a blocker that is COMPLETED no longer blocks (task becomes ready)" {
  task 1 "build the header" completed
  task 2 "wire it up" pending "1"
  task 3 "build the footer" pending
  export CLAUDE_TQ_AGENT_MODE=on
  run run_capture "thanks"
  [[ "$output" == *"FAN THEM OUT"* ]]       # 2 (now unblocked) + 3 are ready
  [[ "$output" == *"wire it up"* ]]
}

@test "fan-out: excludes ❓ parked items" {
  task 1 "build the header" pending
  task 2 "❓ [parked] pick a color" pending
  export CLAUDE_TQ_AGENT_MODE=on
  run run_capture "thanks"
  [[ "$output" != *"FAN THEM OUT"* ]]       # only 1 real ready task; ❓ doesn't count
}

@test "fan-out: silent when agent-mode is off (opt-in)" {
  task 1 "build the header" pending
  task 2 "build the footer" pending
  run run_capture "thanks"
  [[ "$output" != *"FAN THEM OUT"* ]]
}
