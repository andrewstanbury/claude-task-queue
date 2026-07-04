#!/usr/bin/env bats
#
# Tests for the per-feature toggle actions that back the /task-queue:* slash
# commands (autopilot / checkpoint / agents). Each `toggle` flips this repo's flag
# and announces the new state. The old single /tq hub + dispatcher were retired in
# favor of one command per feature (discoverable via Claude Code's / menu).
# Everything faked via CLAUDE_TQ_* overrides + a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_CHECKPOINT_MODE CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  AWAY="$ROOT/bin/tq-away.sh"
  CKPT="$ROOT/bin/tq-checkpoint.sh"
  AGENT="$ROOT/bin/tq-agent.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AGENT_DIR="$(mktemp -d)"
  export CLAUDE_TQ_CKPT_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_TQ_AWAY_DIR" \
         "$CLAUDE_TQ_AGENT_DIR" "$CLAUDE_TQ_CKPT_DIR" "$(dirname "$REPO")"
}
# Run a bin script for $REPO: at <script> [args...]
at() { bash -c 'cd "$1" && shift && bash "$@"' _ "$REPO" "$@"; }

@test "autopilot toggle flips off → on → off" {
  run at "$AWAY" status; [[ "$output" == off* ]]
  at "$AWAY" toggle
  run at "$AWAY" status; [[ "$output" == on* ]]
  at "$AWAY" toggle
  run at "$AWAY" status; [[ "$output" == off* ]]
}

@test "autopilot toggle announces the new state in plain words" {
  run at "$AWAY" toggle; [[ "$output" == *"Autopilot ON"* ]]
  run at "$AWAY" toggle; [[ "$output" == *"Autopilot OFF"* ]]
}

@test "checkpoint toggle flips off → on → off" {
  run at "$CKPT" status; [[ "$output" == off* ]]
  at "$CKPT" toggle
  run at "$CKPT" status; [[ "$output" == on* ]]
  at "$CKPT" toggle
  run at "$CKPT" status; [[ "$output" == off* ]]
}

@test "agents toggle flips off → on → off" {
  run at "$AGENT" status; [[ "$output" == off* ]]
  at "$AGENT" toggle
  run at "$AGENT" status; [[ "$output" == on* ]]
  at "$AGENT" toggle
  run at "$AGENT" status; [[ "$output" == off* ]]
}

@test "checkpoint off writes a tombstone that overrides the global default" {
  CLAUDE_TQ_CHECKPOINT_MODE=on run at "$CKPT" status; [[ "$output" == on* ]]   # armed via env
  CLAUDE_TQ_CHECKPOINT_MODE=on at "$CKPT" off                                  # explicit per-repo off
  CLAUDE_TQ_CHECKPOINT_MODE=on run at "$CKPT" status; [[ "$output" == off* ]]  # tombstone wins
}

@test "agents off writes a tombstone that overrides the global default" {
  CLAUDE_TQ_AGENT_MODE=on run at "$AGENT" status; [[ "$output" == on* ]]
  CLAUDE_TQ_AGENT_MODE=on at "$AGENT" off
  CLAUDE_TQ_AGENT_MODE=on run at "$AGENT" status; [[ "$output" == off* ]]
}
