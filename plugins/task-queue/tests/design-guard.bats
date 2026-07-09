#!/usr/bin/env bats
#
# Tests for the DESIGN-PREVIEW gate: bin/tq-design-guard.sh + the capture/ask-guard
# wiring. A visual/design prompt arms a per-session marker; the PreToolUse guard denies
# edits until a preview (AskUserQuestion) is shown, which the ask-guard clears. Faked
# via CLAUDE_TQ_* overrides + a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_AGENT_MODE
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/tq-design-guard.sh"
  ASK="$ROOT/bin/tq-ask-guard.sh"
  CAPTURE="$ROOT/bin/tq-capture.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  SID="sess1"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  REPO="$(git -C "$REPO" rev-parse --show-toplevel)"
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_TQ_AWAY_DIR" \
         "$CLAUDE_TQ_PROJECTS_DIR" "$(dirname "$REPO")"
}

design_flag() { printf '%s/design-%s' "$CLAUDE_TQ_AWAY_DIR" "$SID"; }   # marker now lives in the shared away dir (hud-readable)
guard()  { bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"%s\"}" "$1" "$2" | bash "$3"' _ "$REPO" "$SID" "$GUARD"; }
capture() { bash -c 'printf "{\"prompt\":\"%s\",\"cwd\":\"%s\",\"session_id\":\"%s\"}" "$1" "$2" "$3" | bash "$4" >/dev/null' _ "$1" "$REPO" "$SID" "$CAPTURE"; }
away_flag() { printf '%s/%s' "$CLAUDE_TQ_AWAY_DIR" "$(printf '%s' "$REPO" | sed 's:/:-:g')"; }

@test "guard is silent when no design preview is pending" {
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "capture arms the design marker on a visual prompt" {
  capture "make the login page prettier"
  [ -f "$(design_flag)" ]
}

@test "capture does NOT arm (and clears) on a non-visual prompt" {
  : > "$(design_flag)"                       # pretend a stale marker
  capture "add rate limiting to the API"
  [ ! -f "$(design_flag)" ]
}

@test "guard denies an edit while a design preview is pending" {
  : > "$(design_flag)"
  run guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
  [[ "$output" == *"Design-preview pending"* ]]
}

@test "showing an AskUserQuestion clears the design marker (via the ask-guard)" {
  : > "$(design_flag)"
  bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"%s\"}" "$1" "$2" | bash "$3" >/dev/null' _ "$REPO" "$SID" "$ASK"
  [ ! -f "$(design_flag)" ]
  run guard                                   # now unblocked
  [ -z "$output" ]
}

@test "guard stands down during an autopilot drain (away + owner absent)" {
  : > "$(design_flag)"
  : > "$(away_flag)"                          # autopilot on, no present marker → absent
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]                            # design decisions are parked, not gated
}

@test "guard allows when disabled via CLAUDE_TQ_DESIGN_GATE=0" {
  : > "$(design_flag)"
  run bash -c 'printf "{\"cwd\":\"%s\",\"session_id\":\"%s\"}" "$1" "$2" | CLAUDE_TQ_DESIGN_GATE=0 bash "$3"' _ "$REPO" "$SID" "$GUARD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
