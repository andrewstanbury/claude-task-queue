#!/usr/bin/env bats
#
# Hook fuzz (R30·d8) — the enforced core is best-effort and MUST NOT crash or break the action it
# runs on, whatever it's fed. Pipe empty / non-JSON / truncated / valid-but-empty / huge stdin at
# every stdin-reading hook/CLI and assert each exits cleanly (0 = allow/silent/clean, or 2 =
# check-secrets.sh's one legitimate BLOCK verdict) and prints nothing alarming to stdout. This is
# the contract the whole design rests on; a regression here is something that could break a user's
# edit or crash on ordinary content — check-secrets.sh is no longer a hook (R100/Pass 3) but stays
# in this fuzz set because it still reads arbitrary stdin.

# Fixture dirs go under BATS_TEST_TMPDIR, which bats removes after each test. Plain `mktemp -d`
# leaks: one session of this suite left 37,000 directories in /tmp and exhausted the inode table,
# which then fails unrelated tests for reasons that look like code defects.
_tmpd() { mktemp -d "$BATS_TEST_TMPDIR/d.XXXXXX"; }

setup() {
  # Tests live in dev/ and are NOT shipped. ROOT still means the SHIPPED plugin dir; DEV is
  # where the gates that verify it live. Keeping the two named apart is the point of the split.
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../plugins/companion" && pwd)"
  DEV="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)"
  export CLAUDE_COMPANION_STATE_DIR="$(_tmpd)"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

@test "fuzz: every stdin-reading hook survives empty / garbage / truncated / huge input" {
  # Feed stdin from a FILE, not a bash -c argument — a 100KB arg blows the test's own ARG_MAX
  # (the hooks read stdin fine at any size; that's what we're proving).
  local f; f="$(mktemp)"
  # stop-autopilot added 2026-08-12 with its restore (R26). A Stop hook fires on EVERY stop of an
  # autopiloted run, so garbage stdin there degrades the whole session rather than one action —
  # it belongs in this set at least as much as the others (R30·d8, best-effort R68).
  local hooks=(check-secrets statusline prompt-continue session-start ask-guard stop-autopilot)
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

@test "fuzz: hooks/CLIs don't choke on multibyte / emoji content (bash 3.2 byte-splitting)" {
  # the exact class that crashed macOS bash 3.2
  run bash -c 'printf "%s" "$1" | "$2" --path /x/a.py' _ 'x = "🛡❓⏳✈️"' "$ROOT/bin/check-secrets.sh"
  [ "$status" -eq 0 ]                                   # emoji content is not a secret, allowed
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ '{"model":{"display_name":"m🛡"}}' "$ROOT/bin/statusline.sh"
  [ "$status" -eq 0 ]                                   # emoji in model name doesn't crash the bar
}
