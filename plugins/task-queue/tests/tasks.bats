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
  AGENT="$ROOT/bin/tq-agent.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AGENT_DIR="$(mktemp -d)"
  unset CLAUDE_TQ_AGENT_MODE   # hermetic: ignore any ambient global default
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_TQ_AGENT_DIR"
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

@test "session start hydrates the live queue from a committed roadmap/backlog file" {
  local repo; repo="$(mktemp -d)"
  mkdir -p "$repo/docs"; printf '# Roadmap\n## Next\n- ship it\n' > "$repo/docs/ROADMAP.md"
  run run_resume "s9" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"committed backlog at docs/ROADMAP.md"* ]]
  [[ "$output" == *"adopt its open"* ]]
  rm -rf "$repo"
}

@test "no roadmap file -> no hydration nudge" {
  run run_resume "s9" "/home/x/no-roadmap"
  [ "$status" -eq 0 ]
  [[ "$output" != *"committed backlog"* ]]
}

@test "hydration nudge is omitted in lean mode (compact)" {
  local repo; repo="$(mktemp -d)"
  printf '# Backlog\n' > "$repo/ROADMAP.md"
  json="$(jq -nc --arg cwd "$repo" '{session_id:"s9", cwd:$cwd, source:"compact"}')"
  run bash -c 'printf "%s" "$1" | "$0" | jq -r .hookSpecificOutput.additionalContext' "$RESUME" "$json"
  [[ "$output" != *"committed backlog"* ]]
  rm -rf "$repo"
}

@test "quiet mode: policy marker in CLAUDE.md -> one-line re-anchor, carryover preserved" {
  local repo; repo="$(mktemp -d)"
  printf '# CLAUDE.md\nstanding policy here <!-- claude-companion -->\n' > "$repo/CLAUDE.md"
  make_session "old9" "$repo"; make_task "old9" "1" "pending" "leftover task"
  run run_resume "new9" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"policy in CLAUDE.md"* ]]
  [[ "$output" != *"without draining"* ]]        # full POLICY prose suppressed
  [[ "$output" == *"carry over"* ]]              # state (carryover) NOT suppressed
  rm -rf "$repo"
}

@test "not documented -> full policy plus a bootstrap tip to bake it into CLAUDE.md" {
  run run_resume "s2" "/home/x/alpha"
  [[ "$output" == *"without draining"* ]]        # full policy present
  [[ "$output" == *"claude-companion"* ]]        # tip names the marker
}

@test "tq-agent toggles opt-in agent-mode on/off/status (per repo)" {
  local repo; repo="$(mktemp -d)"
  run bash -c 'cd "$1" && bash "$2" status' _ "$repo" "$AGENT"
  [[ "$output" == on\ * || "$output" == off\ * ]]; [[ "$output" == off* ]]
  run bash -c 'cd "$1" && bash "$2" on' _ "$repo" "$AGENT"
  [[ "$output" == *"agent-mode ON"* ]]
  run bash -c 'cd "$1" && bash "$2" status' _ "$repo" "$AGENT"
  [[ "$output" == on* ]]
  run bash -c 'cd "$1" && bash "$2" off' _ "$repo" "$AGENT"
  [[ "$output" == *"agent-mode OFF"* ]]
  rm -rf "$repo"
}

@test "session start shows the agent-mode policy only when enabled" {
  local repo; repo="$(mktemp -d)"
  run run_resume "sA" "$repo"                        # default: off
  [[ "$output" != *"Agent-mode is ON"* ]]
  ( cd "$repo" && bash "$AGENT" on >/dev/null )
  run run_resume "sA" "$repo"
  [[ "$output" == *"Agent-mode is ON"* ]]
  [[ "$output" == *"subagents"* ]]
  rm -rf "$repo"
}

