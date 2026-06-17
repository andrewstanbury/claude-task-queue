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

# ---- debt surface (moved here from SessionStart; post-work, throttled) ------

@test "stop: recommends a prune when debt crosses the threshold (dirty, no tests)" {
  local repo="$WORK/d1"; mkdir -p "$repo"; git -C "$repo" init -q
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$repo/a.go"; seq 1 12 > "$repo/b.go"; seq 1 12 > "$repo/c.go"
  run run_verify "$repo" d1
  [[ "$output" == *"Debt threshold crossed"* ]]
  [[ "$output" == *"prune pass"* ]]
  [[ "$output" == *"systemMessage"* ]]                               # non-blocking
}

@test "stop: the prune nudge is throttled to once per episode" {
  local repo="$WORK/d2"; mkdir -p "$repo"; git -C "$repo" init -q
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$repo/a.go"; seq 1 12 > "$repo/b.go"; seq 1 12 > "$repo/c.go"
  run run_verify "$repo" d2; [[ "$output" == *"Debt threshold crossed"* ]]   # 1st: fires
  run run_verify "$repo" d2; [ -z "$output" ]                                 # 2nd: quiet
}

@test "stop: quiet when debt is below the prune threshold" {
  local repo="$WORK/d3"; mkdir -p "$repo"; git -C "$repo" init -q
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$repo/a.go"                          # only 1 over budget (threshold 3)
  run run_verify "$repo" d3
  [ -z "$output" ]
}

@test "stop: over-budget TEST files don't trip the prune nudge (exempt)" {
  local repo="$WORK/d4"; mkdir -p "$repo"; git -C "$repo" init -q
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$repo/a_test.go"; seq 1 12 > "$repo/b_test.go"; seq 1 12 > "$repo/c_test.go"
  run run_verify "$repo" d4
  [ -z "$output" ]
}

# ---- regression gate (untested scar-tissue hotspots) ------------------------

# A repo whose scar.sh is a scar-tissue hotspot (repeatedly FIXED) with NO test,
# plus a healthy.sh that only ever saw feature work. Leaves the tree CLEAN.
scar_repo() {
  local repo="$1" i; mkdir -p "$repo"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  printf '#!/usr/bin/env bash\necho a\n' > "$repo/scar.sh"
  git -C "$repo" add -A; git -C "$repo" commit -q -m "feat: add scar"
  printf 'echo b\n' >> "$repo/scar.sh"; git -C "$repo" add -A; git -C "$repo" commit -q -m "fix: scar bug"
  printf 'echo c\n' >> "$repo/scar.sh"; git -C "$repo" add -A; git -C "$repo" commit -q -m "fix: scar regression"
  for i in 1 2 3; do printf 'v%s\n' "$i" > "$repo/healthy.sh"; git -C "$repo" add -A; git -C "$repo" commit -q -m "feat: extend $i"; done
}

@test "regression gate: blocks a touched file that is an untested scar-tissue hotspot" {
  local repo="$WORK/rg1"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"                 # touch the hotspot again (dirty)
  run run_verify "$repo" rg1
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"REPEATEDLY FIXED"* ]]
  [[ "$output" == *"scar.sh"* ]]
}

@test "regression gate: silent on a touched file that is NOT a hotspot" {
  local repo="$WORK/rg2"; scar_repo "$repo"
  printf 'v4\n' > "$repo/healthy.sh"                   # healthy file → no rework history
  run run_verify "$repo" rg2
  [ -z "$output" ]
}

@test "regression gate: goes quiet once the hotspot has a test (loop closed)" {
  local repo="$WORK/rg3"; scar_repo "$repo"
  printf '#!/usr/bin/env bats\n@test x { run true; }\n' > "$repo/scar.bats"
  git -C "$repo" add -A; git -C "$repo" commit -q -m "test: scar"
  printf 'echo e\n' >> "$repo/scar.sh"                 # edit the now-tested hotspot
  run run_verify "$repo" rg3
  [ -z "$output" ]
}

