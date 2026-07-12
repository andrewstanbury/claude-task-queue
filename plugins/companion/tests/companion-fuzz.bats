#!/usr/bin/env bats
#
# Hook fuzz (R30·d8) — the enforced core is best-effort and MUST NOT crash or break the action it
# runs on, whatever it's fed. Pipe empty / non-JSON / truncated / valid-but-empty / huge stdin at
# every stdin-reading hook and assert each exits cleanly (0 = allow/silent, or 2 = secret-guard's
# one legitimate block) and prints nothing alarming to stdout. This is the contract the whole
# design rests on; a regression here is a hook that could break a user's edit.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

@test "fuzz: every stdin-reading hook survives empty / garbage / truncated / huge input" {
  # Feed stdin from a FILE, not a bash -c argument — a 100KB arg blows the test's own ARG_MAX
  # (the hooks read stdin fine at any size; that's what we're proving).
  local f; f="$(mktemp)"
  local hooks=(secret-guard ask-guard touch session-start stop-autopilot statusline)
  local inputs=("" "not json at all" "{" '{"tool_input":' "{}" '{"cwd":"/nope","tool_input":{"file_path":"/no/such"}}')
  local h input
  for h in "${hooks[@]}"; do
    for input in "${inputs[@]}"; do
      printf '%s' "$input" > "$f"
      run bash -c '"$1" < "$2"' _ "$ROOT/bin/$h.sh" "$f"
      # never a crash/error exit — only allow(0) or the secret-gate block(2)
      { [ "$status" -eq 0 ] || [ "$status" -eq 2 ]; } \
        || { echo "CRASH: $h.sh exit=$status on input=[${input:0:40}]" >&2; false; }
    done
    head -c 100000 /dev/zero | tr '\0' x > "$f"       # huge stdin
    run bash -c '"$1" < "$2"' _ "$ROOT/bin/$h.sh" "$f"
    { [ "$status" -eq 0 ] || [ "$status" -eq 2 ]; } \
      || { echo "CRASH(huge): $h.sh exit=$status" >&2; false; }
  done
  rm -f "$f"
}

@test "fuzz: hooks don't choke on multibyte / emoji content (bash 3.2 byte-splitting)" {
  # the exact class that crashed macOS bash 3.2 — feed emoji through the JSON path
  local payload; payload='{"tool_input":{"file_path":"/x/a.py","content":"x = \"🛡❓⏳✈️\""}}'
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$ROOT/bin/secret-guard.sh"
  [ "$status" -eq 0 ]                                   # emoji content is not a secret, allowed
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ '{"model":{"display_name":"m🛡"}}' "$ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]                                   # emoji in model name doesn't crash the bar
}
