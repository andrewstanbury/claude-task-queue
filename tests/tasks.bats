#!/usr/bin/env bats
#
# Tests for the read-only native-task viewer. We fake Claude Code's task store
# and project transcripts in temp dirs via the CLAUDE_TQ_* overrides, then
# assert what the status line and the grouped table render.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$ROOT/bin/tq"
  STATUS="$ROOT/bin/tq-status.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR"
}

# Register a fake session -> project (cwd) mapping.
make_session() {
  local sid="$1" cwd="$2" encoded
  encoded="$(printf '%s' "$cwd" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$encoded"
  printf '{"cwd":"%s","type":"session"}\n' "$cwd" \
    > "$CLAUDE_TQ_PROJECTS_DIR/$encoded/$sid.jsonl"
}

# Write a native task file.
make_task() {
  local sid="$1" id="$2" status="$3" subject="$4"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" --arg subj "$subject" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

@test "status line is empty when there are no tasks" {
  run "$STATUS"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "status line is empty when all tasks are done" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 completed "Init repo"
  make_task s1 2 completed "Ship it"
  run "$STATUS"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "status line counts open work and shows the doing task + project" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending     "Build login"
  make_task s1 2 in_progress "Wire engine"
  make_task s1 3 completed   "Init repo"
  run "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 todo"* ]]
  [[ "$output" == *"1 doing"* ]]
  [[ "$output" == *"Wire engine"* ]]
  [[ "$output" == *"[alpha]"* ]]
}

@test "status line aggregates across projects and counts distinct projects" {
  make_session "s1" "/home/x/alpha"
  make_session "s2" "/home/x/beta"
  make_task s1 1 pending "A1"
  make_task s2 1 pending "B1"
  make_task s2 2 pending "B2"
  run "$STATUS"
  [[ "$output" == *"2 proj"* ]]
  [[ "$output" == *"3 todo"* ]]
}

@test "list table groups by project with counts and lists only open tasks" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending     "Build login"
  make_task s1 2 in_progress "Wire engine"
  make_task s1 3 completed   "Init repo"
  run "$TQ" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"alpha"* ]]
  [[ "$output" == *"1 todo · 1 doing · 1 done"* ]]
  [[ "$output" == *"▶ Wire engine"* ]]
  [[ "$output" == *"▢ Build login"* ]]
  # completed task is counted but not listed
  [[ "$output" != *"Init repo"* ]]
}

@test "list reports nothing found on an empty store" {
  run "$TQ" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No tasks found"* ]]
}

@test "project label is cached after first resolve" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "A1"
  run "$STATUS"
  [ -f "$CLAUDE_TQ_STATE_DIR/project-cache.tsv" ]
  grep -q "s1" "$CLAUDE_TQ_STATE_DIR/project-cache.tsv"
  grep -q "alpha" "$CLAUDE_TQ_STATE_DIR/project-cache.tsv"
}

@test "label is the git repo root basename when the session ran inside a repo" {
  repo="$(mktemp -d)/my-cool-repo"
  mkdir -p "$repo/src/deep" && git -C "$repo" init -q
  make_session "s1" "$repo/src/deep"
  make_task s1 1 in_progress "Work in a subdir"
  run "$STATUS"
  [[ "$output" == *"[my-cool-repo]"* ]]
  rm -rf "$(dirname "$repo")"
}

@test "tq path prints the tasks dir being read" {
  run "$TQ" path
  [ "$output" = "$CLAUDE_TQ_TASKS_DIR" ]
}

@test "unknown command exits 64" {
  run "$TQ" bogus
  [ "$status" -eq 64 ]
}
