#!/usr/bin/env bats

setup() {
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$THIS_DIR/bin/tq"
  STATUS="$THIS_DIR/bin/tq-status.sh"
  cd "$CLAUDE_TQ_STATE_DIR"
}

teardown() {
  rm -rf "$CLAUDE_TQ_STATE_DIR"
}

@test "tq add + tq list roundtrip" {
  id="$($TQ add "build feature" S 1500)"
  [ "$id" = "1" ]
  line="$($TQ list)"
  [ -n "$line" ]
  [ "$(printf '%s' "$line" | jq -r '.subject')" = "build feature" ]
}

@test "tq pause writes a pause file; tq resume removes it" {
  $TQ pause >/dev/null
  $TQ list >/dev/null  # touch state
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  [ -f "$(tq_pause_path)" ]
  $TQ resume >/dev/null
  [ ! -f "$(tq_pause_path)" ]
}

@test "tq autopilot + one-at-a-time roundtrip" {
  $TQ autopilot >/dev/null
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  [ -f "$(tq_autopilot_path)" ]
  $TQ one-at-a-time >/dev/null
  [ ! -f "$(tq_autopilot_path)" ]
}

@test "tq start + done updates status" {
  $TQ add "x" >/dev/null
  $TQ start 1 >/dev/null
  [ "$($TQ get 1 | jq -r '.status')" = "in_progress" ]
  $TQ done 1 >/dev/null
  [ "$($TQ get 1 | jq -r '.status')" = "completed" ]
}

@test "tq cancel marks cancelled" {
  $TQ add "x" >/dev/null
  $TQ cancel 1 >/dev/null
  [ "$($TQ get 1 | jq -r '.status')" = "cancelled" ]
}

@test "tq status prints empty when no queue" {
  out="$($STATUS)"
  [ -z "$out" ]
}

@test "tq status shows next task with counts" {
  $TQ add "first task" S 1200 >/dev/null
  out="$($STATUS)"
  [[ "$out" == *"0/1"* ]]
  [[ "$out" == *"first task"* ]]
}

@test "tq status shows paused glyph when paused" {
  $TQ add "x" >/dev/null
  $TQ pause >/dev/null
  out="$($STATUS)"
  [[ "$out" == *"paused"* ]]
}

@test "tq status shows auto when autopilot on" {
  $TQ add "x" >/dev/null
  $TQ autopilot >/dev/null
  out="$($STATUS)"
  [[ "$out" == *"auto"* ]]
}

@test "tq path prints a file under the state dir" {
  p="$($TQ path)"
  [[ "$p" == "$CLAUDE_TQ_STATE_DIR"* ]]
  [[ "$p" == *.jsonl ]]
}
