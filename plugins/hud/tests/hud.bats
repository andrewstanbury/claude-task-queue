#!/usr/bin/env bats
#
# Tests for the hud status line: the read-only accessors and a render smoke
# test. Faked via CLAUDE_HUD_* overrides + a temp git repo.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/hud-status.sh"
  export CLAUDE_HUD_PAUSE_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  SRC='. "$1/lib/hud.sh";'
}

teardown() {
  rm -rf "$CLAUDE_HUD_PAUSE_DIR" "$(dirname "$REPO")"
}

@test "hud_paused reflects the repo's pause flag" {
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "0" ]
  touch "$CLAUDE_HUD_PAUSE_DIR/-some-repo"
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "1" ]
}

@test "hud_agent reflects task-queue's per-repo agent-mode flag" {
  export CLAUDE_HUD_AGENT_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AGENT_DIR/-some-repo"
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  rm -rf "$CLAUDE_HUD_AGENT_DIR"
}

@test "hud_verify reads the verification floor's last outcome" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ -z "$output" ]
  printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sessabc"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ "$output" = "pass" ]
  printf 'fail' > "$CLAUDE_HUD_VERIFY_DIR/result-sessabc"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ "$output" = "fail" ]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "hud_dirty counts uncommitted files, empty on a clean tree" {
  run bash -c "$SRC"' hud_dirty "$2"' bash "$ROOT" "$REPO"; [ -z "$output" ]   # clean
  printf 'x\n' > "$REPO/new.txt"
  run bash -c "$SRC"' hud_dirty "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
}

@test "renders a single line with the key slots (ctx %, model)" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus 4.8"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:68, context_window_size:1000000}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctx 68%"* ]]
  [[ "$output" == *"Opus 4.8"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]   # single line
}

@test "render: ✓ tests when the verification floor last passed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✓ tests"* ]]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: ✗ tests when the verification floor last failed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'fail' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✗ tests"* ]]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: omits ctx when the payload has no context_window" {
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"ctx"* ]]
}

# ---- hud-install (status-line wiring) ---------------------------------------

@test "install: adds a version-resilient statusLine, preserving other settings" {
  local s; s="$(mktemp -d)/settings.json"
  printf '{"existingKey":true}\n' > "$s"
  run bash -c 'CLAUDE_SETTINGS="$1" "$2/bin/hud-install.sh"' _ "$s" "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.existingKey == true' "$s"                       # preserved
  jq -e '.statusLine.type == "command"' "$s"
  [[ "$(jq -r '.statusLine.command' "$s")" == *"sort -V | tail -1"* ]]   # self-resolving, not version-pinned
  [[ "$(jq -r '.statusLine.command' "$s")" != *"/0.1.0/"* ]]
  rm -rf "$(dirname "$s")"
}

@test "install: creates settings.json when absent" {
  local s; s="$(mktemp -d)/settings.json"   # file does not exist yet
  run bash -c 'CLAUDE_SETTINGS="$1" "$2/bin/hud-install.sh"' _ "$s" "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.statusLine.command' "$s"
  rm -rf "$(dirname "$s")"
}

@test "hud_open_questions counts pending/in_progress ❓ tasks (deduped), ignores the rest" {
  export CLAUDE_HUD_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_HUD_TASKS_DIR/sQ"
  jq -n '{id:"1",subject:"❓ Block or warn?",status:"pending"}'      > "$CLAUDE_HUD_TASKS_DIR/sQ/1.json"
  jq -n '{id:"2",subject:"❓ Which style?",status:"in_progress"}'    > "$CLAUDE_HUD_TASKS_DIR/sQ/2.json"
  jq -n '{id:"3",subject:"Do some work",status:"pending"}'          > "$CLAUDE_HUD_TASKS_DIR/sQ/3.json"
  jq -n '{id:"4",subject:"❓ already answered",status:"completed"}'  > "$CLAUDE_HUD_TASKS_DIR/sQ/4.json"
  run bash -c "$SRC"' hud_open_questions sQ' bash "$ROOT"
  [ "$output" = "2" ]
  run bash -c "$SRC"' hud_open_questions none' bash "$ROOT"
  [ "$output" = "0" ]
  rm -rf "$CLAUDE_HUD_TASKS_DIR"
}

@test "status line shows ❓N when open questions exist for the session" {
  export CLAUDE_HUD_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_HUD_TASKS_DIR/sR"
  jq -n '{id:"1",subject:"❓ pending one",status:"pending"}' > "$CLAUDE_HUD_TASKS_DIR/sR/1.json"
  json="$(jq -nc --arg s sR --arg c "$REPO" '{model:{display_name:"Opus"},session_id:$s,cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"❓1"* ]]
  rm -rf "$CLAUDE_HUD_TASKS_DIR"
}

@test "hud_coupling reads tidy's cached direction marker" {
  export CLAUDE_HUD_COUPLING_DIR="$(mktemp -d)"
  printf 'up' > "$CLAUDE_HUD_COUPLING_DIR/-some-repo"
  run bash -c "$SRC"' hud_coupling "/some/repo"' bash "$ROOT"; [ "$output" = "up" ]
  printf 'steady' > "$CLAUDE_HUD_COUPLING_DIR/-some-repo"
  run bash -c "$SRC"' hud_coupling "/some/repo"' bash "$ROOT"; [ "$output" = "steady" ]
  rm -rf "$CLAUDE_HUD_COUPLING_DIR"
}

@test "status line shows 🔗↑ only when coupling climbed (hidden when steady)" {
  export CLAUDE_HUD_COUPLING_DIR="$(mktemp -d)"
  enc="$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | sed 's:/:-:g')"
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c}')"
  printf 'up' > "$CLAUDE_HUD_COUPLING_DIR/$enc"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🔗↑"* ]]
  printf 'steady' > "$CLAUDE_HUD_COUPLING_DIR/$enc"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"🔗"* ]]
  rm -rf "$CLAUDE_HUD_COUPLING_DIR"
}
