#!/usr/bin/env bats
# tq doctor output sanity. Doesn't assert on every line — just that the
# major sections appear and the overall summary reflects detected issues.

setup() {
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_HOME="$(mktemp -d)"
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TQ="$THIS_DIR/bin/tq"
  cd "$CLAUDE_TQ_STATE_DIR"
}

teardown() {
  rm -rf "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_HOME"
}

@test "tq doctor prints the major sections" {
  out="$($TQ doctor 2>&1)"
  [[ "$out" == *"Plugin"* ]]
  [[ "$out" == *"Dependencies"* ]]
  [[ "$out" == *"Settings.json hooks"* ]]
  [[ "$out" == *"Queue"* ]]
  [[ "$out" == *"Recent log"* ]]
}

@test "tq doctor flags missing settings.json as an issue" {
  out="$($TQ doctor 2>&1)"
  [[ "$out" == *"does not exist"* ]] || [[ "$out" == *"⚠️"* ]]
}

@test "tq doctor passes when settings.json is well-formed" {
  cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      { "id": "claude-task-queue", "matcher": "*", "hooks": [{"type": "command", "command": "..."}] }
    ],
    "PreToolUse": [
      { "id": "claude-task-queue", "matcher": "*", "hooks": [{"type": "command", "command": "..."}] }
    ]
  }
}
EOF
  out="$($TQ doctor 2>&1)"
  [[ "$out" == *"claude-task-queue: yes"* ]]
}

@test "tq doctor warns when confirm-intent is still registered" {
  cat > "$CLAUDE_HOME/settings.json" <<'EOF'
{
  "hooks": {
    "UserPromptSubmit": [
      { "id": "claude-task-queue", "matcher": "*", "hooks": [{"type": "command", "command": "..."}] },
      { "hooks": [{"type": "command", "command": "bash $HOME/.claude/hooks/confirm-intent.sh"}] }
    ],
    "PreToolUse": [
      { "id": "claude-task-queue", "matcher": "*", "hooks": [{"type": "command", "command": "..."}] }
    ]
  }
}
EOF
  out="$($TQ doctor 2>&1)"
  [[ "$out" == *"confirm-intent.sh still registered"* ]]
}

@test "tq doctor reports plugin version from manifest.json" {
  out="$($TQ doctor 2>&1)"
  [[ "$out" == *"v0.1"* ]]
}
