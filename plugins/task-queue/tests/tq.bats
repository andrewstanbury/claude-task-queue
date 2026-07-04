#!/usr/bin/env bats
#
# Tests for the /tq hub (bin/tq.sh) — the single control command that replaced the
# per-mode slash commands. It's a thin dispatcher, so these check ROUTING: bare =
# menu, each subcommand reaches the right bin script, unknown = usage error. The
# modes' own behavior is covered by away.bats / checkpoint.bats.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$ROOT/bin/tq.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AGENT_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_TQ_AWAY_DIR" \
         "$CLAUDE_TQ_AGENT_DIR" "$(dirname "$REPO")"
}
tq() { bash -c 'cd "$1" && shift && bash "$@"' _ "$REPO" "$TQ" "$@"; }

@test "bare /tq prints the mode menu" {
  run tq
  [ "$status" -eq 0 ]
  [[ "$output" == *"modes"* ]]
  [[ "$output" == *"solo"* ]]
  [[ "$output" == *"bare /tq = this menu"* ]]
}

@test "/tq solo on|off toggles the (merged) autonomous mode" {
  tq solo on
  run tq solo status
  [[ "$output" == on* ]]
  run tq                                  # menu reflects it
  [[ "$output" == *"solo          ON"* ]]
  tq solo off
  run tq solo status
  [[ "$output" == off* ]]
}

@test "/tq agent on toggles agent-mode" {
  tq agent on
  run tq
  [[ "$output" == *"agent-mode    ON"* ]]
}

@test "/tq undo dispatches to checkpoint restore" {
  run tq undo
  [ "$status" -eq 0 ]                      # no snapshot → benign message, still exits 0
  [[ "$output" == *"checkpoint"* || "$output" == *"restore"* || "$output" == *"snapshot"* ]]
}

@test "/tq with an unknown subcommand errors with usage" {
  run tq frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: /tq"* ]]
}
