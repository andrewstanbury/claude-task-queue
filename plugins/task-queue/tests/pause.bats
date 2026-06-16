#!/usr/bin/env bats
#
# Tests for the per-repo pause: bin/tq-pause.sh, the capture hook honoring it
# (the review loop stays silent when paused), and the SessionStart banner.
# Everything faked via CLAUDE_TQ_* overrides and temp git repos — no model calls.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PAUSE="$ROOT/bin/tq-pause.sh"
  CAPTURE="$ROOT/bin/tq-capture.sh"
  RESUME="$ROOT/bin/tq-resume.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PAUSE_DIR="$(mktemp -d)"
  unset CLAUDE_TQ_CAPTURE_DISABLED

  REPO="$(mktemp -d)/proj"
  mkdir -p "$REPO" && git -C "$REPO" init -q
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" \
         "$CLAUDE_TQ_PAUSE_DIR" "$(dirname "$REPO")"
}

# Feed tq-capture a substantive prompt for $REPO; echo injected text or "".
run_capture() {
  local prompt="$1" json
  json="$(jq -nc --arg p "$prompt" --arg c "$REPO" '{prompt:$p, session_id:"sess", cwd:$c}')"
  printf '%s' "$json" | "$CAPTURE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

SUBSTANTIVE="add the login form and then wire the auth endpoint and update the tests"

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

# ---- the review loop honoring the pause ------------------------------------

@test "review loop fires on a substantive prompt when not paused (control)" {
  run run_capture "$SUBSTANTIVE"
  [[ "$output" == *"interpret→present→approve"* ]]
}

@test "review loop stays silent when the repo is paused" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$PAUSE"
  run run_capture "$SUBSTANTIVE"
  [ -z "$output" ]
}

@test "resuming re-enables the review loop" {
  bash -c 'cd "$1" && bash "$2" on'  _ "$REPO" "$PAUSE"
  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$PAUSE"
  run run_capture "$SUBSTANTIVE"
  [[ "$output" == *"interpret→present→approve"* ]]
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