@test "regression gate: bounded — gives up after the cap with a soft note" {
  local repo="$WORK/rg4"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"
  export CLAUDE_TIDY_VERIFY_MAX=2
  run run_verify "$repo" rgc; [[ "$output" == *block* ]]      # attempt 1
  run run_verify "$repo" rgc; [[ "$output" == *block* ]]      # attempt 2
  run run_verify "$repo" rgc
  [[ "$output" == *"systemMessage"* ]]                        # gave up
  [[ "$output" == *"Regression gate"* ]]
  [[ "$output" != *block* ]]
}

@test "regression gate: disabled via CLAUDE_TIDY_REGRESSION_GATE=0" {
  local repo="$WORK/rg5"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"
  CLAUDE_TIDY_REGRESSION_GATE=0 run run_verify "$repo" rg5
  [ -z "$output" ]
}

@test "regression gate: stands down when the broad coverage ratchet is forcing" {
  local repo="$WORK/rg6"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"
  CLAUDE_TIDY_COVERAGE_RATCHET=1 run run_verify "$repo" rg6
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"Coverage ratchet"* ]]               # the ratchet's message…
  [[ "$output" != *"REPEATEDLY FIXED"* ]]               # …not the regression gate's
}

# ---- diagnose discipline in the fail-block ----------------------------------

@test "verify: the fail-block carries the diagnose loop (hypotheses, tagged logs, regression test)" {
  local repo="$WORK/vdiag"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"
  export CLAUDE_TIDY_TEST_CMD='echo BOOM; exit 1'
  run run_verify "$repo" sd
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"hypotheses"* ]]                    # ranked falsifiable hypotheses
  [[ "$output" == *"DEBUG-"* ]]                        # tagged instrumentation for one-grep cleanup
  [[ "$output" == *"regression test"* ]]               # pin the bug (composes with the regression gate)
}

# ---- import-cycle check (clean architecture, detect-and-run madge) -----------

