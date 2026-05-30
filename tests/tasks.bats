#!/usr/bin/env bats
#
# Tests for the native-task viewer (`tq`) and the SessionStart resume bridge.
# We fake Claude Code's task store and project transcripts in temp dirs via the
# CLAUDE_TQ_* overrides, then assert what `tq` renders and what the hook injects.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$ROOT/bin/tq"
  RESUME="$ROOT/bin/tq-resume.sh"

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

@test "tq status is empty when there are no tasks" {
  run "$TQ" status
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tq status is empty when all tasks are done" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 completed "Init repo"
  make_task s1 2 completed "Ship it"
  run "$TQ" status
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "tq status counts open work and shows the doing task + project" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending     "Build login"
  make_task s1 2 in_progress "Wire engine"
  make_task s1 3 completed   "Init repo"
  run "$TQ" status
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 todo"* ]]
  [[ "$output" == *"1 doing"* ]]
  [[ "$output" == *"Wire engine"* ]]
  [[ "$output" == *"[alpha]"* ]]
}

@test "tq status aggregates across projects and counts distinct projects" {
  make_session "s1" "/home/x/alpha"
  make_session "s2" "/home/x/beta"
  make_task s1 1 pending "A1"
  make_task s2 1 pending "B1"
  make_task s2 2 pending "B2"
  run "$TQ" status
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
  run "$TQ" status
  [ -f "$CLAUDE_TQ_STATE_DIR/project-cache.tsv" ]
  grep -q "s1" "$CLAUDE_TQ_STATE_DIR/project-cache.tsv"
  grep -q "alpha" "$CLAUDE_TQ_STATE_DIR/project-cache.tsv"
}

@test "label is the git repo root basename when the session ran inside a repo" {
  repo="$(mktemp -d)/my-cool-repo"
  mkdir -p "$repo/src/deep" && git -C "$repo" init -q
  make_session "s1" "$repo/src/deep"
  make_task s1 1 in_progress "Work in a subdir"
  run "$TQ" status
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

# ---- resume bridge (SessionStart hook) -------------------------------------

# Feed the hook a SessionStart payload (session id + cwd) on stdin.
run_resume() {
  local sid="$1" cwd="$2" json
  json="$(jq -nc --arg sid "$sid" --arg cwd "$cwd" \
            '{session_id:$sid, cwd:$cwd, source:"startup"}')"
  printf '%s' "$json" | "$RESUME"
}

@test "resume bridge surfaces a prior session's open tasks for the same repo" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending     "Build login"
  make_task s1 2 in_progress "Wire engine"
  make_task s1 3 completed   "Init repo"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"[doing] Wire engine"* ]]
  [[ "$ctx" == *"[todo]  Build login"* ]]
  # completed tasks are not carried over
  [[ "$ctx" != *"Init repo"* ]]
}

@test "resume bridge excludes the starting session's own (empty) folder" {
  make_session "s2" "/home/x/alpha"
  make_task s2 1 pending "Owned by current session"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resume bridge does not leak tasks from a different repo" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "Alpha work"
  run run_resume "s2" "/home/x/beta"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resume bridge is silent when prior tasks are all done" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 completed "Done thing"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "resume bridge caps the todo list and counts the remainder" {
  make_session "s1" "/home/x/alpha"
  for i in 1 2 3 4 5 6 7 8 9 10; do make_task s1 "$i" pending "todo $i"; done
  export CLAUDE_TQ_RESUME_MAX=3
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"10 open tasks carry over"* ]]
  [[ "$ctx" == *"…and 7 more"* ]]
  shown="$(printf '%s\n' "$ctx" | grep -c '• \[todo\]')"
  [ "$shown" -eq 3 ]
}

@test "resume bridge skips sessions untouched past the age cutoff" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "Ancient task"
  touch -d "60 days ago" "$CLAUDE_TQ_TASKS_DIR/s1/1.json"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
