#!/usr/bin/env bats
#
# Characterization tests for bin/tq-status.sh — the per-repo CONTROL-plane readout
# behind the bare `/tq` menu. It had no direct coverage; this pins what it renders
# (mode states + open-work counts + the change-it footer) so a refactor can't
# silently change the owner's control surface. Faked via CLAUDE_TQ_* + a temp repo.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/tq-status.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AGENT_DIR="$(mktemp -d)"
  export CLAUDE_TQ_CKPT_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_AWAY_DIR" "$CLAUDE_TQ_AGENT_DIR" "$CLAUDE_TQ_CKPT_DIR" "$(dirname "$REPO")"
}

# tq-status reads the repo from PWD.
status() { bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$STATUS"; }
flag()   { printf '%s/%s' "$1" "$(printf '%s' "$REPO" | sed 's:/:-:g')"; }
# Map a fake session to $REPO so the open-work scan resolves its tasks to this repo.
make_session() {
  local sid="$1" enc; enc="$(printf '%s' "$REPO" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$enc"
  printf '{"cwd":"%s","type":"session"}\n' "$REPO" > "$CLAUDE_TQ_PROJECTS_DIR/$enc/$sid.jsonl"
}
make_task() {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" --arg subj "$4" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$1/$2.json"
}

@test "all modes off: renders the header + every mode as off" {
  run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"task-queue · $REPO"* ]]
  [[ "$output" == *"solo          off"* ]]
  [[ "$output" == *"checkpoint    off"* ]]
  [[ "$output" == *"agent-mode    off"* ]]
}

@test "footer points at the /tq control command (not the retired per-mode slugs)" {
  run status
  [[ "$output" == *"/tq solo"* ]]
  [[ "$output" != *"/task-queue:pause"* ]]
}

@test "solo ON is reflected (reads the away flag)" {
  date +%s > "$(flag "$CLAUDE_TQ_AWAY_DIR")"
  run status
  [[ "$output" == *"solo          ON"* ]]
}

@test "agent-mode ON is reflected" {
  : > "$(flag "$CLAUDE_TQ_AGENT_DIR")"
  run status
  [[ "$output" == *"agent-mode    ON"* ]]
}

@test "checkpoint ARMED is reflected" {
  : > "$(flag "$CLAUDE_TQ_CKPT_DIR")"
  run status
  [[ "$output" == *"checkpoint    ARMED"* ]]
}

@test "open-work line counts open tasks and the ❓ awaiting subset for this repo" {
  make_session sS
  make_task sS 1 pending     "build the settings page"
  make_task sS 2 in_progress "❓ [parked] pick a color"
  make_task sS 3 completed   "done thing"
  run status
  [[ "$output" == *"2 task(s) still open across sessions · 1 ❓ awaiting you"* ]]
}
