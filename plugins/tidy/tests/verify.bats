#!/usr/bin/env bats
#
# Tests for the verification floor: lib/checks.sh (discover/run the project's own
# tests) and bin/tidy-verify.sh (the Stop hook that blocks until green, bounded).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  VERIFY="$ROOT/bin/tidy-verify.sh"
  WORK="$(mktemp -d)"
  export CLAUDE_TIDY_LOG_DIR="$WORK/log"
}
teardown() { rm -rf "$WORK"; }

# Feed the Stop hook a payload; echo its stdout.
run_verify() {
  local repo="$1" sid="${2:-vsess}" json
  json="$(jq -nc --arg c "$repo" --arg s "$sid" \
            '{cwd:$c, session_id:$s, hook_event_name:"Stop", stop_hook_active:false}')"
  printf '%s' "$json" | "$VERIFY"
}

@test "checks: discovers the project's Makefile test target" {
  command -v make >/dev/null 2>&1 || skip "make not installed"
  local repo="$WORK/v1"; mkdir -p "$repo"
  printf 'test:\n\t@true\n' > "$repo/Makefile"
  src='. "$1/lib/checks.sh";'
  run bash -c "$src"' tidy_test_command "$2"' bash "$ROOT" "$repo"
  [ "$output" = "make test" ]
}

@test "checks: discovers a root check.sh when there's no manifest (make-free)" {
  local repo="$WORK/cs"; mkdir -p "$repo"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$repo/check.sh"; chmod +x "$repo/check.sh"
  src='. "$1/lib/checks.sh";'
  run bash -c "$src"' tidy_test_command "$2"' bash "$ROOT" "$repo"
  [ "$output" = "./check.sh" ]
}

@test "checks: package.json placeholder test script is ignored" {
  local repo="$WORK/vp"; mkdir -p "$repo"
  printf '{"scripts":{"test":"echo \\"Error: no test specified\\" && exit 1"}}\n' > "$repo/package.json"
  src='. "$1/lib/checks.sh";'
  run bash -c "$src"' tidy_test_command "$2"' bash "$ROOT" "$repo"
  [ -z "$output" ]
}

@test "verify: blocks the stop and feeds the failure when tests fail (dirty tree)" {
  local repo="$WORK/v2"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"                                          # untracked → dirty
  export CLAUDE_TIDY_TEST_CMD='echo BOOM; exit 1'
  run run_verify "$repo" s1
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"BOOM"* ]]
  [[ "$output" == *"green"* ]]
}

@test "verify: silent when tests pass" {
  local repo="$WORK/v3"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"
  export CLAUDE_TIDY_TEST_CMD='true'
  run run_verify "$repo" s2
  [ -z "$output" ]
}

@test "verify: silent on a clean tree, with no test command, and when disabled" {
  local repo="$WORK/v4"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"; git -C "$repo" add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init    # clean tree
  CLAUDE_TIDY_TEST_CMD='exit 1' run run_verify "$repo" s3
  [ -z "$output" ]                                                    # clean → skip
  local bare="$WORK/v5"; mkdir -p "$bare"; git -C "$bare" init -q; : > "$bare/x.txt"
  run run_verify "$bare" s4                                           # dirty but no tests
  [ -z "$output" ]
  CLAUDE_TIDY_CHECKS=0 CLAUDE_TIDY_TEST_CMD='exit 1' run run_verify "$bare" s5
  [ -z "$output" ]                                                    # disabled
}

@test "verify: throttles re-runs when the tree is unchanged since the last green" {
  local repo="$WORK/vthr"; mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  : > "$repo/x.txt"                                    # dirty (untracked)
  local runs="$WORK/runs"
  export CLAUDE_TIDY_TEST_CMD="echo x >> $runs; true"
  run run_verify "$repo" thr                          # 1st: runs, green, stores fingerprint
  [ -z "$output" ]
  [ "$(wc -l < "$runs")" -eq 1 ]
  run run_verify "$repo" thr                          # unchanged tree → throttled, no re-run
  [ "$(wc -l < "$runs")" -eq 1 ]
  printf 'changed\n' > "$repo/x.txt"                  # tree changes → must run again
  run run_verify "$repo" thr
  [ "$(wc -l < "$runs")" -eq 2 ]
}

@test "verify: a slow test command times out (allows the stop, doesn't loop)" {
  command -v timeout >/dev/null 2>&1 || skip "timeout not installed"
  local repo="$WORK/vt"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"
  export CLAUDE_TIDY_TEST_CMD='sleep 5' CLAUDE_TIDY_VERIFY_TIMEOUT=1
  run run_verify "$repo" t1
  [[ "$output" == *"timed out"* ]]
  [[ "$output" != *"decision"* ]]          # not a block; no fix-loop
}

@test "verify: gives up (allows the stop) after the attempt cap, with a warning" {
  local repo="$WORK/v6"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"
  export CLAUDE_TIDY_TEST_CMD='exit 1' CLAUDE_TIDY_VERIFY_MAX=2
  run run_verify "$repo" cap; [[ "$output" == *block* ]]              # attempt 1
  run run_verify "$repo" cap; [[ "$output" == *block* ]]              # attempt 2
  run run_verify "$repo" cap
  [[ "$output" == *"systemMessage"* ]]                               # gave up
  [[ "$output" != *block* ]]
}
