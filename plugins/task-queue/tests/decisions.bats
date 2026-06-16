#!/usr/bin/env bats
#
# Tests for the open-decisions ledger: the CLI (tq-ask.sh), the UserPromptSubmit
# re-injector (tq-decisions.sh), and the Notification alert (tq-notify.sh).
# Faked via a temp repo + CLAUDE_TQ_DECISIONS_DIR override.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  ASK="$ROOT/bin/tq-ask.sh"
  DEC="$ROOT/bin/tq-decisions.sh"
  NOTIFY="$ROOT/bin/tq-notify.sh"
  export CLAUDE_TQ_DECISIONS_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
}

teardown() { rm -rf "$CLAUDE_TQ_DECISIONS_DIR" "$(dirname "$REPO")"; }

# Run the CLI from inside the repo (it keys off $PWD's repo root).
ask() { ( cd "$REPO" && "$ASK" "$@" ); }
submit() { printf '{"cwd":"%s","session_id":"s1","prompt":"%s"}' "$REPO" "${1:-do other work}" | "$DEC"; }
notify() { printf '{"cwd":"%s","notification_type":"%s"}' "$REPO" "${1:-idle_prompt}" | "$NOTIFY"; }

@test "open logs a decision and list shows it with the recommended option" {
  run ask open "AA or AAA?" "AA + AAA contrast"
  [[ "$output" == *"#1"* ]]
  run ask list
  [[ "$output" == *"AA or AAA?"* ]]
  [[ "$output" == *"recommended: AA + AAA contrast"* ]]
}

@test "ids increment and resolve removes a single decision" {
  ask open "Q1" "r1"; ask open "Q2" "r2"
  run ask resolve 1
  [[ "$output" == *"Open now: 1"* ]]
  run ask list
  [[ "$output" != *"Q1"* ]]
  [[ "$output" == *"Q2"* ]]
}

@test "add: a corrupt ledger line doesn't collapse the next id (no collision)" {
  ask open "Q1" "r1"; ask open "Q2" "r2"               # ids 1, 2
  f="$CLAUDE_TQ_DECISIONS_DIR/$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | sed 's:/:-:g').jsonl"
  printf 'NOT VALID JSON {{\n' >> "$f"                  # crash-style partial line
  run ask open "Q3" "r3"
  [[ "$output" == *"#3"* ]]                             # max(1,2)+1, NOT a reset to 1
}

@test "resolve all clears the ledger" {
  ask open "Q1" "r1"; ask open "Q2" "r2"
  ask resolve all
  run ask list
  [[ "$output" == *"No open decisions"* ]]
}

@test "UserPromptSubmit re-injects open decisions + the protocol, every prompt" {
  ask open "Use the refactor?" "Yes"
  run submit "let's do something unrelated"
  [[ "$output" == *"OPEN DECISION"* ]]
  [[ "$output" == *"Use the refactor?"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  [[ "$output" == *"don't stall"* ]]
}

@test "UserPromptSubmit is silent when there are no open decisions" {
  run submit "anything"
  [ -z "$output" ]
}

@test "Notification emits a terminal alert when idle with open decisions" {
  ask open "Pick one" "A"
  run notify idle_prompt
  [[ "$output" == *"terminalSequence"* ]]
  [[ "$output" == *"open decision"* ]]
}

@test "Notification is silent with no open decisions, or on non-idle types" {
  run notify idle_prompt
  [ -z "$output" ]                        # nothing pending
  ask open "Pick one" "A"
  run notify auth_success
  [ -z "$output" ]                        # wrong type → no alert
}

@test "a decision with no recommended option still lists and re-injects (no errexit abort)" {
  ask open "Open-ended question?"        # no recommended arg
  run ask list
  [[ "$output" == *"Open-ended question?"* ]]
  run submit "x"
  [[ "$output" == *"Open-ended question?"* ]]
}

@test "the ledger is keyed by repo so the CLI and the hooks agree" {
  ask open "Shared?" "Yes"               # logged via CLI from $PWD=REPO
  run submit "x"                          # hook resolves root from cwd=REPO
  [[ "$output" == *"Shared?"* ]]          # same ledger
}
