#!/usr/bin/env bats
#
# Tests for bin/tq — the fallback queue writer used when Claude Code's native task
# tools are gated off for a model. The load-bearing claim is that tq writes the SAME
# native format to the SAME store, so every EXISTING reader works unchanged; the
# integration tests below prove that by reading tq's output back through tasks.sh.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$ROOT/bin/tq"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_SESSION_ID="sess1"
}
teardown() { rm -rf "$CLAUDE_TQ_TASKS_DIR"; }

@test "tq add: queues sequential pending tasks in native format" {
  run "$TQ" add "refactor parser" "add a test"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_TQ_TASKS_DIR/sess1/1.json" ]
  [ -f "$CLAUDE_TQ_TASKS_DIR/sess1/2.json" ]
  run jq -r '.subject + "|" + .status' "$CLAUDE_TQ_TASKS_DIR/sess1/1.json"
  [ "$output" = "refactor parser|pending" ]
  # native-format fields every reader relies on are present
  run jq -e '.id and .subject and .status and (.blocks|type=="array") and (.blockedBy|type=="array")' \
    "$CLAUDE_TQ_TASKS_DIR/sess1/2.json"
  [ "$status" -eq 0 ]
}

@test "tq add: a second call continues numbering (does not clobber)" {
  "$TQ" add "one" >/dev/null
  "$TQ" add "two" >/dev/null
  [ -f "$CLAUDE_TQ_TASKS_DIR/sess1/1.json" ]
  run jq -r '.subject' "$CLAUDE_TQ_TASKS_DIR/sess1/2.json"
  [ "$output" = "two" ]
}

@test "tq doing / done: flip status in place" {
  "$TQ" add "build it" >/dev/null
  "$TQ" doing 1
  [ "$(jq -r .status "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "in_progress" ]
  "$TQ" done 1
  [ "$(jq -r .status "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "completed" ]
}

@test "tq done: unknown id errors, writes nothing" {
  run "$TQ" done 9
  [ "$status" -ne 0 ]
  [ ! -e "$CLAUDE_TQ_TASKS_DIR/sess1/9.json" ]
}

@test "tq: no session id → clean error, no store touched" {
  run env -u CLAUDE_TQ_SESSION_ID -u CLAUDE_CODE_SESSION_ID "$TQ" add "x"
  [ "$status" -ne 0 ]
  [[ "$output" == *"session id"* ]]
}

@test "tq: unknown command errors with usage" {
  run "$TQ" frobnicate
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown command"* ]]
}

@test "tq list: shows the queue, '(queue empty)' when none" {
  run "$TQ" list
  [[ "$output" == *"queue empty"* ]]
  "$TQ" add "alpha" "beta" >/dev/null
  "$TQ" done 1 >/dev/null
  run "$TQ" list
  [[ "$output" == *"#1"* ]]
  [[ "$output" == *"completed"* ]]
  [[ "$output" == *"beta"* ]]
}

# --- integration: EXISTING readers accept tq's output with no changes ----------

@test "integration: tq_open_worklist reads tq's tasks (❓/⏳/completed excluded)" {
  "$TQ" add "real work" "❓ a decision" "⏳ owner action" >/dev/null
  "$TQ" add "shipped" >/dev/null
  "$TQ" done 4 >/dev/null
  run bash -c '. "$1/lib/tasks.sh"; tq_open_worklist sess1' _ "$ROOT"
  [ "$output" = "real work" ]
}

@test "integration: tq's ❓ task is counted by tq_open_questions" {
  "$TQ" add "❓ block or warn?" "just work" >/dev/null
  run bash -c '. "$1/lib/tasks.sh"; tq_open_questions sess1 | grep -c .' _ "$ROOT"
  [ "$output" = "1" ]
}
