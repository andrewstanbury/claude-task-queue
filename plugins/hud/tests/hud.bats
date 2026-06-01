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

@test "hud_qa aligns with charter: QUALITY.adoc, docs/CLAUDE.md, and the override" {
  run bash -c "$SRC"' hud_qa "$2"' bash "$ROOT" "$REPO"; [ "$output" = "0" ]
  : > "$REPO/QUALITY.adoc"
  run bash -c "$SRC"' hud_qa "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
  rm "$REPO/QUALITY.adoc"; mkdir -p "$REPO/docs"
  printf '# Manual\n## Non-functional requirements\n' > "$REPO/docs/CLAUDE.md"
  run bash -c "$SRC"' hud_qa "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
}

@test "hud_map / hud_roadmap detect the charter baseline docs" {
  run bash -c "$SRC"' hud_map "$2"' bash "$ROOT" "$REPO"; [ "$output" = "0" ]
  run bash -c "$SRC"' hud_roadmap "$2"' bash "$ROOT" "$REPO"; [ "$output" = "0" ]
  mkdir -p "$REPO/docs"; : > "$REPO/docs/MAP.md"; : > "$REPO/docs/ROADMAP.md"
  run bash -c "$SRC"' hud_map "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
  run bash -c "$SRC"' hud_roadmap "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
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

@test "hud_last_tidy extracts the touched filename from the tidy log" {
  printf 'ts\tgo\tfile=/proj/auth/login.go fmt=goimports\n' > "$CLAUDE_HUD_TIDY_LOG"
  run bash -c "$SRC"' hud_last_tidy' bash "$ROOT"
  [ "$output" = "login.go" ]
}

@test "renders a single line with the key slots (ctx %, model, tasks)" {
  mk_task sess 1 in_progress "Wire auth"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus 4.8"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:68, context_window_size:1000000}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wire auth"* ]]
  [[ "$output" == *"ctx 68%"* ]]
  [[ "$output" == *"docs 0/3"* ]]
  [[ "$output" == *"Opus 4.8"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]   # single line
}

@test "render: ✓ tests + docs ✓ when verify passed and baseline docs present" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  mkdir -p "$REPO/docs"; : > "$REPO/docs/MAP.md"; : > "$REPO/docs/ROADMAP.md"; : > "$REPO/QUALITY.md"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✓ tests"* ]]
  [[ "$output" == *"docs ✓"* ]]
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
