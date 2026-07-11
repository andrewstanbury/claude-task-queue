#!/usr/bin/env bats
#
# Tests for the companion's ENFORCED CORE — the only behavior that must execute or block
# (the steering layer is STEERING.md, prose the model reads; it isn't unit-testable, and
# pretending otherwise was the old system's mistake). Three things are real code, so three
# things get tested: the secret gate blocks/allows correctly, `tq` writes the native store
# every reader keys off, and SessionStart injects the steering + resumes THIS repo's tasks.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_PROJECTS_DIR"; }

# ---- secret gate (the one enforced content block) ----

@test "secret gate: blocks a real AWS key (exit 2)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{file_path:\"/x/c.py\",content:\$c}}" | "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret gate: blocks a generic secret literal (exit 2)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/c.py\",content:\"password = \\\"hunter2primetime\\\"\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 2 ]
}

@test "secret gate: allows a placeholder (exit 0)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/c.py\",content:\"API_KEY = \\\"your-key-here\\\"\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]
}

@test "secret gate: allows ordinary code (exit 0)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/a.py\",content:\"def add(a,b): return a+b\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]
}

@test "secret gate: disabled via CLAUDE_COMPANION_SECSCAN=0" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'CLAUDE_COMPANION_SECSCAN=0 bash -c "jq -nc --arg c \"\$1\" \"{tool_input:{file_path:\\\"/x/c.py\\\",content:\\\$c}}\" | \"\$2\"" _ "$1" "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
}

# ---- tq fallback (writes the native store) ----

@test "tq: add/doing/done write native-format JSON; report groups by state" {
  "$TQ" add "build it" "❓ pick a backend" >/dev/null
  run jq -r '.subject + "|" + .status' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json"
  [ "$output" = "build it|pending" ]
  "$TQ" doing 1 >/dev/null
  [ "$(jq -r .status "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "in_progress" ]
  run "$TQ" done 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"#1 → completed"* ]]
  [[ "$output" == *"📋 Task queue"* ]]
  [[ "$output" == *"1 parked"* ]]
  [[ "$output" == *"✔ #1"* ]]
}

@test "tq: no session id errors cleanly" {
  run env -u CLAUDE_COMPANION_SESSION_ID -u CLAUDE_CODE_SESSION_ID "$TQ" add x
  [ "$status" -ne 0 ]
  [[ "$output" == *"session id"* ]]
}

# ---- session start (steering + repo-scoped resume) ----

@test "session start: injects STEERING and resumes THIS repo's tasks only" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local enc; enc="$(printf '%s' "$repo" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_COMPANION_PROJECTS_DIR/$enc" "$CLAUDE_COMPANION_TASKS_DIR/sMine"
  printf '{"cwd":"%s"}\n' "$repo" > "$CLAUDE_COMPANION_PROJECTS_DIR/$enc/sMine.jsonl"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_PROJECTS_DIR/-other" "$CLAUDE_COMPANION_TASKS_DIR/sOther"
  printf '{"cwd":"/other/x"}\n' > "$CLAUDE_COMPANION_PROJECTS_DIR/-other/sOther.jsonl"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"

  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"new\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]   # STEERING injected
  [[ "$output" == *"resume me"* ]]           # this repo's task
  [[ "$output" != *"NOT MINE"* ]]            # no cross-project bleed
}