# A fake `madge` on PATH that prints the given --circular --json output.
madge_stub() {
  mkdir -p "$WORK/fakebin"
  printf '%s' "$1" > "$WORK/madge-out.json"
  printf '#!/usr/bin/env bash\ncat %q\n' "$WORK/madge-out.json" > "$WORK/fakebin/madge"
  chmod +x "$WORK/fakebin/madge"
}
run_verify_madge() {
  local repo="$1" sid="${2:-cyc}" json
  json="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c, session_id:$s}')"
  printf '%s' "$json" | PATH="$WORK/fakebin:$PATH" CLAUDE_TIDY_TEST_CMD='true' "$VERIFY"
}
cyc_repo() {
  mkdir -p "$1/src"; git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

@test "cycle check: surfaces an import cycle involving a changed file (post-green)" {
  local repo="$WORK/cy1"; cyc_repo "$repo"
  printf 'import "./b"\n' > "$repo/src/a.ts"                 # dirty (untracked)
  madge_stub '[["src/a.ts","src/b.ts"]]'
  run run_verify_madge "$repo" c1
  [[ "$output" == *"Circular dependency"* ]]
  [[ "$output" == *"src/a.ts → src/b.ts → src/a.ts"* ]]
}

@test "cycle check: deduped — the same cycle set is not re-surfaced" {
  local repo="$WORK/cy2"; cyc_repo "$repo"
  printf 'x\n' > "$repo/src/a.ts"
  madge_stub '[["src/a.ts","src/b.ts"]]'
  run run_verify_madge "$repo" c2; [[ "$output" == *"Circular"* ]]
  run run_verify_madge "$repo" c2; [ -z "$output" ]         # unchanged set → quiet
}

@test "cycle check: only cycles touching a changed file are surfaced" {
  local repo="$WORK/cy3"; cyc_repo "$repo"
  printf 'x\n' > "$repo/src/a.ts"                           # only a.ts changed
  madge_stub '[["src/x.ts","src/y.ts"]]'                    # cycle is unrelated
  run run_verify_madge "$repo" c3
  [ -z "$output" ]
}

@test "cycle check: silent without madge, and when disabled" {
  local repo="$WORK/cy4"; cyc_repo "$repo"
  printf 'import "./b"\n' > "$repo/src/a.ts"
  run run_verify "$repo" c4                                  # no madge on PATH
  [ -z "$output" ]
  madge_stub '[["src/a.ts","src/b.ts"]]'
  json="$(jq -nc --arg c "$repo" --arg s c5 '{cwd:$c, session_id:$s}')"
  run bash -c 'printf "%s" "$1" | PATH="$2:$PATH" CLAUDE_TIDY_TEST_CMD=true CLAUDE_TIDY_CYCLE_CHECK=0 "$3"' _ "$json" "$WORK/fakebin" "$VERIFY"
  [ -z "$output" ]
}

# ---- quality floor (the project's own typecheck/a11y/dep-rule gates) ---------

@test "quality floor: discovers the project's typecheck/a11y/arch scripts (not test/lint)" {
  local repo="$WORK/q0"; mkdir -p "$repo"
  printf '{"scripts":{"test":"jest","typecheck":"tsc","a11y":"axe","lint":"eslint","arch":"depcruise"}}\n' > "$repo/package.json"
  src='. "$1/lib/checks.sh";'
  run bash -c "$src"' tidy_quality_commands "$2"' bash "$ROOT" "$repo"
  [[ "$output" == *"typecheck"* ]]
  [[ "$output" == *"a11y/perf"* ]]
  [[ "$output" == *"architecture"* ]]
  [[ "$output" != *"jest"* ]]                 # the test script is the floor, not a gate
  [[ "$output" != *"eslint"* ]]               # project-wide lint stays at edit time
}

@test "quality floor: blocks on a failing gate, before the tests even run" {
  local repo="$WORK/q1"; mkdir -p "$repo"; git -C "$repo" init -q; : > "$repo/x.txt"
  export CLAUDE_TIDY_QUALITY_CMD='echo TYPE-ERR; exit 1' CLAUDE_TIDY_TEST_CMD='echo SHOULD-NOT-RUN'
  run run_verify "$repo" q1
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"quality gate"* ]]
  [[ "$output" == *"TYPE-ERR"* ]]
  [[ "$output" != *"SHOULD-NOT-RUN"* ]]        # quality blocked before the test command ran
}

@test "quality floor: silent when the gate passes (tests then run)" {
  local repo="$WORK/q2"; mkdir -p "$repo"; git -C "$repo" init -q; : > "$repo/x.txt"
  export CLAUDE_TIDY_QUALITY_CMD='true' CLAUDE_TIDY_TEST_CMD='true'
  run run_verify "$repo" q2
  [ -z "$output" ]
}

@test "quality floor: disabled via CLAUDE_TIDY_QUALITY_FLOOR=0" {
  local repo="$WORK/q3"; mkdir -p "$repo"; git -C "$repo" init -q; : > "$repo/x.txt"
  export CLAUDE_TIDY_QUALITY_CMD='exit 1' CLAUDE_TIDY_QUALITY_FLOOR=0 CLAUDE_TIDY_TEST_CMD='true'
  run run_verify "$repo" q3
  [ -z "$output" ]
}

@test "quality floor: bounded — gives up after the cap with a soft note" {
  local repo="$WORK/q4"; mkdir -p "$repo"; git -C "$repo" init -q; : > "$repo/x.txt"
  export CLAUDE_TIDY_QUALITY_CMD='exit 1' CLAUDE_TIDY_VERIFY_MAX=2
  run run_verify "$repo" q4; [[ "$output" == *block* ]]
  run run_verify "$repo" q4; [[ "$output" == *block* ]]
  run run_verify "$repo" q4
  [[ "$output" == *"systemMessage"* ]]
  [[ "$output" == *"Quality gate"* ]]
  [[ "$output" != *block* ]]
}
