#!/usr/bin/env bats
#
# Tests for charter-consent.sh — the PreToolUse hook that SURFACES (never blocks)
# consequential/irreversible actions for plain-language owner consent. Silent
# unless a pattern matches; always exits 0 and never emits a permissionDecision.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CONSENT="$ROOT/bin/charter-consent.sh"
  export CLAUDE_CHARTER_LOG_DIR="$(mktemp -d)"
}

teardown() { rm -rf "$CLAUDE_CHARTER_LOG_DIR"; }

# Feed a Bash payload; echo additionalContext (or "").
run_bash() {
  local json; json="$(jq -nc --arg c "$1" '{tool_name:"Bash", tool_input:{command:$c}}')"
  printf '%s' "$json" | "$CONSENT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

# Feed an Edit/Write payload by file_path.
run_file() {
  local json; json="$(jq -nc --arg p "$1" '{tool_name:"Write", tool_input:{file_path:$p}}')"
  printf '%s' "$json" | "$CONSENT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "surfaces a dependency add (cost / lock-in)" {
  run run_bash "npm install left-pad"
  [[ "$output" == *"consequential"* ]]
  [[ "$output" == *"dependency"* ]]
  run run_bash "yarn add react"
  [[ "$output" == *"dependency"* ]]
  run run_bash "go get github.com/foo/bar"
  [[ "$output" == *"dependency"* ]]
}

@test "surfaces destructive filesystem/history commands" {
  run run_bash "rm -rf build/"
  [[ "$output" == *"destructive or irreversible"* ]]
  run run_bash "git reset --hard origin/main"
  [[ "$output" == *"destructive or irreversible"* ]]
  run run_bash "git push --force origin main"
  [[ "$output" == *"destructive or irreversible"* ]]
}

@test "surfaces destructive database ops (case-insensitive)" {
  run run_bash "psql -c 'drop table users'"
  [[ "$output" == *"database"* ]]
  run run_bash "mysql -e 'DELETE FROM orders'"
  [[ "$output" == *"database"* ]]
}

@test "surfaces data migrations (command and file)" {
  run run_bash "npx prisma migrate deploy"
  [[ "$output" == *"migration"* ]]
  run run_file "prisma/migrations/0001_init/migration.sql"
  [[ "$output" == *"schema/migration"* ]]
}

@test "silent on benign commands and unrelated edits" {
  run run_bash "npm test"
  [ -z "$output" ]
  run run_bash "ls -la && git status"
  [ -z "$output" ]
  run run_bash "npm run build"
  [ -z "$output" ]
  run run_file "src/components/Button.tsx"
  [ -z "$output" ]
}

@test "never blocks: exits 0 and emits no permissionDecision" {
  json="$(jq -nc '{tool_name:"Bash", tool_input:{command:"rm -rf node_modules"}}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$CONSENT"
  [ "$status" -eq 0 ]
  # surfaces a reminder, but asserts no blocking decision is present
  [[ "$output" != *"permissionDecision"* ]]
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "PreToolUse"' >/dev/null
}

@test "disabled via env → fully silent" {
  export CLAUDE_CHARTER_CONSENT_DISABLED=1
  run run_bash "rm -rf /"
  [ -z "$output" ]
}

@test "drift-safe: a payload with no command/file_path stays silent and exits 0" {
  run bash -c 'printf "{\"tool_name\":\"Bash\",\"tool_input\":{}}" | "$1"' _ "$CONSENT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
