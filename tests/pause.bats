#!/usr/bin/env bats
#
# Tests for the per-repo pause: bin/tq-pause.sh, the TaskCompleted hook honoring
# it, and the SessionStart banner. Everything is faked via CLAUDE_TQ_* overrides
# and temp git repos — no real store, no model calls.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PAUSE="$ROOT/bin/tq-pause.sh"
  NEXT="$ROOT/bin/tq-next.sh"
  RESUME="$ROOT/bin/tq-resume.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PAUSE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_LOG_DIR="$(mktemp -d)"

  REPO="$(mktemp -d)/proj"
  mkdir -p "$REPO" && git -C "$REPO" init -q
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" \
         "$CLAUDE_TQ_PAUSE_DIR" "$CLAUDE_TQ_LOG_DIR" "$(dirname "$REPO")"
}

make_task() {
  local sid="$1" id="$2" status="$3"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" \
    '{id:$id, subject:("t"+$id), status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

# Run tq-next.sh as the TaskCompleted hook for $REPO; echo injected text or "".
run_next() {
  local sid="$1" done_id="$2" json
  json="$(jq -nc --arg s "$sid" --arg d "$done_id" --arg c "$REPO" \
            '{session_id:$s, task_id:$d, cwd:$c}')"
  printf '%s' "$json" | "$NEXT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

# ---- tq-pause.sh -----------------------------------------------------------

@test "tq-pause.sh reports active by default, paused after on, active after off" {
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$PAUSE"
  [[ "$output" == active* ]]

  run bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$PAUSE"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$PAUSE"
  [[ "$output" == paused* ]]

  run bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$PAUSE"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$PAUSE"
  [[ "$output" == active* ]]
}

@test "tq-pause.sh rejects an unknown action" {
  run bash -c 'cd "$1" && bash "$2" wat' _ "$REPO" "$PAUSE"
  [ "$status" -eq 2 ]
}

@test "pause flag is scoped to the repo root (subdir resolves to the same flag)" {
  mkdir -p "$REPO/a/b"
  run bash -c 'cd "$1/a/b" && bash "$2" on' _ "$REPO" "$PAUSE"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$PAUSE"
  [[ "$output" == paused* ]]
}

# ---- TaskCompleted honoring the pause --------------------------------------

@test "advance fires when not paused (control)" {
  make_task sess 1 completed
  make_task sess 2 pending
  run run_next sess 1
  [[ "$output" == *"Next unblocked task: #2"* ]]
}

@test "advance stays silent when the repo is paused" {
  make_task sess 1 completed
  make_task sess 2 pending
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$PAUSE"
  run run_next sess 1
  [ -z "$output" ]
}

@test "resuming re-enables advance" {
  make_task sess 1 completed
  make_task sess 2 pending
  bash -c 'cd "$1" && bash "$2" on'  _ "$REPO" "$PAUSE"
  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$PAUSE"
  run run_next sess 1
  [[ "$output" == *"Next unblocked task: #2"* ]]
}

# ---- SessionStart surfacing -------------------------------------------------

@test "SessionStart always includes the pause/resume command hint" {
  json="$(jq -nc --arg c "$REPO" '{session_id:"s2", cwd:$c, source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$json" "$RESUME"
  [[ "$output" == *"tq-pause.sh"* ]]
}

@test "SessionStart surfaces a PAUSED banner when the repo is paused" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$PAUSE"
  json="$(jq -nc --arg c "$REPO" '{session_id:"s2", cwd:$c, source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$json" "$RESUME"
  [[ "$output" == *"PAUSED for this repo"* ]]
}
