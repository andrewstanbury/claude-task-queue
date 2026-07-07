#!/usr/bin/env bats
#
# Characterization tests for bin/tq-status.sh — the per-repo CONTROL-plane readout
# behind /task-queue:status. It pins what it renders (feature states in full words +
# open-work counts + the toggle hint) so a refactor can't silently change the owner's
# control surface. Faked via CLAUDE_TQ_* + a temp repo.

setup() {
  unset CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/tq-status.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AGENT_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_AWAY_DIR" "$CLAUDE_TQ_AGENT_DIR" "$(dirname "$REPO")"
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

@test "all features off: renders the header + every feature as off (full words)" {
  run status
  [ "$status" -eq 0 ]
  [[ "$output" == *"task-queue · $REPO"* ]]
  [[ "$output" =~ autopilot[[:space:]]+off ]]
  [[ "$output" =~ agents[[:space:]]+off ]]
}

@test "hint points at the /task-queue: commands (not the retired /tq or per-mode slugs)" {
  run status
  [[ "$output" == *"/task-queue:"* ]]
  [[ "$output" != *"/tq "* ]]
  [[ "$output" != *"/task-queue:pause"* ]]
}

@test "autopilot ON is reflected (reads the away flag)" {
  date +%s > "$(flag "$CLAUDE_TQ_AWAY_DIR")"
  run status
  [[ "$output" =~ autopilot[[:space:]]+on ]]
}

@test "agents ON is reflected" {
  : > "$(flag "$CLAUDE_TQ_AGENT_DIR")"
  run status
  [[ "$output" =~ agents[[:space:]]+on ]]
}

@test "open-work line counts open tasks and the ❓ awaiting subset for this repo" {
  make_session sS
  make_task sS 1 pending     "build the settings page"
  make_task sS 2 in_progress "❓ [parked] pick a color"
  make_task sS 3 completed   "done thing"
  run status
  [[ "$output" == *"2 task(s) still open across sessions · 1 ❓ awaiting you"* ]]
}
