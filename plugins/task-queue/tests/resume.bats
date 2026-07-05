#!/usr/bin/env bats
#
# Tests for bin/tq-restore.sh — the on-demand "put me back where I was" that backs
# /task-queue:resume. It ties two existing pieces together (checkpoint working-tree
# restore + earlier-session task carryover) and is honest that it cannot reload the
# conversation. Faked via CLAUDE_TQ_* overrides + a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_CHECKPOINT_MODE CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESTORE="$ROOT/bin/tq-restore.sh"
  CKPT="$ROOT/bin/tq-checkpoint.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_CKPT_DIR="$(mktemp -d)"

  REPO="$(mktemp -d)/proj"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  printf 'v1\n' > "$REPO/tracked.txt"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm init
  REPO="$(git -C "$REPO" rev-parse --show-toplevel)"   # canonical root the libs resolve to
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_CKPT_DIR" "$(dirname "$REPO")"
}

# Register a fake session -> project (cwd) mapping so its tasks map to this repo.
make_session() {
  local sid="$1" cwd="$2" encoded
  encoded="$(printf '%s' "$cwd" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$encoded"
  printf '{"cwd":"%s","type":"session"}\n' "$cwd" \
    > "$CLAUDE_TQ_PROJECTS_DIR/$encoded/$sid.jsonl"
}

make_task() {
  local sid="$1" id="$2" status="$3" subject="$4"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" --arg subj "$subject" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

run_restore() { bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$RESTORE"; }

@test "no checkpoint + no carryover: friendly no-ops, and the honest conversation note" {
  run run_restore
  [ "$status" -eq 0 ]
  [[ "$output" == *"no checkpoint to restore"* ]]
  [[ "$output" == *"No open tasks carry over"* ]]
  [[ "$output" == *"claude --resume"* ]]           # never implies it reloaded context
}

@test "restores a crashed edit AND surfaces an earlier session's open task" {
  # Arm + snapshot, then simulate a crash losing the edit.
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$CKPT"
  printf 'work-in-progress\n' > "$REPO/tracked.txt"
  printf '{"cwd":"%s"}' "$REPO" | "$CKPT" now
  git -C "$REPO" checkout -q -- tracked.txt          # "crash" — edit lost

  # An open task from an earlier session for THIS repo.
  make_session "sOld" "$REPO"
  make_task "sOld" 1 in_progress "Wire up the resume command"

  run run_restore
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored working tree"* ]]
  [[ "$output" == *"Wire up the resume command"* ]]
  [[ "$output" == *"carry over from an earlier session"* ]]
  [ "$(cat "$REPO/tracked.txt")" = "work-in-progress" ]   # the lost edit is back
}
