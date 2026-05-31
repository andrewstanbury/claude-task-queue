#!/usr/bin/env bats
#
# Tests for the hud status line: the read-only accessors and a render smoke
# test. Faked via CLAUDE_HUD_* overrides + a temp git repo.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/hud-status.sh"
  export CLAUDE_HUD_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_HUD_PAUSE_DIR="$(mktemp -d)"
  export CLAUDE_HUD_TIDY_LOG="$(mktemp -d)/activity.log"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  SRC='. "$1/lib/hud.sh";'
}

teardown() {
  rm -rf "$CLAUDE_HUD_TASKS_DIR" "$CLAUDE_HUD_PAUSE_DIR" \
         "$(dirname "$CLAUDE_HUD_TIDY_LOG")" "$(dirname "$REPO")"
}

mk_task() {
  mkdir -p "$CLAUDE_HUD_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" --arg subj "$4" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_HUD_TASKS_DIR/$1/$2.json"
}

@test "hud_tasks counts open tasks and reports the in-progress subject" {
  mk_task sess 1 in_progress "Wire auth"; mk_task sess 2 pending x; mk_task sess 3 completed done
  run bash -c "$SRC"' hud_tasks sess' bash "$ROOT"
  [[ "$output" == "2"*"Wire auth" ]]            # 2 open (completed excluded), doing = Wire auth
}

@test "hud_paused reflects the repo's pause flag" {
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "0" ]
  touch "$CLAUDE_HUD_PAUSE_DIR/-some-repo"
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "1" ]
}

@test "hud_qa detects documented quality attributes" {
  run bash -c "$SRC"' hud_qa "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "0" ]
  : > "$REPO/QUALITY.md"
  run bash -c "$SRC"' hud_qa "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "1" ]
}

@test "hud_last_tidy extracts the touched filename from the tidy log" {
  printf 'ts\tgo\tfile=/proj/auth/login.go fmt=goimports\n' > "$CLAUDE_HUD_TIDY_LOG"
  run bash -c "$SRC"' hud_last_tidy' bash "$ROOT"
  [ "$output" = "login.go" ]
}

@test "hud_fmt_k humanizes counts" {
  run bash -c "$SRC"' hud_fmt_k 1234' bash "$ROOT"; [ "$output" = "1.2k" ]
  run bash -c "$SRC"' hud_fmt_k 2000000' bash "$ROOT"; [ "$output" = "2.0M" ]
}

@test "renders a single line with the key slots" {
  mk_task sess 1 in_progress "Wire auth"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus 4.8"}, session_id:"sess", cwd:$c,
      context_window:{total_input_tokens:12345, total_output_tokens:4567}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wire auth"* ]]
  [[ "$output" == *"Tokens:"* ]]
  [[ "$output" == *"12.3k"* ]]
  [[ "$output" == *"Opus 4.8"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]   # single line
}
