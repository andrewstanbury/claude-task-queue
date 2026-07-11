#!/usr/bin/env bats
#
# Tests for the Stop hook (bin/tidy-verify.sh). The end-of-turn verification floor
# (run the project's tests, block until green) was REMOVED — tests are run manually.
# What remains and is covered here: the non-blocking post-work debt/cycle surface and
# the two OPT-IN, off-by-default test-existence gates (coverage ratchet, regression gate).

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

@test "stop: silent on a clean tree, on a dirty tree with nothing to surface, and when disabled" {
  local repo="$WORK/v4"; mkdir -p "$repo"; git -C "$repo" init -q
  : > "$repo/x.txt"; git -C "$repo" add -A
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init    # clean tree
  run run_verify "$repo" s3
  [ -z "$output" ]                                                    # clean → skip
  local bare="$WORK/v5"; mkdir -p "$bare"; git -C "$bare" init -q; : > "$bare/x.txt"
  run run_verify "$bare" s4                                           # dirty, nothing to surface
  [ -z "$output" ]
  CLAUDE_TIDY_CHECKS=0 run run_verify "$bare" s5
  [ -z "$output" ]                                                    # whole hook disabled
}

# ---- debt surface (post-work, non-blocking, throttled) ----------------------

@test "stop: recommends a prune when debt crosses the threshold (dirty tree)" {
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

# ---- regression gate (untested scar-tissue hotspots, OPT-IN) ----------------

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

@test "regression gate: blocks a touched untested scar-tissue hotspot when opted in" {
  local repo="$WORK/rg1"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"                 # touch the hotspot again (dirty)
  export CLAUDE_TIDY_REGRESSION_GATE=1                 # opt-in (off by default)
  run run_verify "$repo" rg1
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"REPEATEDLY FIXED"* ]]
  [[ "$output" == *"scar.sh"* ]]
}

@test "regression gate: silent on a touched file that is NOT a hotspot" {
  local repo="$WORK/rg2"; scar_repo "$repo"
  printf 'v4\n' > "$repo/healthy.sh"                   # healthy file → no rework history
  export CLAUDE_TIDY_REGRESSION_GATE=1
  run run_verify "$repo" rg2
  [ -z "$output" ]
}

@test "regression gate: goes quiet once the hotspot has a test (loop closed)" {
  local repo="$WORK/rg3"; scar_repo "$repo"
  printf '#!/usr/bin/env bats\n@test x { run true; }\n' > "$repo/scar.bats"
  git -C "$repo" add -A; git -C "$repo" commit -q -m "test: scar"
  printf 'echo e\n' >> "$repo/scar.sh"                 # edit the now-tested hotspot
  export CLAUDE_TIDY_REGRESSION_GATE=1
  run run_verify "$repo" rg3
  [ -z "$output" ]
}

@test "regression gate: bounded — gives up after the cap with a soft note" {
  local repo="$WORK/rg4"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"
  export CLAUDE_TIDY_REGRESSION_GATE=1 CLAUDE_TIDY_VERIFY_MAX=2
  run run_verify "$repo" rgc; [[ "$output" == *block* ]]      # attempt 1
  run run_verify "$repo" rgc; [[ "$output" == *block* ]]      # attempt 2
  run run_verify "$repo" rgc
  [[ "$output" == *"systemMessage"* ]]                        # gave up
  [[ "$output" == *"Regression gate"* ]]
  [[ "$output" != *block* ]]
}

@test "regression gate: OFF by default (tests are opt-in — no block unless enabled)" {
  local repo="$WORK/rg5"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"                 # touch the untested hotspot
  run run_verify "$repo" rg5                           # no CLAUDE_TIDY_REGRESSION_GATE → off
  [ -z "$output" ]
}

@test "regression gate: stands down when the broad coverage ratchet is forcing" {
  local repo="$WORK/rg6"; scar_repo "$repo"
  printf 'echo d\n' >> "$repo/scar.sh"
  CLAUDE_TIDY_REGRESSION_GATE=1 CLAUDE_TIDY_COVERAGE_RATCHET=1 run run_verify "$repo" rg6
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"Coverage ratchet"* ]]               # the ratchet's message…
  [[ "$output" != *"REPEATEDLY FIXED"* ]]               # …not the regression gate's
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
  printf '%s' "$json" | PATH="$WORK/fakebin:$PATH" "$VERIFY"
}
cyc_repo() {
  mkdir -p "$1/src"; git -C "$1" init -q
  git -C "$1" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
}

@test "cycle check: surfaces an import cycle involving a changed file" {
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
  run bash -c 'printf "%s" "$1" | PATH="$2:$PATH" CLAUDE_TIDY_CYCLE_CHECK=0 "$3"' _ "$json" "$WORK/fakebin" "$VERIFY"
  [ -z "$output" ]
}
