#!/usr/bin/env bats
# Observability log roundtrip.

setup() {
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  . "$THIS_DIR/lib/log.sh"
  cd "$CLAUDE_TQ_STATE_DIR"
}

teardown() {
  rm -rf "$CLAUDE_TQ_STATE_DIR"
}

@test "tq_log_path is project-scoped" {
  p="$(tq_log_path)"
  [[ "$p" == "$CLAUDE_TQ_STATE_DIR/"*".log" ]]
}

@test "tq_log appends a parseable jsonl line" {
  tq_log decompose --arg outcome "trivial-skip"
  line="$(cat "$(tq_log_path)")"
  ts="$(printf '%s' "$line" | jq -r '.ts')"
  event="$(printf '%s' "$line" | jq -r '.event')"
  [ "$event" = "decompose" ]
  [ -n "$ts" ]
}

@test "tq_log preserves jq --argjson types" {
  tq_log pretool --arg tool "Bash" --argjson latency_ms 42
  line="$(cat "$(tq_log_path)")"
  latency_type="$(printf '%s' "$line" | jq -r '.latency_ms | type')"
  [ "$latency_type" = "number" ]
}

@test "tq_log_tail returns the last N events" {
  for i in 1 2 3 4 5; do
    tq_log "event-$i"
  done
  tail="$(tq_log_tail 3 | wc -l | tr -d '[:space:]')"
  [ "$tail" = "3" ]
}

@test "tq_log_tail returns nothing when log doesn't exist" {
  out="$(tq_log_tail 10)"
  [ -z "$out" ]
}
