#!/usr/bin/env bats
#
# Tests for the observability log (tq_log) and the tq-doctor health check.
# Everything is faked via CLAUDE_TQ_* overrides — no real store, no model calls.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  DOCTOR="$ROOT/bin/tq-doctor.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_LOG_DIR="$(mktemp -d)"
  unset CLAUDE_TQ_LOG_DISABLED
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_LOG_DIR"
}

make_task() {
  local sid="$1" id="$2" status="$3"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" \
    '{id:$id, subject:("t"+$id), status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

# ---- observability log ------------------------------------------------------

@test "tq_log appends a tab-separated line when enabled" {
  run bash -c '. "$1/lib/tasks.sh"; tq_log "advance" "-> #2" "abcdef123456"' bash "$ROOT"
  [ "$status" -eq 0 ]
  [ -f "$CLAUDE_TQ_LOG_DIR/activity.log" ]
  line="$(cat "$CLAUDE_TQ_LOG_DIR/activity.log")"
  [[ "$line" == *$'\t'"advance"$'\t'"abcdef12"$'\t'"-> #2"* ]]   # sid truncated to 8
}

@test "tq_log writes nothing when CLAUDE_TQ_LOG_DISABLED is set" {
  CLAUDE_TQ_LOG_DISABLED=1 run bash -c '. "$1/lib/tasks.sh"; tq_log "advance" "x"' bash "$ROOT"
  [ "$status" -eq 0 ]
  [ ! -f "$CLAUDE_TQ_LOG_DIR/activity.log" ]
}

@test "tq_log never fails its caller even if the log dir is unwritable" {
  export CLAUDE_TQ_LOG_DIR=/proc/nonexistent/cannot-write
  run bash -c '. "$1/lib/tasks.sh"; tq_log "advance" "x"; echo "survived"' bash "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"survived"* ]]
}

# ---- tq-doctor --------------------------------------------------------------

@test "doctor passes on a healthy faked store" {
  make_task sess 1 pending
  run "$DOCTOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — core assumptions hold."* ]]
  [[ "$output" == *"task schema OK"* ]]
}

@test "doctor FAILs (exit 1) when a task file lacks expected fields" {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/sess"
  jq -n '{id:"1", subject:"x"}' > "$CLAUDE_TQ_TASKS_DIR/sess/1.json"   # no status
  run "$DOCTOR"
  [ "$status" -eq 1 ]
  [[ "$output" == *"task schema changed"* ]]
}

@test "doctor warns (not fails) when there are no tasks yet" {
  run "$DOCTOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no task files to sample yet"* ]]
}

@test "doctor reports the activity log tail" {
  make_task sess 1 pending
  printf 'a-recent-log-entry\n' > "$CLAUDE_TQ_LOG_DIR/activity.log"
  run "$DOCTOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a-recent-log-entry"* ]]
}

# ---- schema-drift canary ----------------------------------------------------

@test "tq_schema_status reports empty, ok, then drift" {
  run bash -c '. "$1/lib/tasks.sh"; tq_schema_status' bash "$ROOT"
  [ "$output" = "empty" ]                       # no task files yet

  make_task sess 1 pending
  run bash -c '. "$1/lib/tasks.sh"; tq_schema_status' bash "$ROOT"
  [ "$output" = "ok" ]                          # a well-formed file

  printf '{"subject":"no id or status"}\n' > "$CLAUDE_TQ_TASKS_DIR/sess/9.json"
  run bash -c '. "$1/lib/tasks.sh"; tq_schema_status' bash "$ROOT"
  [ "$output" = "drift" ]                       # a file missing the fields we read
}
