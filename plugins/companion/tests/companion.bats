#!/usr/bin/env bats
#
# Tests for the companion's ENFORCED CORE — the only behavior that must execute or block
# (the steering layer is STEERING.md, prose the model reads; it isn't unit-testable, and
# pretending otherwise was the old system's mistake). Four things are real code: the secret
# gate, `tq` (THE queue — the companion owns its store; it does NOT use native tasks),
# SessionStart (steering + root-scoped resume), and the status line.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR"; }

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

# ---- tq (THE queue, companion-owned store) ----

@test "tq: add/doing/done write the companion store + stamp the repo root; report groups by state" {
  ( cd "$ROOT" && "$TQ" add "build it" "❓ pick a backend" ) >/dev/null
  [ -f "$CLAUDE_COMPANION_TASKS_DIR/s1/.root" ]                # session dir stamped with the repo root
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

# ---- session start (steering + root-scoped resume, no native transcript) ----

@test "session start: injects STEERING and resumes THIS repo's tasks only (scoped by .root)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sMine"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sMine/.root"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOther"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"

  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"new\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]   # STEERING injected
  [[ "$output" == *"resume me"* ]]           # this repo's task
  [[ "$output" != *"NOT MINE"* ]]            # no cross-repo bleed
}

# ---- status line (the glance surface) ----

@test "status line: renders 🛡 · model · tokens · task count · project · branch" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sBar"
  jq -n '{id:"1",subject:"a",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sBar/1.json"
  jq -n '{id:"2",subject:"b",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sBar/2.json"
  jq -n '{id:"3",subject:"c",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/sBar/3.json"
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"claude-opus-4-8"},session_id:"sBar",cwd:$c,context_window:{total_input_tokens:45200,total_output_tokens:1300}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"🛡"* ]]            # secret gate on
  [[ "$output" == *"opus-4-8"* ]]      # model, claude- prefix + date stripped
  [[ "$output" == *"⇡45.2k"* ]]        # up tokens
  [[ "$output" == *"⇣1.3k"* ]]         # down tokens
  [[ "$output" == *"📋 2"* ]]           # 2 open (completed excluded)
  [[ "$output" == *"⎇"* ]]             # branch
}

@test "status line: 🛡✗ when the secret gate is disabled" {
  run bash -c 'printf "{}" | CLAUDE_COMPANION_SECSCAN=0 NO_COLOR=1 "$1"' _ "$SL"
  [[ "$output" == *"🛡✗"* ]]
}
