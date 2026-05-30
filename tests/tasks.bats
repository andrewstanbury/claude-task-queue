#!/usr/bin/env bats
#
# Tests for the single SessionStart hook (bin/tq-resume.sh), which injects a
# one-time queue policy plus this repo's carried-over open tasks. We fake Claude
# Code's task store and project transcripts in temp dirs via the CLAUDE_TQ_*
# overrides, then assert what the hook injects.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESUME="$ROOT/bin/tq-resume.sh"
  NEXT="$ROOT/bin/tq-next.sh"

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

# Write a native task file with a blockedBy list (space-separated ids).
make_task_blocked() {
  local sid="$1" id="$2" status="$3" subject="$4" blockers="$5"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  local by; by="$(printf '%s\n' $blockers | jq -R . | jq -sc .)"
  jq -n --arg id "$id" --arg s "$status" --arg subj "$subject" --argjson by "$by" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:$by}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

# Feed the TaskCompleted hook a payload (session id + completed task id) and
# return the injected additionalContext, or empty string when it stays silent.
run_next() {
  local sid="$1" done_id="$2" json out
  json="$(jq -nc --arg sid "$sid" --arg id "$done_id" \
            '{session_id:$sid, task_id:$id, hook_event_name:"TaskCompleted"}')"
  out="$(printf '%s' "$json" | "$NEXT" || true)"
  [ -n "$out" ] && printf '%s' "$out" | jq -r '.hookSpecificOutput.additionalContext' || true
}

# Feed the hook a SessionStart payload (session id + cwd) and return the
# injected additionalContext on stdout.
run_resume() {
  local sid="$1" cwd="$2" json
  json="$(jq -nc --arg sid "$sid" --arg cwd "$cwd" \
            '{session_id:$sid, cwd:$cwd, source:"startup"}')"
  printf '%s' "$json" | "$RESUME" | jq -r '.hookSpecificOutput.additionalContext'
}

# ---- policy (always injected) ----------------------------------------------

@test "session start always injects the queue policy, even with no tasks" {
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TaskCreate"* ]]
  [[ "$output" == *"dependency order"* ]]
  # no carry-over section when there are no prior tasks
  [[ "$output" != *"carry over"* ]]
}

@test "hook output is valid SessionStart hook JSON" {
  json="$(jq -nc '{session_id:"s2", cwd:"/home/x/alpha", source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$0" | jq -r .hookSpecificOutput.hookEventName' "$RESUME" "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "SessionStart" ]
}

# ---- resume (carried-over tasks) -------------------------------------------

@test "resume surfaces a prior session's open tasks for the same repo" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending     "Build login"
  make_task s1 2 in_progress "Wire engine"
  make_task s1 3 completed   "Init repo"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[doing] Wire engine"* ]]
  [[ "$output" == *"[todo]  Build login"* ]]
  # completed tasks are not carried over
  [[ "$output" != *"Init repo"* ]]
}

@test "resume excludes the starting session's own folder (policy only)" {
  make_session "s2" "/home/x/alpha"
  make_task s2 1 pending "Owned by current session"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"TaskCreate"* ]]
  [[ "$output" != *"carry over"* ]]
}

@test "resume does not leak tasks from a different repo" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "Alpha work"
  run run_resume "s2" "/home/x/beta"
  [ "$status" -eq 0 ]
  [[ "$output" != *"carry over"* ]]
  [[ "$output" != *"Alpha work"* ]]
}

@test "resume matches by git repo root across different subdirs" {
  repo="$(mktemp -d)/proj"
  mkdir -p "$repo/a/b" "$repo/c" && git -C "$repo" init -q
  make_session "s1" "$repo/a/b"
  make_task s1 1 in_progress "Deep work"
  run run_resume "s2" "$repo/c"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[doing] Deep work"* ]]
  rm -rf "$(dirname "$repo")"
}

@test "resume shows no carry-over when prior tasks are all done" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 completed "Done thing"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" != *"carry over"* ]]
}

@test "resume caps the todo list and counts the remainder" {
  make_session "s1" "/home/x/alpha"
  for i in 1 2 3 4 5 6 7 8 9 10; do make_task s1 "$i" pending "todo $i"; done
  export CLAUDE_TQ_RESUME_MAX=3
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"10 open tasks carry over"* ]]
  [[ "$output" == *"…and 7 more"* ]]
  shown="$(printf '%s\n' "$output" | grep -c '• \[todo\]')"
  [ "$shown" -eq 3 ]
}

@test "resume skips sessions untouched past the age cutoff" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "Ancient task"
  touch -d "60 days ago" "$CLAUDE_TQ_TASKS_DIR/s1/1.json"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" != *"carry over"* ]]
}

@test "resume caches the session root after first resolve" {
  make_session "s1" "/home/x/alpha"
  make_task s1 1 pending "A1"
  run run_resume "s2" "/home/x/alpha"
  [ -f "$CLAUDE_TQ_STATE_DIR/root-cache.tsv" ]
  grep -q "s1" "$CLAUDE_TQ_STATE_DIR/root-cache.tsv"
  grep -q "alpha" "$CLAUDE_TQ_STATE_DIR/root-cache.tsv"
}

# ---- auto-advance (TaskCompleted -> next unblocked task) -------------------

@test "advance names the next unblocked pending task after a completion" {
  make_task s1 1 completed   "First"
  make_task s1 2 pending     "Second"
  make_task s1 3 pending     "Third"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Next unblocked task: #2 — Second"* ]]
  [[ "$output" == *"(2 open)"* ]]
}

@test "advance picks the lowest-numbered unblocked task, not file order" {
  make_task s1 10 pending "Ten"
  make_task s1 2  pending "Two"
  run run_next "s1" "99"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#2 — Two"* ]]
}

@test "advance treats the just-completed task as closed for blockedBy" {
  # #2 is blocked only by #1; completing #1 should unblock it even if the
  # store still shows #1 as pending (hook fired before the native write).
  make_task         s1 1 pending "Blocker"
  make_task_blocked s1 2 pending "Dependent" "1"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#2 — Dependent"* ]]
}

@test "advance stays silent while another task is in_progress" {
  make_task s1 1 completed   "Done"
  make_task s1 2 in_progress "Busy"
  make_task s1 3 pending     "Waiting"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advance stays silent when no pending task is unblocked" {
  make_task         s1 1 completed "Done"
  make_task_blocked s1 2 pending   "Still blocked" "9"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advance stays silent when the queue is drained" {
  make_task s1 1 completed "Only task"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advance stays silent when the session has no task folder" {
  run run_next "ghost" "1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
