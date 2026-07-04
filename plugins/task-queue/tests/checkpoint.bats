#!/usr/bin/env bats
#
# Tests for the crash checkpoint: bin/tq-checkpoint.sh (toggle + snapshot) and the
# SessionStart armed-state line. The load-bearing guarantee is that a snapshot
# captures the working tree WITHOUT touching HEAD/index/worktree/branch history.
# Faked via CLAUDE_TQ_* overrides and a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_CHECKPOINT_MODE CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CKPT="$ROOT/bin/tq-checkpoint.sh"
  RESUME="$ROOT/bin/tq-resume.sh"

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
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_CKPT_DIR" "$(dirname "$REPO")"
}

arm()      { bash -c 'cd "$1" && bash "$2" on'  _ "$REPO" "$CKPT"; }
snapshot() { printf '{"cwd":"%s"}' "$REPO" | "$CKPT" now; }
ckpt_ref() { git -C "$REPO" rev-parse -q --verify refs/tq/checkpoint; }

# ---- toggle -----------------------------------------------------------------

@test "checkpoint reports off by default, on after on, off after off" {
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$CKPT"
  [[ "$output" == off* ]]
  arm
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$CKPT"
  [[ "$output" == on* ]]
  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$CKPT"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$CKPT"
  [[ "$output" == off* ]]
}

# ---- global default + tombstone --------------------------------------------

@test "global default (CLAUDE_TQ_CHECKPOINT_MODE) arms checkpoint with no per-repo flag" {
  run bash -c 'cd "$1" && CLAUDE_TQ_CHECKPOINT_MODE=on bash "$2" status' _ "$REPO" "$CKPT"
  [[ "$output" == on* ]]
}

@test "global default still snapshots with no per-repo flag (fast-exit honors the env)" {
  printf 'v2\n' >> "$REPO/tracked.txt"
  CLAUDE_TQ_CHECKPOINT_MODE=on bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | "$2" now' _ "$REPO" "$CKPT"
  run ckpt_ref
  [ "$status" -eq 0 ]
}

@test "an off tombstone overrides the global default for this repo" {
  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$CKPT"   # writes an off tombstone
  run bash -c 'cd "$1" && CLAUDE_TQ_CHECKPOINT_MODE=on bash "$2" status' _ "$REPO" "$CKPT"
  [[ "$output" == off* ]]
}

@test "checkpoint rejects an unknown action" {
  run bash -c 'cd "$1" && bash "$2" wat' _ "$REPO" "$CKPT"
  [ "$status" -eq 2 ]
}

# ---- snapshot behavior ------------------------------------------------------

@test "now is a no-op when disarmed (no ref created)" {
  printf 'edit\n' >> "$REPO/tracked.txt"
  snapshot
  run ckpt_ref
  [ "$status" -ne 0 ]        # no checkpoint ref exists
}

@test "now snapshots tracked+untracked edits into the ref, untouching HEAD/index/worktree" {
  arm
  printf 'v2\n' >> "$REPO/tracked.txt"          # modify tracked
  printf 'new\n' > "$REPO/untracked.txt"        # add untracked
  local pre_head pre_status
  pre_head="$(git -C "$REPO" rev-parse HEAD)"
  pre_status="$(git -C "$REPO" status --porcelain)"

  snapshot
  run ckpt_ref
  [ "$status" -eq 0 ]                            # a checkpoint now exists

  # HEAD, index and working-tree state are all exactly as before the snapshot.
  [ "$(git -C "$REPO" rev-parse HEAD)" = "$pre_head" ]
  [ "$(git -C "$REPO" status --porcelain)" = "$pre_status" ]

  # ...and the snapshot tree carries BOTH the tracked edit and the untracked file.
  run git -C "$REPO" show refs/tq/checkpoint:tracked.txt
  [[ "$output" == *"v2"* ]]
  run git -C "$REPO" show refs/tq/checkpoint:untracked.txt
  [[ "$output" == *"new"* ]]
}

@test "restore recovers edits a crash would have lost" {
  arm
  printf 'precious\n' >> "$REPO/tracked.txt"
  printf 'alsoprecious\n' > "$REPO/untracked.txt"
  snapshot
  # Simulate a crash+recovery that lost the uncommitted edits:
  git -C "$REPO" checkout -q -- tracked.txt
  rm -f "$REPO/untracked.txt"
  # Restore from the checkpoint ref (the documented recovery command).
  git -C "$REPO" restore --source=refs/tq/checkpoint --worktree -- .
  run cat "$REPO/tracked.txt"
  [[ "$output" == *"precious"* ]]
  [ -f "$REPO/untracked.txt" ]
}

@test "the restore subcommand recovers lost edits (backs /task-queue:restore)" {
  arm
  printf 'recover-me\n' >> "$REPO/tracked.txt"
  snapshot
  git -C "$REPO" checkout -q -- tracked.txt      # simulate the crash losing the edit
  run bash -c 'cd "$1" && bash "$2" restore' _ "$REPO" "$CKPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"restored working tree"* ]]
  run cat "$REPO/tracked.txt"
  [[ "$output" == *"recover-me"* ]]
}

@test "restore is a friendly no-op when there is no checkpoint" {
  arm
  run bash -c 'cd "$1" && bash "$2" restore' _ "$REPO" "$CKPT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"no checkpoint to restore"* ]]
}

@test "unchanged tree is not re-snapshotted (ref stays put)" {
  arm
  printf 'v2\n' >> "$REPO/tracked.txt"
  snapshot
  local first; first="$(ckpt_ref)"
  snapshot                                   # nothing changed since
  [ "$(ckpt_ref)" = "$first" ]
}

@test "now outside a git repo is a silent no-op" {
  local notrepo; notrepo="$(mktemp -d)"
  run bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | "$2" now' _ "$notrepo" "$CKPT"
  [ "$status" -eq 0 ]
  rm -rf "$notrepo"
}

# ---- SessionStart surfacing -------------------------------------------------

@test "SessionStart is silent about checkpoint when disarmed" {
  json="$(jq -nc --arg c "$REPO" '{session_id:"s2", cwd:$c, source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$json" "$RESUME"
  [[ "$output" != *"Crash-checkpoint is ARMED"* ]]
}

@test "SessionStart shows the armed line, with a restore hint once a snapshot exists" {
  arm
  json="$(jq -nc --arg c "$REPO" '{session_id:"s2", cwd:$c, source:"startup"}')"
  ctx() { printf '%s' "$json" | "$RESUME" | jq -r .hookSpecificOutput.additionalContext; }
  run ctx
  [[ "$output" == *"Crash-checkpoint is ARMED"* ]]
  [[ "$output" != *"restore them with"* ]]     # no ref yet → no restore hint

  printf 'v2\n' >> "$REPO/tracked.txt"; snapshot
  run ctx
  [[ "$output" == *"restore them with"* ]]      # ref exists → restore command shown
  [[ "$output" == *"git restore --source=refs/tq/checkpoint"* ]]
}
