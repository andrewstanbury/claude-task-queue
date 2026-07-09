#!/usr/bin/env bats
#
# Tests for tidy's edit-time secret floor (lib/secscan.sh + bin/tidy-presecret.sh).
# Secret-shaped fixtures are ASSEMBLED AT RUNTIME from fragments so the literal never
# appears contiguous in this file — otherwise gitleaks (check.sh) and the scan itself
# would flag the test source (SPEC §17 trap).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$ROOT/bin/tidy-presecret.sh"
  # shellcheck source=../lib/secscan.sh
  . "$ROOT/lib/secscan.sh"
  WORK="$(mktemp -d)"
}
teardown() { rm -rf "$WORK"; }

# Real AWS-access-key shape (AKIA + 16 upper-alnum), never contiguous in source.
aws_key() { printf '%s%s' "AKIA" "ABCDEFGHIJKLMNOP"; }

# Drive the PreToolUse hook with a Write payload; $status = exit code, $output = both
# streams (bats merges stderr into output).
run_hook() { # $1=file_path  $2=content
  local json
  json="$(jq -nc --arg p "$1" --arg c "$2" \
            '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}')"
  printf '%s' "$json" | "$HOOK"
}

# --- the block path (the whole point) ---

@test "blocks an AWS-key-shaped literal before write" {
  run run_hook "$WORK/config.py" "API_KEY = '$(aws_key)'"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED by tidy secret-scan"* ]]
}

@test "blocks a PEM private-key block" {
  run run_hook "$WORK/key.js" "const k = \`-----BEGIN RSA PRIVATE KEY-----\`"
  [ "$status" -eq 2 ]
}

@test "blocks a generic long credential assignment" {
  run run_hook "$WORK/s.py" "password = '8f3aB9xK2mNp7qRt5wYz'"
  [ "$status" -eq 2 ]
}

# --- the must-not-block paths (false positives BLOCK real work, so these matter) ---

@test "allows ordinary code untouched" {
  run run_hook "$WORK/math.py" "def add(a, b):\n    return a + b\n"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "allows an obvious placeholder credential" {
  run run_hook "$WORK/s.py" "password = 'your_password_here'"
  [ "$status" -eq 0 ]
}

@test "allows an env-var reference, not a literal" {
  run run_hook "$WORK/s.py" "api_key = os.environ['API_KEY']"
  [ "$status" -eq 0 ]
}

# --- exclusions ---

@test "does not scan markdown (docs describe secret shapes)" {
  run run_hook "$WORK/README.md" "Example: API_KEY = '$(aws_key)'"
  [ "$status" -eq 0 ]
}

@test "does not scan fixture/test trees" {
  run run_hook "$WORK/tests/fixtures/sample.py" "KEY = '$(aws_key)'"
  [ "$status" -eq 0 ]
}

# --- disable switch + payload robustness ---

@test "CLAUDE_TIDY_SECSCAN=0 disables the block" {
  json="$(jq -nc --arg p "$WORK/c.py" --arg c "K='$(aws_key)'" \
            '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}')"
  run bash -c 'CLAUDE_TIDY_SECSCAN=0 "$1" <<<"$2"' _ "$HOOK" "$json"
  [ "$status" -eq 0 ]
}

@test "scans MultiEdit new_string content" {
  json="$(jq -nc --arg p "$WORK/c.py" --arg s "tok = '$(aws_key)'" \
            '{tool_name:"MultiEdit", tool_input:{file_path:$p, edits:[{old_string:"x", new_string:$s}]}}')"
  run bash -c 'printf "%s" "$2" | "$1"' _ "$HOOK" "$json"
  [ "$status" -eq 2 ]
}

@test "scans NotebookEdit new_source content" {
  json="$(jq -nc --arg p "$WORK/nb.ipynb" --arg s "tok = '$(aws_key)'" \
            '{tool_name:"NotebookEdit", tool_input:{file_path:$p, new_source:$s}}')"
  run bash -c 'printf "%s" "$2" | "$1"' _ "$HOOK" "$json"
  [ "$status" -eq 2 ]
}

@test "allows a clean NotebookEdit" {
  json="$(jq -nc --arg p "$WORK/nb.ipynb" --arg s "print('hello world')" \
            '{tool_name:"NotebookEdit", tool_input:{file_path:$p, new_source:$s}}')"
  run bash -c 'printf "%s" "$2" | "$1"' _ "$HOOK" "$json"
  [ "$status" -eq 0 ]
}

@test "empty / shapeless payload passes through" {
  run bash -c 'printf "%s" "{}" | "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
}

# --- unit: tidy_secscan_text directly ---

@test "tidy_secscan_text returns 0 + reason on a hit, 1 on clean" {
  run tidy_secscan_text "key = '$(aws_key)'" "/x.py"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  run tidy_secscan_text "let total = price * qty" "/x.js"
  [ "$status" -eq 1 ]
}

@test "tidy_secscan_text never echoes the raw secret back" {
  run tidy_secscan_text "key = '$(aws_key)'" "/x.py"
  [[ "$output" != *"$(aws_key)"* ]]
}
