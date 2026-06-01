#!/usr/bin/env bats
#
# Tests for the coverage ratchet (lib/coverage.sh): test detection, the touch-time
# "characterize before you change" nudge, the untested-changed lister, and the
# opt-in Stop gate. Faked via a temp repo + CLAUDE_TIDY_* overrides.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOUCH="$ROOT/bin/tidy-touch.sh"
  VERIFY="$ROOT/bin/tidy-verify.sh"
  WORK="$(mktemp -d)"
  export CLAUDE_TIDY_LOG_DIR="$WORK/log"
  SRC='. "$1/lib/tidy.sh"; . "$1/lib/coverage.sh";'
}
teardown() { rm -rf "$WORK"; }

run_touch() {
  local json
  json="$(jq -nc --arg p "$1" '{tool_name:"Write", tool_input:{file_path:$p}, session_id:"sesscov12"}')"
  printf '%s' "$json" | "$TOUCH" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "has_test_for: finds sibling, walked-up tests/, and __tests__ conventions" {
  mkdir -p "$WORK/pkg"
  printf 'package x\n' > "$WORK/pkg/foo.go"
  run bash -c "$SRC"' tidy_has_test_for "$2/pkg/foo.go"' bash "$ROOT" "$WORK"
  [ "$status" -eq 1 ]                                   # no test yet
  printf 'package x\n' > "$WORK/pkg/foo_test.go"        # sibling go test
  run bash -c "$SRC"' tidy_has_test_for "$2/pkg/foo.go"' bash "$ROOT" "$WORK"
  [ "$status" -eq 0 ]

  # shell file with a consolidated tests/ dir one level up
  mkdir -p "$WORK/app/lib" "$WORK/app/tests"
  printf 'echo hi\n' > "$WORK/app/lib/util.sh"
  run bash -c "$SRC"' tidy_has_test_for "$2/app/lib/util.sh"' bash "$ROOT" "$WORK"
  [ "$status" -eq 1 ]
  : > "$WORK/app/tests/util.bats"
  run bash -c "$SRC"' tidy_has_test_for "$2/app/lib/util.sh"' bash "$ROOT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "has_test_for: a non-test sibling (foo.md) under tests/ does NOT count (web)" {
  mkdir -p "$WORK/web/tests"
  printf 'export const x=1\n' > "$WORK/web/foo.ts"
  : > "$WORK/web/tests/foo.md"                          # not a test → must not count
  run bash -c "$SRC"' tidy_has_test_for "$2/web/foo.ts"' bash "$ROOT" "$WORK"
  [ "$status" -eq 1 ]
  : > "$WORK/web/tests/foo.test.ts"                     # real test → now counts
  run bash -c "$SRC"' tidy_has_test_for "$2/web/foo.ts"' bash "$ROOT" "$WORK"
  [ "$status" -eq 0 ]
}

@test "touch: an untested source file is nudged to characterize before changing" {
  printf 'package x\n' > "$WORK/widget.go"
  run run_touch "$WORK/widget.go"
  [[ "$output" == *"coverage: widget.go has no test"* ]]
  [[ "$output" == *"characterize it before changing"* ]]
}

@test "touch: silent once a test exists, and deduped per session" {
  printf 'package x\n' > "$WORK/mod.go"
  run run_touch "$WORK/mod.go"
  [[ "$output" == *"coverage: mod.go has no test"* ]]
  run run_touch "$WORK/mod.go"                          # same session → deduped
  [[ "$output" != *"coverage:"* ]]
  printf 'package x\n' > "$WORK/other.go"; : > "$WORK/other_test.go"
  run run_touch "$WORK/other.go"                        # has a test → silent
  [[ "$output" != *"coverage:"* ]]
}

@test "touch: test files and disabled mode produce no coverage nudge" {
  printf 'package x\n' > "$WORK/a_test.go"
  run run_touch "$WORK/a_test.go"
  [[ "$output" != *"coverage:"* ]]
  printf 'package x\n' > "$WORK/b.go"
  CLAUDE_TIDY_COVERAGE=0 run run_touch "$WORK/b.go"
  [[ "$output" != *"coverage:"* ]]
}

@test "untested_changed lists changed source files lacking a test" {
  local repo="$WORK/repo"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'package x\n' > "$repo/svc.go"                 # untracked, no test
  printf 'package x\n' > "$repo/done.go"; : > "$repo/done_test.go"
  run bash -c "$SRC"' tidy_untested_changed "$2"' bash "$ROOT" "$repo"
  [[ "$output" == *"svc.go"* ]]
  [[ "$output" != *"done.go"* ]]                        # has a test → excluded
}

@test "verify gate: opt-in ratchet blocks until changed source is characterized" {
  local repo="$WORK/vrepo"; mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf 'package x\n' > "$repo/handler.go"             # untested, dirty
  json="$(jq -nc --arg c "$repo" '{cwd:$c, session_id:"s1"}')"
  CLAUDE_TIDY_COVERAGE_RATCHET=1 run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$VERIFY"
  [[ "$output" == *'"decision": "block"'* ]] || [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"handler.go"* ]]
}

@test "verify gate: gives up (allows) after VERIFY_MAX blocks — never loops forever" {
  local repo="$WORK/vrepo3"; mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf 'package x\n' > "$repo/h.go"                   # untested, dirty
  json="$(jq -nc --arg c "$repo" '{cwd:$c, session_id:"sgate"}')"
  export CLAUDE_TIDY_COVERAGE_RATCHET=1 CLAUDE_TIDY_VERIFY_MAX=2
  run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$VERIFY"   # block #1
  [[ "$output" == *"block"* ]]
  run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$VERIFY"   # block #2
  [[ "$output" == *"block"* ]]
  run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$VERIFY"   # gave up → warn, allow
  [[ "$output" == *"systemMessage"* ]]
  [[ "$output" != *"decision"* ]]
}

@test "verify gate: off by default (no block when ratchet unset)" {
  local repo="$WORK/vrepo2"; mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf 'package x\n' > "$repo/handler.go"
  json="$(jq -nc --arg c "$repo" '{cwd:$c, session_id:"s1"}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$VERIFY"
  [[ "$output" != *"Coverage ratchet"* ]]
}
