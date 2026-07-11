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

@test "tq breadcrumb: doing sets an optional note, tq note updates it, done keeps it" {
  "$TQ" add "build it" >/dev/null
  "$TQ" doing 1 "scaffolding written; next: wire the handler"
  [ "$(jq -r .description "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "scaffolding written; next: wire the handler" ]
  "$TQ" note 1 "handler wired; next: tests"
  [ "$(jq -r .description "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "handler wired; next: tests" ]
  "$TQ" done 1
  # completing must NOT wipe the breadcrumb (it's the crash-resume detail)
  [ "$(jq -r .description "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "handler wired; next: tests" ]
  [ "$(jq -r .status "$CLAUDE_TQ_TASKS_DIR/sess1/1.json")" = "completed" ]
}

@test "tq note: needs an id and text, errors otherwise" {
  "$TQ" add "x" >/dev/null
  run "$TQ" note 1
  [ "$status" -ne 0 ]
  run "$TQ" note 9 "text"
  [ "$status" -ne 0 ]
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

# --- report: the CLI task report (replaces hud's old 📋 status-line slot) -------

@test "tq report: groups tasks by state with a count header" {
  "$TQ" add "real work" "❓ a decision" "⏳ owner action" >/dev/null
  "$TQ" add "shipped" >/dev/null
  "$TQ" doing 1 >/dev/null
  "$TQ" done 4 >/dev/null
  run "$TQ" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"📋 Task queue"* ]]
  [[ "$output" == *"1 in progress"* ]]      # #1 doing
  [[ "$output" == *"1 parked"* ]]           # #2 ❓
  [[ "$output" == *"1 blocked"* ]]          # #3 ⏳
  [[ "$output" == *"1 done"* ]]             # #4 completed
  [[ "$output" == *"▸ #1"* ]]               # in_progress glyph
  [[ "$output" == *"✔ #4"* ]]               # completed glyph
}

@test "tq report: empty queue says so, exits clean" {
  run "$TQ" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"empty"* ]]
}

@test "tq done: prints the report (completion is the trigger)" {
  "$TQ" add "one" "two" >/dev/null
  run "$TQ" done 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"#1 → completed"* ]]     # the confirmation line
  [[ "$output" == *"📋 Task queue"* ]]       # ...followed by the full report
  [[ "$output" == *"✔ #1"* ]]
  [[ "$output" == *"◻ #2"* ]]               # the still-open one
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