@test "agent-mode: the global default (CLAUDE_TQ_AGENT_MODE) enables it without a per-repo flag" {
  local repo; repo="$(mktemp -d)"
  run run_resume "sG" "$repo"                          # no flag, no env → off
  [[ "$output" != *"Agent-mode is ON"* ]]
  CLAUDE_TQ_AGENT_MODE=on run run_resume "sG" "$repo"  # global default on
  [[ "$output" == *"Agent-mode is ON"* ]]
  CLAUDE_TQ_AGENT_MODE=0 run run_resume "sG" "$repo"   # explicit off value
  [[ "$output" != *"Agent-mode is ON"* ]]
  rm -rf "$repo"
}

@test "session start advertises the agent-mode command (discoverable)" {
  run run_resume "s2" "/home/x/alpha"
  [[ "$output" == *"tq-agent.sh"* ]]
}

@test "hook output is valid SessionStart hook JSON" {
  json="$(jq -nc '{session_id:"s2", cwd:"/home/x/alpha", source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$0" | jq -r .hookSpecificOutput.hookEventName' "$RESUME" "$json"
  [ "$status" -eq 0 ]
  [ "$output" = "SessionStart" ]
}

@test "session start warns when the task store schema has drifted" {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/old"
  printf '{"subject":"no id/status — shape changed"}\n' > "$CLAUDE_TQ_TASKS_DIR/old/1.json"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no longer matches the expected schema"* ]]
}

@test "session start does not warn when the schema is intact" {
  make_task s1 1 pending "Fine"
  run run_resume "s2" "/home/x/alpha"
  [ "$status" -eq 0 ]
  [[ "$output" != *"no longer matches the expected schema"* ]]
}

# run_resume sets source:"startup" → full block. Helper for other sources:
resume_with_source() {
  local src="$1" json
  json="$(jq -nc --arg c "/home/x/alpha" --arg s "$src" \
            '{session_id:"s2", cwd:$c, source:$s}')"
  printf '%s' "$json" | "$RESUME" | jq -r '.hookSpecificOutput.additionalContext'
}

@test "source-aware: full policy on startup, lean re-anchor on compact" {
  run resume_with_source "startup"
  [[ "$output" == *"without draining the backlog"* ]]   # full policy
  [[ "$output" != *"(reminder)"* ]]

  run resume_with_source "compact"
  [[ "$output" == *"(reminder)"* ]]                      # lean re-anchor
  [[ "$output" != *"without draining the backlog"* ]]
  [[ "$output" == *"tq-pause.sh"* ]]                     # pause command still rides along
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

@test "a real-captured task file parses through resume and advance" {
  # tests/fixtures/real-task.json is the exact key set Claude Code writes, so
  # this guards our parsing against the true on-disk shape (not a hand-made fake).
  make_session "s1" "/home/x/alpha"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/s1"
  cp "$ROOT/tests/fixtures/real-task.json" "$CLAUDE_TQ_TASKS_DIR/s1/7.json"
  run run_resume "s2" "/home/x/alpha"
  [[ "$output" == *"Wire the auth middleware"* ]]      # resume parses the real shape
  run run_next "s1" "1"
  [[ "$output" == *"#7 — Wire the auth middleware"* ]]  # advance parses blockedBy
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

@test "advance stays silent when every pending task is blocked by an open task" {
  # Mutual block: both pending, each blocked by the other (still-open) task.
  make_task_blocked s1 2 pending "Blocked by 3" "3"
  make_task_blocked s1 3 pending "Blocked by 2" "2"
  run run_next "s1" "1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "advance surfaces a task whose blocker was completed earlier (file removed)" {
  # Claude Code removes a completed task's file, so a done blocker is simply
  # absent. #5 was blocked only by the now-gone #1; completing unrelated #2
  # must surface #5 — an absent blocker can't block.
  make_task_blocked s1 5 pending "Was blocked by removed 1" "1"
  run run_next "s1" "2"
  [ "$status" -eq 0 ]
  [[ "$output" == *"#5 — Was blocked by removed 1"* ]]
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
