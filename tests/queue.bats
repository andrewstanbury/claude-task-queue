#!/usr/bin/env bats

setup() {
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  # Pin cwd so the project key is stable across tests.
  cd "$CLAUDE_TQ_STATE_DIR"
}

teardown() {
  rm -rf "$CLAUDE_TQ_STATE_DIR"
}

@test "tq_state_dir respects CLAUDE_TQ_STATE_DIR" {
  [ "$(tq_state_dir)" = "$CLAUDE_TQ_STATE_DIR" ]
}

@test "tq_project_key is stable for the same cwd" {
  k1="$(tq_project_key "$PWD")"
  k2="$(tq_project_key "$PWD")"
  [ "$k1" = "$k2" ]
  [ "${#k1}" -eq 12 ]
}

@test "tq_project_key differs across paths" {
  k1="$(tq_project_key /tmp/a)"
  k2="$(tq_project_key /tmp/b)"
  [ "$k1" != "$k2" ]
}

@test "tq_next_id starts at 1 and increments" {
  [ "$(tq_next_id)" = "1" ]
  tq_append "first" >/dev/null
  [ "$(tq_next_id)" = "2" ]
  tq_append "second" >/dev/null
  [ "$(tq_next_id)" = "3" ]
}

@test "tq_append writes a parseable JSON line" {
  id="$(tq_append "build queue" S 1000)"
  [ "$id" = "1" ]
  line="$(tq_list)"
  [ -n "$line" ]
  status="$(printf '%s' "$line" | jq -r '.status')"
  [ "$status" = "pending" ]
}

@test "tq_get returns the requested task only" {
  tq_append "first" >/dev/null
  tq_append "second" >/dev/null
  got="$(tq_get 2)"
  subj="$(printf '%s' "$got" | jq -r '.subject')"
  [ "$subj" = "second" ]
}

@test "tq_update_status flips a task to in_progress" {
  tq_append "x" >/dev/null
  tq_update_status 1 in_progress
  status="$(tq_get 1 | jq -r '.status')"
  [ "$status" = "in_progress" ]
}

@test "tq_cancel marks task cancelled" {
  tq_append "x" >/dev/null
  tq_cancel 1
  [ "$(tq_get 1 | jq -r '.status')" = "cancelled" ]
}

@test "tq_next returns the first unblocked pending task" {
  tq_append "first" >/dev/null
  tq_append "second" M 0 "1" >/dev/null  # blocked by 1
  next="$(tq_next)"
  [ "$(printf '%s' "$next" | jq -r '.id')" = "1" ]
}

@test "tq_next skips blocked tasks until prereqs complete" {
  tq_append "first" >/dev/null
  tq_append "second" M 0 "1" >/dev/null
  tq_update_status 1 completed
  next="$(tq_next)"
  [ "$(printf '%s' "$next" | jq -r '.id')" = "2" ]
}

@test "tq_counts reflects completed/total" {
  tq_append "a" >/dev/null
  tq_append "b" >/dev/null
  tq_append "c" >/dev/null
  tq_update_status 1 completed
  [ "$(tq_counts)" = "1/3" ]
}

@test "tq_clear deletes queue + pause + autopilot files" {
  tq_append "x" >/dev/null
  : > "$(tq_pause_path)"
  : > "$(tq_autopilot_path)"
  tq_clear
  [ ! -f "$(tq_queue_path)" ]
  [ ! -f "$(tq_pause_path)" ]
  [ ! -f "$(tq_autopilot_path)" ]
}

@test "tq_is_paused detects the pause file" {
  ! tq_is_paused
  tq_ensure_state
  : > "$(tq_pause_path)"
  tq_is_paused
}

@test "tq_is_autopilot detects the autopilot file" {
  ! tq_is_autopilot
  tq_ensure_state
  : > "$(tq_autopilot_path)"
  tq_is_autopilot
}

# --- tq_fmt_task_line -------------------------------------------------------

@test "tq_fmt_task_line: bare task → id, subject, est" {
  out="$(tq_fmt_task_line '{"id":"5","subject":"Wire engine","est":"M","blockedBy":[],"attachedRules":[],"recommendedParallel":false}')"
  [ "$out" = "5: Wire engine (M)" ]
}

@test "tq_fmt_task_line: attached rules are surfaced" {
  out="$(tq_fmt_task_line '{"id":"4","subject":"Add auth","est":"M","blockedBy":[],"attachedRules":["OWASP","WCAG"],"recommendedParallel":false}')"
  [ "$out" = "4: Add auth (M) [rules: OWASP,WCAG]" ]
}

@test "tq_fmt_task_line: blockers and rules combine in order" {
  out="$(tq_fmt_task_line '{"id":"4","subject":"Add auth","est":"M","blockedBy":["3"],"attachedRules":["OWASP"],"recommendedParallel":false}')"
  [ "$out" = "4: Add auth (M) [blocked-by: 3] [rules: OWASP]" ]
}

@test "tq_fmt_task_line: parallel-ok flag is surfaced" {
  out="$(tq_fmt_task_line '{"id":"5","subject":"Wire engine","est":"L","blockedBy":[],"attachedRules":[],"recommendedParallel":true}')"
  [ "$out" = "5: Wire engine (L) [parallel-ok]" ]
}

@test "tq_fmt_task_line: missing est defaults to M" {
  out="$(tq_fmt_task_line '{"id":"7","subject":"Cleanup","blockedBy":[],"attachedRules":[]}')"
  [ "$out" = "7: Cleanup (M)" ]
}

@test "tq_fmt_task_line: empty input → empty output" {
  out="$(tq_fmt_task_line "")"
  [ -z "$out" ]
}

@test "tq_fmt_task_line: round-trips a real tq_append'd task" {
  id="$(tq_append "Secure the login form" M 1200 "" "OWASP" true)"
  task="$(tq_get "$id")"
  out="$(tq_fmt_task_line "$task")"
  [ "$out" = "${id}: Secure the login form (M) [rules: OWASP] [parallel-ok]" ]
}
