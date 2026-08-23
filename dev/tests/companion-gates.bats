#!/usr/bin/env bats
#
# THE DEV GATES - the checks that verify the plugin: doc-lint, mutation gate, size/command lint, stale, trace, budgets.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper


@test "docs/flows index lists every shipped command + the count matches (contract can't silently drift)" {
  # The flows index is the R54 contract pillar a regen reproduces; if a command is added without an
  # entry, a regen reproduces the WRONG surface. This is the guard that caught the 8-vs-10 drift.
  local repo idx; repo="$(cd "$ROOT/../.." && pwd)"; idx="$repo/docs/flows/README.md"
  [ -f "$idx" ]
  local f name n=0
  for f in "$ROOT/commands"/*.md; do
    name="$(basename "$f" .md)"
    grep -q "companion:$name" "$idx"       # every shipped command must appear in the flows index
    n=$((n+1))
  done
  grep -q "Slash commands ($n)" "$idx"     # and the stated count matches reality
}

@test "docs/flows: every [E] flow test resolves to a real @test (anti-drift gate — R61/R62)" {
  # THE gate: a flow page's `- [E] `<name>`` Tests line names a backtick substring of a real bats
  # @test title — the machine-readable link from a documented user experience to the test that proves
  # it. If that test is renamed/deleted, the flow page silently lies, and a golden/happy-path test
  # built from the contract LATER would chase a ghost (the exact drift to avoid). This FAILS the build
  # the moment a referenced test stops resolving. Honest gaps ([S] judgment lines, 👁) are skipped,
  # not failed — coverage stays truthful. (bats proves the test PASSES; this proves it EXISTS + is
  # wired to the flow.) Uses the shared _ux_* helpers — the same code the guard-test runs.
  local repo titles; repo="$(cd "$ROOT/../.." && pwd)"
  [ -d "$repo/docs/flows" ]; titles="$(grep -h '^@test' "$DEV/tests"/*.bats)"
  local f line frag s; local -a bad=()
  for f in "$repo"/docs/flows/*.md; do [ -f "$f" ] || continue
    while IFS= read -r line; do
      frag="$(_ux_flow_check "$line")"; [ -n "$frag" ] || continue
      s="${frag#\`}"; s="${s%\`}"; [ -n "$s" ] || continue
      _ux_check_resolves "$s" "$titles" || bad+=("$(basename "$f"): $s")
    done < "$f"
  done
  if [ "${#bad[@]}" -gt 0 ]; then printf 'flow [E] test resolves to no @test:\n'; printf '  - %s\n' "${bad[@]}"; false; fi
}

@test "docs/flows anti-drift gate FAILS on a phantom test + PASSES a real one — via the real matcher (R61/R62)" {
  # Guards the guard: a gate that can't fail is theater. This drives fixture lines through the SAME
  # _ux_flow_check + _ux_check_resolves the real gate uses (not a re-implemented proxy), proving the
  # matcher rejects a phantom AND accepts a real name — so it can't be silently stuck always-pass or
  # always-fail. Also covers the silent-skip edge: a leading-indented Tests line must still be gated.
  local titles; titles="$(grep -h '^@test' "$DEV/tests"/*.bats)"
  local frag s; _check() { local r="$1"                # returns 0 iff the line's [E] test resolves
    frag="$(_ux_flow_check "$r")"; [ -n "$frag" ] || return 1
    s="${frag#\`}"; s="${s%\`}"; _ux_check_resolves "$s" "$titles"; }
  ! _check '- [E] `this test absolutely does not exist xyzzy`'   # phantom → unresolved
  _check '- [E] `tq: no session id errors cleanly`'               # real → resolves (not always-fail)
  ! _check '   - [E] `another phantom qqq nonexistent`'          # indented phantom still reaches matcher
  ! _check '- [S] `tq: no session id errors cleanly`'             # an [S] line is NOT gated (skipped)
}

@test "check.sh: a red verdict NAMES the section it went red in, and never double-counts (R89)" {
  # Sources the REAL definitions out of check.sh rather than restating them — a re-implementation
  # would pass while the gate itself regressed, which is the failure mode this suite already
  # rejects elsewhere. Running the whole gate here is not an option: check.sh runs bats.
  run bash -c '
    cd "$1" || exit 1
    fail=0
    eval "$(sed -n "/^CUR=\"(startup)\"/,/^}/p" check.sh)"
    section "Alpha" >/dev/null; failsec; failsec
    section "Beta"  >/dev/null; failsec
    section "Gamma" >/dev/null
    printf "fail=%s sections=%s\n" "$fail" "$FAILED_SECTIONS"
  ' _ "$BATS_TEST_DIRNAME/../.."
  [ "$status" -eq 0 ]
  [[ "$output" == *"fail=1"* ]]
  [[ "$output" == *"sections=Alpha;Beta"* ]]   # Alpha once despite two failures; Gamma clean, absent
}

@test "command-lint: the COMMAND CONTRACT checks can now fail — they could not while inline (R75)" {
  # These checks lived inline in check.sh, where the suite could not reach them, so their declared
  # mutations had nothing that could redden. Extraction (2026-08-03, size guard) is what makes them
  # testable; this is the test that makes the extraction worth anything.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/commands" "$d/plugins/companion/mcp-server" "$d/dev"
  cp dev/doc-lint.sh dev/command-lint.sh "$d/dev/"
  # the portability floor derives tool names from the MCP server and refuses to pass VACUOUSLY when
  # it can derive none, so the fixture has to look like a repo — not only like the check under test
  printf '  "board",\n' > "$d/plugins/companion/mcp-server/index.js"
  _cl() { run bash -c 'cd "$1" && dev/command-lint.sh' _ "$d"; }

  # a well-formed command passes
  printf -- '---\ndescription: Do the thing\n---\n\nBody calls `board`.\n' \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -eq 0 ]

  # an over-long description is per-session injection and must FAIL
  printf -- '---\ndescription: %s\n---\n\nBody calls `board`.\n' "$(printf 'x%.0s' $(seq 1 200))" \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -ne 0 ]; [[ "$output" == *"> 140B"* ]]

  # a body reading $ARGUMENTS with no argument-hint leaves the parameter invisible where it is typed
  printf -- '---\ndescription: Do the thing\n---\n\nUse $ARGUMENTS with `board`.\n' \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -ne 0 ]; [[ "$output" == *"argument-hint"* ]]
}

@test "command-lint: a mode autopilot.sh IMPLEMENTS but no document mentions is caught (doc vs CODE)" {
  # The live 2026-08-15 miss: `burndown on|off|status` was implemented and the description, the
  # argument-hint and the body ALL omitted it — so every doc-vs-doc check agreed, and agreed about
  # nothing. Three consistent documents are not evidence when the mode is absent from all three.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/commands" "$d/plugins/companion/bin" "$d/plugins/companion/mcp-server" "$d/dev"
  cp dev/doc-lint.sh dev/command-lint.sh "$d/dev/"
  printf '  "board",\n' > "$d/plugins/companion/mcp-server/index.js"
  _cl() { run bash -c 'cd "$1" && dev/command-lint.sh' _ "$d"; }
  # a stand-in autopilot.sh whose top-level case implements one shared action and two modes
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in' \
    '  status) echo s ;;' '  ship) echo x ;;' '  burndown) echo y ;;' 'esac' \
    > "$d/plugins/companion/bin/autopilot.sh"

  # documents BOTH modes -> clean
  printf -- '---\ndescription: on|off|status · ship/burndown on|off\n---\n\nModes: ship, burndown via `board`.\n' \
    > "$d/plugins/companion/commands/autopilot.md"
  _cl; [ "$status" -eq 0 ]

  # drops one mode from every document at once -> exactly the drift that shipped, now caught
  printf -- '---\ndescription: on|off|status · ship on|off\n---\n\nModes: ship via `board`.\n' \
    > "$d/plugins/companion/commands/autopilot.md"
  _cl; [ "$status" -ne 0 ]
  [[ "$output" == *"burndown"* ]]
  [[ "$output" != *"never mentions the \`ship\`"* ]]   # the documented mode is not flagged
  [[ "$output" != *"never mentions the \`status\`"* ]] # shared actions are not modes
}

# ── doc-lint (R78) ─────────────────────────────────────────────────────────────────────────────
# These two checks used to live inline in check.sh, which the suite cannot invoke without recursion
# (check.sh runs bats) — so they had no behavioural case and no mutation, a gap R78 had to record
# rather than close. Extracted to bin/doc-lint.sh precisely so these cases can exist.

@test "doc-lint frontmatter: accepts shapes the HOST accepts (no false positives) (R78)" {
  # An earlier whole-block whitelist rejected all three of these, which would have broken valid
  # user commands — worse than having no check at all.
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: "plain"\nallowed-tools:\n  - Bash\n  - Read\n---\nbody\n' > "$d/a.md"
  printf -- '---\ndescription: "plain"\nallowed-tools: [Bash, Read]\n---\nbody\n' > "$d/b.md"
  printf -- "---\ndescription: 'a: b'\nmodel: inherit\n---\nbody\n" > "$d/c.md"
  # UNQUOTED but perfectly valid — without this every fixture was quoted, so a doc-lint that
  # rejected all unquoted values passed all three cases AND left check.sh green (every real
  # command already quotes). The "must not break valid commands" contract had no coverage.
  printf -- '---\ndescription: walk the parked backlog one at a time\n---\nbody\n' > "$d/d.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/a.md" "$d/b.md" "$d/c.md" "$d/d.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doc-lint frontmatter: rejects shapes the HOST throws on (R75/R78)" {
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: [target] — leading indicator\n---\nbody\n' > "$d/ind.md"
  printf -- '---\ndescription: wire this: the thing\n---\nbody\n'          > "$d/colon.md"
  printf -- '---\ndescription: "never closed\n---\nbody\n'                 > "$d/quote.md"
  printf -- '---\ndescription: "one"\ndescription: "two"\n---\nbody\n'     > "$d/dup.md"
  for c in ind colon quote dup; do
    run "$DEV/doc-lint.sh" frontmatter "$d/$c.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
  done
  run "$DEV/doc-lint.sh" frontmatter "$d/ind.md"
  [[ "$output" == *"YAML indicator"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/quote.md"
  [[ "$output" == *"never closes"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/dup.md"
  [[ "$output" == *"duplicate"* ]]
}

@test "doc-lint ledger: a hard measurement needs evidence; a rhetorical figure does not (R78)" {
  local d; d="$(_tmpd)"
  printf '| **R1** | 🔓 | Grew by 512B and blocked 25/25 turns. | 2026-01-01, no evidence. |\n' > "$d/bad.md"
  run "$DEV/doc-lint.sh" ledger "$d/bad.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 states a measurement with no evidence"* ]]

  printf '| **R2** | 🔓 | Grew by 512B, measured with check.sh. | 2026-01-01. |\n' > "$d/good.md"
  run "$DEV/doc-lint.sh" ledger "$d/good.md"
  [ "$status" -eq 0 ]

  # a rhetorical estimate is a judgement, not a measurement — it must NOT trip the rule (this
  # false-positived on R40's "~90% of the value" during calibration)
  printf '| **R3** | 🔓 | Roughly ~90%% of the value, and version 3.22.0. | 2026-01-01. |\n' > "$d/rhet.md"
  run "$DEV/doc-lint.sh" ledger "$d/rhet.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check.sh actually INVOKES doc-lint for both subcommands (R78 wiring guard)" {
  # Extracting the logic made it testable but created a new untested failure mode: the CALL. With
  # both invocations stubbed out the whole suite stayed green while the gate silently checked
  # nothing. bats cannot run check.sh (check.sh runs bats), so this is a structural guard — the
  # same shape as the R56·P3 guard over command prose.
  # The frontmatter caller MOVED to dev/command-lint.sh with the 2026-08-03 extraction, so this
  # guard follows it. Leaving it pointed at check.sh is the third extraction trap in LESSONS — a
  # moved failure mode — and it fired here: the guard went red for the right reason.
  run grep -c 'doc-lint\.sh" frontmatter' "$DEV/command-lint.sh"
  [ "$output" -ge 1 ]
  # Moved with the byte-cap section into dev/token-budget.sh 2026-08-16 — the guard FOLLOWS the
  # call, which is the extraction trap LESSONS records and this very comment predicted.
  run grep -c 'doc-lint\.sh ledger' "$DEV/token-budget.sh"
  [ "$output" -ge 1 ]
}

@test "doc-lint: CRLF and BOM do not silently disable the frontmatter lint (R78)" {
  # The reader compared line 1 to "---"; a CRLF file made it "---\r", so the block came back EMPTY
  # and EVERY frontmatter check passed vacuously — fail-open on all of them at once, and the exact
  # route by which the 3.21.0 blocker (an unquoted leading `[`) gets back in.
  local d; d="$(_tmpd)"
  printf -- '---\r\ndescription: "never closed\r\n---\r\nbody\r\n' > "$d/crlf.md"
  printf -- '\xef\xbb\xbf---\ndescription: [bad]\n---\nbody\n'     > "$d/bom.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/crlf.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"never closes"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/bom.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"YAML indicator"* ]]
  # and the shared reader really returns the block for both
  run "$DEV/doc-lint.sh" fm "$d/crlf.md"
  [[ "$output" == *"description"* ]]
}

@test "doc-lint: folded and literal block scalars are valid YAML, not indicators (R78)" {
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: >\n  folded and valid\n---\nb\n' > "$d/f.md"
  printf -- '---\ndescription: |\n  literal and valid\n---\nb\n' > "$d/l.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/f.md" "$d/l.md"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf -- '---\ndescription: [still bad]\n---\nb\n' > "$d/i.md"   # real indicators still caught
  run "$DEV/doc-lint.sh" frontmatter "$d/i.md"
  [ "$status" -eq 1 ]
}

@test "doc-lint ledger: the ~ exemption works on MULTI-digit numbers (R78)" {
  # `(^|[^~])[0-9]` could begin matching one digit inside the number, so ~371B tripped while ~9B
  # did not — the exemption only worked for single digits.
  local d; d="$(_tmpd)"
  printf '| **R9** | 🔓 | Grew by ~371B and ≈1200 tokens. | x. |\n' > "$d/approx.md"
  run "$DEV/doc-lint.sh" ledger "$d/approx.md"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '| **R9** | 🔓 | Grew by 371B. | x. |\n' > "$d/hard.md"    # a hard figure still needs evidence
  run "$DEV/doc-lint.sh" ledger "$d/hard.md"
  [ "$status" -eq 1 ]
}
@test "mutate-gate: a FAILED RESTORE is reported and fails the run, never reported as caught" {
  # Live 2026-08-16: `mv "$tgt.mutbak" "$tgt"` was fire-and-forget, it failed, and the gate printed
  # "ok caught" and exited 0 while leaving lib/task-store.sh MUTATED — a tree in which
  # companion_open_tasks returned nothing, i.e. the crash-resume path dead, with every gate green.
  _mg_fixture
  run bash -c 'cd "$1" && bash dev/mutate-gate.sh' _ "$MG"
  [ "$status" -eq 0 ]; [[ "$output" == *"all 1 mutations caught"* ]]
  run grep -c MARKER_A "$MG/plugins/companion/bin/t.sh"
  [ "$output" -eq 1 ]                                  # healthy run puts the file back

  # Sabotage the put-back exactly as reality did: the backup is gone when the mv runs.
  # NO `sed -i` — BSD sed (the macOS lane) requires an argument to -i and reads the script as the
  # backup suffix, so the edit silently does not apply, the gate restores fine, and this test passes
  # for the wrong reason. It reddened macOS CI on 3.87.0 doing exactly that. sed-to-a-temp is the
  # portable form, and it is the FOURTH time this repo has paid for the difference.
  run bash -c 'cd "$1" && sed "s@  mv \"\$tgt.mutbak\" \"\$tgt\" 2>/dev/null@  rm -f \"\$tgt.mutbak\"; mv \"\$tgt.mutbak\" \"\$tgt\" 2>/dev/null@" dev/mutate-gate.sh > dev/mg.tmp && mv dev/mg.tmp dev/mutate-gate.sh' _ "$MG"
  [ "$status" -eq 0 ]
  run grep -c 'rm -f "$tgt.mutbak"; mv' "$MG/dev/mutate-gate.sh"
  [ "$output" -ge 1 ]                                  # the sabotage really applied
  run bash -c 'cd "$1" && bash dev/mutate-gate.sh' _ "$MG"
  [ "$status" -ne 0 ]                                  # the run FAILS...
  [[ "$output" == *"RESTORE FAILED"* ]]                # ...saying so, in those words
  [[ "$output" == *"git checkout --"* ]]               # ...and naming the recovery
  rmdir "$MG_LOCK" 2>/dev/null || true
}

@test "mutate-gate: a STALE lock is reclaimed, a LIVE one is still refused" {
  # A run killed with SIGKILL runs no trap, so the bare-directory lock outlived it and blocked every
  # later run FOREVER while reporting "another run holds" with nothing running. Hit twice in a day.
  _mg_fixture
  mkdir -p "$MG_LOCK"; printf '999999\n' > "$MG_LOCK/pid"    # an owner that cannot be alive
  run bash -c 'cd "$1" && bash dev/mutate-gate.sh' _ "$MG"
  [ "$status" -eq 0 ]; [[ "$output" == *"reclaiming a STALE lock"* ]]

  # a LIVE owner is the case that really corrupts backups, and must still be refused
  sleep 60 & local live=$!
  mkdir -p "$MG_LOCK"; printf '%s\n' "$live" > "$MG_LOCK/pid"
  run bash -c 'cd "$1" && bash dev/mutate-gate.sh' _ "$MG"
  kill "$live" 2>/dev/null || true
  [ "$status" -eq 2 ]; [[ "$output" == *"holds"* ]]
  rm -f "$MG_LOCK/pid"; rmdir "$MG_LOCK" 2>/dev/null || true
}

@test "size-lint: over the cap FAILS, saturated WARNS but passes, and the gate can be exercised at all" {
  # Extracted from check.sh 2026-08-16 for the R78 reason: inline, the suite could not invoke it
  # without recursing, so the one gate that decides when to decompose had no test of its own.
  local d; d="$(_tmpd)"
  printf 'x\n%.0s' $(seq 1 310) > "$d/over.sh"       # 310 lines
  printf 'x\n%.0s' $(seq 1 285) > "$d/near.sh"       # saturated but legal
  printf 'x\n%.0s' $(seq 1 100) > "$d/small.sh"
  run bash "$DEV/size-lint.sh" "$d/over.sh"
  [ "$status" -eq 1 ]; [[ "$output" == *"FAIL"* ]]; [[ "$output" == *"310 > 300"* ]]
  # SATURATION IS NOT A FAILURE: blocking otherwise-fine work on "this file is largish" is how a
  # gate gets switched off, and a disabled gate protects nothing.
  run bash "$DEV/size-lint.sh" "$d/near.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *"WARN"* ]]; [[ "$output" == *"285/300"* ]]
  run bash "$DEV/size-lint.sh" "$d/small.sh"
  [ "$status" -eq 0 ]; [ -z "$output" ]              # quiet when there is nothing to say
  # thresholds are tunable, measuring them is not
  run env CHECK_SIZE_WARN=50 bash "$DEV/size-lint.sh" "$d/small.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *"WARN"* ]]
}

@test "doc-lint retired: a claim naming a SURVIVING file fails; history and true retirements pass" {
  # From the 2026-08-16 audit. A retirement claim asserts an ABSENCE, so nothing fails when the
  # thing comes back — one of the two found had been false for four days.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/bin" "$d/dev"
  cp dev/doc-lint.sh "$d/dev/"
  : > "$d/plugins/companion/bin/alive.sh"          # a file that EXISTS
  local _r; _r() { run bash -c 'cd "$1" && dev/doc-lint.sh retired "$2"' _ "$d" "$d/req.yaml"; }

  # present-tense claim about a surviving file -> FAIL
  printf 'note: alive.sh is retired and has no surviving code\n' > "$d/req.yaml"
  _r; [ "$status" -eq 1 ]; [[ "$output" == *"alive.sh"* ]]

  # HISTORY must not trip it — this is the shape of a correct, corrected note
  printf 'note: alive.sh was retired 2026-08-08, then RESTORED 2026-08-12\n' > "$d/req.yaml"
  _r; [ "$status" -eq 0 ]

  # a TRUE retirement (the file really is gone) passes
  printf 'note: gone.sh is retired and stays retired\n' > "$d/req.yaml"
  _r; [ "$status" -eq 0 ]

  # and a missing input FAILS loudly rather than reporting ok for a check that never ran
  run bash -c 'cd "$1" && dev/doc-lint.sh retired "$1/nope.yaml"' _ "$d"
  [ "$status" -eq 1 ]; [[ "$output" == *"did not run"* ]]
}

@test "doc-lint ledger: a missing file FAILS loudly instead of reporting ok (R78)" {
  # It exited 0, and check.sh then printed "ok (ledger measurements cite their evidence)" for a
  # check that never ran — a gate reporting green on work it did not do.
  run "$DEV/doc-lint.sh" ledger /nonexistent/REQUIREMENTS.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "R81 hook budget: the gate CATCHES a store-scaling hook and PASSES a bounded one" {
  # The gate's own guard. A budget gate that cannot fail is theatre, so prove both directions
  # against a REAL scaling hook rather than a stub: a fake bin/ whose statusline.sh reads the
  # whole store (the shape of the 2085ms->16108ms session-start regression this gate was built to
  # catch — session-start.sh, then stop-autopilot.sh, both retired since, R100/Pass 2 and Pass 4,
  # but the scaling failure mode is generic to any hook that reads the store, so the fixture keeps
  # getting renamed to whatever hook is still standing, never dropped) must FAIL, and a bounded one PASS.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  local fake; fake="$(_tmpd)"; mkdir -p "$fake/bin" "$fake/lib"
  cp "$DEV/hook-budget.sh" "$fake/bin/"; cp "$ROOT/lib/companion.sh" "$fake/lib/"
  # BOUNDED: touches nothing in the store. Must pass.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/bin/statusline.sh"
  chmod +x "$fake/bin/statusline.sh"
  # Pin the ABSOLUTE cap, which is the hard gate since the recalibration, and use a store big
  # enough that the unbounded hook clears the noise floor. With the old tiny store the fake
  # hook measured UNDER NOISE_MS, where the ratio is not enforced — so the gate passed it and
  # this guard silently stopped guarding. It failed only under load, which is how it surfaced.
  run env HOOK_BUDGET_BIN="$fake/bin" HOOK_BUDGET_BASEDIRS=8 HOOK_BUDGET_PERDIR=8 HOOK_BUDGET_ABSCAP=200 bash "$fake/bin/hook-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"statusline.sh"* ]]
  # UNBOUNDED: one jq per file across every session dir — cost tracks the store. Must fail.
  cat > "$fake/bin/statusline.sh" <<'EOS'
#!/usr/bin/env bash
for f in "${CLAUDE_COMPANION_TASKS_DIR:-/nonexistent}"/*/*.json; do
  [ -f "$f" ] || continue
  jq -r '.subject // empty' "$f" >/dev/null 2>&1 || true
done
exit 0
EOS
  chmod +x "$fake/bin/statusline.sh"
  run env HOOK_BUDGET_BIN="$fake/bin" HOOK_BUDGET_BASEDIRS=8 HOOK_BUDGET_PERDIR=8 HOOK_BUDGET_ABSCAP=200 bash "$fake/bin/hook-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "R81 hook budget: a missing jq/git SKIPS clean — the gate never false-reds the environment" {
  # Best-effort about the environment, strict about the budget (R7/R68): a toolless box must not
  # turn into a red build, or the gate gets deleted for being flaky.
  local fake bsh; fake="$(_tmpd)"; mkdir -p "$fake/bin" "$fake/empty"
  cp "$DEV/hook-budget.sh" "$fake/bin/"
  # Absolute interpreter path: `env PATH=<empty> bash …` would fail to find bash ITSELF, which
  # tests nothing about the gate. Emptying PATH must hide jq/git from the script, not the shell.
  bsh="$(command -v bash)"
  run env PATH="$fake/empty" HOOK_BUDGET_BIN="$fake/bin" "$bsh" "$fake/bin/hook-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "R81 hook budget: measures under a COMMA-DECIMAL locale (LC_ALL=C is load-bearing)" {
  # TIMEFORMAT renders through the locale: under de_DE every sample was "0,124", failed the
  # digits-only guard and fell through to 0 — a green gate that measured nothing at all.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run env LC_NUMERIC=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 \
      HOOK_BUDGET_BASEDIRS=6 HOOK_BUDGET_PERDIR=4 bash "$DEV/hook-budget.sh"
  [ "$status" -eq 0 ]
  # at least one hook must report a NON-zero measurement
  [[ "$output" =~ [1-9][0-9]*ms ]]
}
@test "mutation gate: only a COMPLETE run that failed counts as caught (R78)" {
  # THE POINT: "bats exited nonzero" and "a test failed" are different claims, and conflating them
  # made the gate certify holes as covered. Each case below exits nonzero; only one is evidence.

  # (1) KILLED — exit 124, nothing ran. This is what load does, and what made a real pace-marker
  #     hole report as caught locally while CI called it a hole (3.30.2).
  run _mutgate "$(_shim 'exit 124')" killed
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not COMPLETE"* ]]; [[ "$output" != *"ok    caught"* ]]

  # (2) PARTIAL — the plan promises 3 results, 2 arrive. A run cut short mid-suite still emits a
  #     `not ok`, so checking only for one accepts a suite that never finished.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; exit 1')" partial
  [ "$status" -ne 0 ]; [[ "$output" == *"did not COMPLETE"* ]]

  # (3) GENUINE — a complete run of 3 with one failure. The gate must still do its actual job.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; echo "ok 3 c"; exit 1')" real
  [ "$status" -eq 0 ]; [[ "$output" == *"caught"* ]]

  # (4) GREEN — the mutation survived. Still a hole.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "ok 2 b"; echo "ok 3 c"; exit 0')" green
  [ "$status" -ne 0 ]; [[ "$output" == *"HOLE"* ]]
}

@test "mutation gate: a suite ALREADY RED is refused — it would score every mutation caught (R78)" {
  # The deepest version of this gate's failure mode. Every verdict is "did the suite go red?",
  # which measures nothing if it was red beforehand: ONE pre-existing failure makes EVERY mutation
  # report "caught" and the gate hand back a clean bill of health for coverage it never saw.
  # This is not hypothetical — a killed run left doc-lint.sh mutated in the tree, one test went
  # red, and the gate duly certified two mutations it had not actually measured.
  local d="$BATS_TEST_TMPDIR/mgred"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "a" { true; }\n@test "already broken" { false; }\n@test "c" { true; }\n' \
    > "$d/dev/tests/t.bats"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ALREADY RED"* ]]
  [[ "$output" == *"already broken"* ]]   # names the culprit rather than just refusing
  [[ "$output" != *"ok    caught"* ]]     # no mutation was scored
}

@test "mutation gate: refuses to run CONCURRENTLY on one tree (R78/R7)" {
  # Two runs restore each other's *.mutbak and leave enforced core MUTATED in the working tree,
  # ready for the next `git add -A`. That happened: doc-lint.sh lost its BOM stripping and ship.sh
  # lost sight of untracked critical paths, both silently.
  local d="$BATS_TEST_TMPDIR/mglock"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "a" { true; }\n@test "b" { true; }\n' > "$d/dev/tests/t.bats"
  # Hold the lock the way a RUNNING gate would — with a live owning pid recorded in it. Since
  # 2026-08-16 presence alone is not enough: a lock whose owner is dead is reclaimed rather than
  # obeyed, because a SIGKILLed run leaves no trap and its lock used to block every later run
  # forever. The case that genuinely corrupts backups is a LIVE peer, and that is what this pins.
  local lk; lk="${TMPDIR:-/tmp}/companion-mutate-$(printf '%s' "$d" | cksum | cut -d' ' -f1).lock"
  mkdir -p "$lk"
  sleep 60 & local peer=$!
  printf '%s\n' "$peer" > "$lk/pid"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  kill "$peer" 2>/dev/null || true
  rm -f "$lk/pid"; rmdir "$lk" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [[ "$output" == *"another --mutate run"* ]]
  [[ "$output" != *"ok    caught"* ]]
  # and the target was never touched while the lock was held
  run cat "$d/plugins/companion/target.sh"
  [ "$output" = "VALUE=1" ]
}

@test "mutation gate: --shard partitions the set with no gaps and no overlap (R78)" {
  # 65 mutations x a ~50s suite is ~55 minutes serially, and a long job blocks log access for the
  # WHOLE CI run — a red check lane could not be read until the mutation lane finished. Sharding
  # is only safe if the shards are a true partition: every mutation runs exactly once across them.
  local d="$BATS_TEST_TMPDIR/mgshard"
  mkdir -p "$d/dev/tests" "$d/plugins/companion" "$d/shim"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  local i
  for i in 1 2 3 4 5; do printf 'V%s=1\n' "$i" >> "$d/plugins/companion/target.sh"; done
  for i in 1 2 3 4 5; do
    printf 'plugins/companion/target.sh::s@V%s=1@V%s=2@::mutation %s\n' "$i" "$i" "$i"
  done > "$d/dev/tests/mutations.txt"
  printf '%s\n' "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; echo "ok 3 c"; exit 1')" > "$d/shim/bats"
  chmod +x "$d/shim/bats"
  _run_shard() {  # $1 = shard spec, or "" for the whole set
    rm -f "$d/shim/bats.n"
    ( cd "$d" && PATH="$d/shim:$PATH" ./dev/mutate-gate.sh ${1:+--shard "$1"} 2>&1 | tail -1 )
  }
  # Every shard runs SOME, and the parts sum to the whole — no mutation skipped, none run twice.
  local a b whole
  a="$(_run_shard 0/2)"; b="$(_run_shard 1/2)"; whole="$(_run_shard '')"
  [[ "$a" =~ all\ ([0-9]+)\ mutations ]]; local na="${BASH_REMATCH[1]}"
  [[ "$b" =~ all\ ([0-9]+)\ mutations ]]; local nb="${BASH_REMATCH[1]}"
  [[ "$whole" =~ all\ ([0-9]+)\ mutations ]]; local nw="${BASH_REMATCH[1]}"
  [ "$nw" -eq 5 ]
  [ "$(( na + nb ))" -eq "$nw" ]
  [ "$na" -gt 0 ] && [ "$nb" -gt 0 ]
  # A malformed spec is refused rather than silently running everything.
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh --shard nonsense' _ "$d"
  [ "$status" -eq 2 ]
}

# ── the CI wall-clock projection (R81 applied to CI: R74's watch ceiling vs the mutation set) ──
_mgproj() {  # $1=shards $2=ceiling-seconds $3=seconds-per-mutation $4=mutation-count
  local d="$BATS_TEST_TMPDIR/mgproj_$1_$2_$3_$4" i
  mkdir -p "$d/dev/tests" "$d/plugins/companion/bin" "$d/.github/workflows" "$d/shim"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  for i in $(seq 1 "$4"); do printf 'V%s=1\n' "$i" >> "$d/plugins/companion/target.sh"; done
  for i in $(seq 1 "$4"); do
    printf 'plugins/companion/target.sh::s@V%s=1@V%s=2@::mutation %s\n' "$i" "$i" "$i"
  done > "$d/dev/tests/mutations.txt"
  # Written EXACTLY as the real workflow writes it. `${{ matrix.shard }}` CONTAINS SPACES, and the
  # first draft of the projection matched with a no-space class — so it parsed nothing, skipped
  # itself, and reported success. A fixture with a simplified `--shard N/M` would have passed that
  # bug straight through, which is the whole reason this line is verbatim.
  printf '        run: ./check.sh --mutate --shard ${{ matrix.shard }}/%s\n' "$1" \
    > "$d/.github/workflows/ci.yml"
  printf 'timeout="${SHIP_CI_TIMEOUT:-%s}"\n' "$2" > "$d/plugins/companion/bin/ci-watch.sh"
  printf '%s\n' "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "ok 2 b"; echo "ok 3 c"; exit 0')" \
    > "$d/shim/bats"
  chmod +x "$d/shim/bats"
  ( cd "$d" && PATH="$d/shim:$PATH" MUTGATE_SEC_PER_MUT="$3" ./dev/mutate-gate.sh --validate 2>&1 )
}

@test "mutation gate: projected CI wall-clock well under the watch ceiling says nothing (R74/R81)" {
  # 10 mutations / 5 shards = 2 on the slowest x 100s = 200s against a 1000s ceiling = 20%.
  # Silence is the correct output here: a gate that comments on every healthy run trains the
  # reader to skip its output, which is how the 60% warning below would get missed.
  run _mgproj 5 1000 100 10
  [ "$status" -eq 0 ]
  [[ "$output" == *"all still apply"* ]]
  [[ "$output" != *"CI wall-clock"* ]]
}

@test "mutation gate: projected CI wall-clock nearing the watch ceiling WARNS (R74/R81)" {
  # 2 x 100s = 200s against 300s = 66%. Warn BEFORE it bites: the fix (add shards) takes a minute,
  # whereas discovering it after the fact costs a ship that reports UNWATCHED and a manual watch.
  run _mgproj 5 300 100 10
  [ "$status" -eq 0 ]                              # a forecast must not fail the gate
  [[ "$output" == *"WARN CI wall-clock"* ]]
  [[ "$output" == *"66% of the 300s"* ]]
}

@test "mutation gate: projected CI wall-clock OVER the watch ceiling FAILS (R74/R81)" {
  # 9 mutations / 5 shards is deliberately NOT divisible: ceil = 2 on the slowest shard (200s,
  # 133%, fails) while a floor would give 1 (100s, 66%, merely warns). The SLOWEST shard sets the
  # wall-clock, so rounding down here would under-report the very thing being measured.
  # 2 x 100s = 200s against 150s = 133%. Not a forecast — the watch already cannot outlast the run,
  # so every land exits 12 and R74's guarantee is dead while still reading like a guarantee. This
  # is the case that went unnoticed TWICE (300s outgrown 2026-08-01, 1800s outgrown 2026-08-22),
  # both times discovered by a ship rather than by the gate.
  run _mgproj 5 150 100 9
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL CI wall-clock"* ]]
  [[ "$output" == *"EXCEEDS the 150s watch ceiling"* ]]
  [[ "$output" == *"Add shards"* ]]                # the message names the remedy, not just the fact
}

@test "mutation gate: an unreadable operand SKIPS the projection, never fails on it (R74/R81)" {
  # The projection is a courtesy on top of mutation validation. A fixture tree, a fork that renamed
  # the workflow, a checkout without .github — none of those are mutation-coverage defects, and
  # failing them here would make the real gate unrunnable outside this repo's exact layout.
  local d="$BATS_TEST_TMPDIR/mgproj_5_150_100_9"
  run _mgproj 5 150 100 9                           # build the fixture (and prove it DOES fail)
  [ "$status" -eq 1 ]
  rm -f "$d/plugins/companion/bin/ci-watch.sh"      # now remove the ceiling's only source
  run bash -c 'cd "$1" && PATH="$1/shim:$PATH" MUTGATE_SEC_PER_MUT=100 ./dev/mutate-gate.sh --validate 2>&1' _ "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"all still apply"* ]]
  [[ "$output" != *"CI wall-clock"* ]]
  # And SILENTLY. Asserting only the clean exit could not tell a real skip from a guard that fell
  # through to `[ "" -ge 1 ]` — bash returns 2 there, the `||` still yields 0, and the only trace is
  # an "integer expected" line on stderr. That is exactly how this assertion's first draft scored a
  # broken guard as passing: same outcome, different reason. Pin the reason, not just the outcome.
  [[ "$output" != *"integer expected"* ]]
  [[ "$output" != *"integer expression"* ]]
}

@test "mutation gate: an UNPARSEABLE suite is refused up front, not scored (R78)" {
  # bats answers a suite it cannot parse with a perfectly well-formed `1..1 / not ok
  # bats-gather-tests` — zero tests run. Demanding "a ^not ok" therefore does NOT distinguish it,
  # and the first version of this very fix scored EVERY mutation as caught because of it, exiting
  # 0. Calibrating with `bats --count` catches it before a single mutation is applied.
  local d="$BATS_TEST_TMPDIR/mgparse"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "broken" {\n  if true; then\n}\n' > "$d/dev/tests/x.bats"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot enumerate the suite"* ]]
  [[ "$output" != *"caught"* ]]
}

@test "check.sh actually INVOKES the portability lint, both halves (wiring guard)" {
  # bats cannot run check.sh (check.sh runs bats), so this is structural — the same shape as the
  # doc-lint wiring guard. Without it, check.sh could quietly stop calling the linter, or call only
  # one half, and every test above would still pass while the gate protected nothing.
  run grep -c 'portability-lint\.sh all' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  # The fixtures invocation is a SEPARATE call over the test files, so `all` being wired says
  # nothing about it — CI caught exactly that as a hole.
  run grep -c 'portability-lint\.sh fixtures' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  # ...and so is `boundary`. The mutation gate reported this exact hole when the lint shipped: the
  # guard existed, was tested, and check.sh never called it.
  run grep -c 'portability-lint\.sh boundary' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  # command-lint was extracted out of check.sh when the 300-line guard fired; an extraction that
  # leaves the caller behind is the same hole in a new place.
  # Match the INVOCATION, not the name: grepping for the bare filename also matched the comment
  # ABOVE the call, so stubbing the call out left this green — the mutation gate caught exactly
  # that. Same family as the TODO scanner that fed on prose about TODO markers.
  run grep -c '\$(dev/command-lint\.sh)' "$DEV/token-budget.sh"
  [ "$output" -ge 1 ]
}

@test "portability-lint: catches the two traps that keep shipping red CI, and honours its markers" {
  # These two guards were written INLINE in check.sh with declared mutations and no tests, so the
  # mutation gate correctly reported both as HOLES — a guard that cannot fail is not a guard. They
  # live in dev/ now for the same reason doc-lint does: so the suite can reach them.
  local d; d="$BATS_TEST_TMPDIR/pl"; mkdir -p "$d"
  local L="$DEV/portability-lint.sh"

  # SC2015: `A && B || C` reads as if-then-else and is not. CI's shellcheck flags it; the local
  # build does not, which is exactly how it shipped red three times.
  printf '%s\n' '[ -n "$a" ] && [ -n "$b" ] || exit 1' > "$d/bad-sc.sh"
  run "$L" sc2015 "$d/bad-sc.sh"; [ "$status" -eq 1 ]; [[ "$output" == *"bad-sc.sh"* ]]
  printf '%s\n' '[ -n "$a" ] && [ -n "$b" ] || exit 1   # sc2015-ok: unless both held' > "$d/ok-sc.sh"
  run "$L" sc2015 "$d/ok-sc.sh"; [ "$status" -eq 0 ]; [ -z "$output" ]

  # GNU-only escapes: BSD sed/grep read \+ \? \| as LITERALS. This one made burn-down unable to
  # create a single branch on macOS while Linux stayed green.
  printf '%s\n' "x=\$(printf a | sed -e 's/[a-z]\\+/-/g')" > "$d/bad-bre.sh"
  run "$L" bre "$d/bad-bre.sh"; [ "$status" -eq 1 ]; [[ "$output" == *"bad-bre.sh"* ]]
  # An escaped pipe inside an ERE is correct, not a violation — -E/-r invocations are exempt.
  printf '%s\n' "grep -nE 'a\\|b' f" > "$d/ere.sh"
  run "$L" bre "$d/ere.sh"; [ "$status" -eq 0 ]
  printf '%s\n' "sed -e 's/a\\+/b/' f   # bre-ok: deliberate literal plus" > "$d/ok-bre.sh"
  run "$L" bre "$d/ok-bre.sh"; [ "$status" -eq 0 ]

  # A comment mentioning the shape is not code.
  printf '%s\n' '# never write [ a ] && [ b ] || c' > "$d/comment.sh"
  run "$L" all "$d/comment.sh"; [ "$status" -eq 0 ]
  # fixtures: a bare `$(mktemp -d)` in a test leaks a dir bats would otherwise have removed.
  # Checked HERE rather than by a bats case, because a test that greps for the pattern contains
  # the pattern and so fails on itself forever — which is exactly what happened when I tried.
  # Build the leaky line from PARTS: writing the literal into this file would make the fixtures
  # lint flag companion-core.bats itself — the same self-reference that killed the bats-based
  # version of this guard.
  local mk='mktemp -d'
  printf 'repo="$(%s)"\n' "$mk" > "$d/leaky.bats"
  run "$L" fixtures "$d/leaky.bats"; [ "$status" -eq 1 ]; [[ "$output" == *"leaky.bats"* ]]
  printf '%s\n' 'repo="$(_tmpd)"' > "$d/clean.bats"
  run "$L" fixtures "$d/clean.bats"; [ "$status" -eq 0 ]; [ -z "$output" ]

  # `all` fails if EITHER lints fail.
  run "$L" all "$d/bad-sc.sh" "$d/bad-bre.sh"; [ "$status" -eq 1 ]
  run "$L" all "$d/ok-sc.sh" "$d/ok-bre.sh" "$d/ere.sh"; [ "$status" -eq 0 ]
}

@test "check.sh actually INVOKES the traceability gate (wiring guard)" {
  # bats cannot run check.sh (check.sh runs bats), so this is structural — same shape as the
  # doc-lint and portability wiring guards. Without it check.sh could stop running trace.sh and
  # every requirement could drift out of its tests with the suite still green.
  run grep -c 'dev/trace\.sh' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
}
@test "stale: only the requirement whose OWN test block moved goes stale — same file, both tests (R97)" {
  # THE design claim. 130 of this repo's tests live in one .bats, so a file-granular drift signal
  # would give every requirement claiming a test in it the same score and the ranking would carry
  # no information at all. Two requirements, one file, one block churning: only that one may fire.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  cat > "$d/docs/requirements.yaml" <<'EOT'
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  requirement: >
    alpha stays true
  verified_by:
    - "alpha holds"

- id: R2
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  requirement: >
    beta stays true
  verified_by:
    - "beta holds"
EOT
  _stale_commit "$d" 2019-06-01 init
  local i
  for i in 1 2 3 4; do _bump_alpha "$d" "$i"; _stale_commit "$d" "2021-0$i-01" "churn $i"; done

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [ "$(_st R1)" = STALE ]      # 4 commits to its block, threshold 3
  [ "$(_st R2)" = ok ]         # same FILE, untouched BLOCK — must not be billed for R1's churn
}

@test "stale: re-affirming multiplies the threshold, so a surviving requirement goes quiet (R97)" {
  # Surviving a challenge is evidence. Without the backoff the same requirement is re-litigated
  # every time its tests move, which is how a challenge mechanism turns into noise and gets muted.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  _mkreq() {                                     # $1=affirmations
    cat > "$d/docs/requirements.yaml" <<EOT
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: $1
  requirement: >
    alpha stays true
  verified_by:
    - "alpha holds"
EOT
  }
  _mkreq 0
  _stale_commit "$d" 2019-06-01 init
  local i
  for i in 1 2 3 4; do _bump_alpha "$d" "$i"; _stale_commit "$d" "2021-0$i-01" "churn $i"; done

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$(_st R1)" = STALE ]                        # drift 4 >= base 3

  _mkreq 1                                       # affirmed once -> threshold doubles to 6
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$(_st R1)" = ok ]
  [[ "$output" == *"4/6"* ]]                     # and it SHOWS the raised bar, not just silence
}

@test "stale: a judgment-shaped requirement expires on CALENDAR — the only axis it has (R97)" {
  # These name no test by construction, so there is no contact to measure. Age is all that is
  # left; the alternative is exempting exactly the requirements nobody can verify.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  cat > "$d/docs/requirements.yaml" <<'EOT'
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  judgment: "a ritual, not a code path"
  requirement: >
    the ritual is worth running
  verified_by: []

- id: R2
  satisfies: [UN-1]
  affirmed: 2199-01-01
  affirmations: 0
  judgment: "also a ritual"
  requirement: >
    the other ritual is worth running
  verified_by: []
EOT
  _stale_commit "$d" 2019-06-01 init
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [ "$(_st R1)" = STALE ]                        # long past the 180d base
  [ "$(_st R2)" = ok ]                           # affirmed in the future: nothing to ask about
}

@test "stale: advisory — it reports on a tree it cannot measure and never fails the build (R97/R28)" {
  # The line R28 draws: code blocks, injects, or guarantees control flow. This does none of the
  # three, so a non-zero exit from it would put a JUDGEMENT call into a gate, which is the exact
  # mistake of asserting a requirement is dead because a clock ran out.
  local d; d="$(_tmpd)"; mkdir -p "$d/dev" "$d/docs"; cp dev/stale.sh "$d/dev/stale.sh"

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"   # no requirements file, no git repo
  [ "$status" -eq 0 ]

  git -C "$d" init -q; mkdir -p "$d/dev/tests"
  printf -- '- id: R1\n  satisfies: [UN-1]\n  requirement: >\n    x\n  verified_by:\n    - "gone"\n' \
    > "$d/docs/requirements.yaml"                # no affirmed:, and it claims a test that is absent
  _stale_commit "$d" 2019-06-01 init
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO affirmed"* ]]             # reported, loudly, and still exit 0
}

@test "trace: a requirement with no affirmed:/affirmations: stamp FAILS the shape gate (R97)" {
  # stale.sh cannot date a requirement that carries no stamp, and an OPTIONAL field is a field
  # that is missing on the next entry someone adds. The shape gate is where that is prevented.
  local d; d="$(_tmpd)"; mkdir -p "$d/dev/tests" "$d/docs"; cp dev/trace.sh "$d/dev/trace.sh"
  printf -- '- id: UN-1\n  need: >\n    a thing\n' > "$d/docs/needs.yaml"
  printf -- '@test "alpha holds" {\n  run true\n}\n' > "$d/dev/tests/t.bats"
  _tr() { run bash -c 'cd "$1" && dev/trace.sh' _ "$d"; }

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: 2026-08-02\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -eq 0 ]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmed"* ]]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: last tuesday\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmed"* ]]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: 2026-08-02\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmations"* ]]
}

@test "check.sh's lint set INCLUDES bin/tq — the extensionless file the glob silently missed (R110 wiring guard)" {
  # MEASURED HOLE, 2026-08-11. `scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)` globs on
  # `.sh`, and `bin/tq` has no extension — it is the ONLY extensionless file in bin/. So THE task
  # queue (R8/R10), which every command and the MCP server route through, was invisible to
  # ShellCheck, portability-lint AND the size guard at once. The gate reported green while tq grew
  # 355 -> 382 lines. A gate that cannot fail on the file that matters most is UN-5's failure shape.
  # bats cannot run check.sh (check.sh runs bats), so this is structural, like the wiring guards above.
  local c="$ROOT/../../check.sh"
  run grep -cE '^scripts=\(.*bin/tq' "$c"
  [ "$output" -ge 1 ]

  # And the file really is extensionless — if it ever gains `.sh` the glob covers it and this guard
  # becomes theatre, so the premise is pinned too.
  [ -f "$ROOT/bin/tq" ]
  [ ! -f "$ROOT/bin/tq.sh" ]
}

@test "check.sh's size guard has NO exemptions — the tq debt was PAID, not waived (R110)" {
  # HISTORY, kept because it is the point. `bin/tq` sat at 382 lines outside the size guard
  # entirely: the glob was `bin/*.sh` and tq has no extension, so the gate could not fail on the
  # most-called file in the product. Wiring it in forced a choice — decompose THE task queue inside
  # the change that found the hole, or exempt it visibly. It was exempted BY NAME, printed on every
  # run, with a staleness check that went RED the moment tq dropped back under 300.
  #
  # That trap fired on 2026-08-12 and the debt was PAID (tq 382 -> 285, usage()+report() extracted
  # to tq-output.sh on a cohesion seam). This test replaces the one that watched the exemption: what
  # matters now is that NO exemption ever comes back quietly. A named, printed, self-expiring
  # exemption was defensible for a day; a silent one is how tq drifted to 382 unseen.
  local c="$ROOT/../../check.sh"
  run grep -cE 'size_skip|EXEMPT' "$c"
  [ "$output" -eq 0 ] || { echo "a size exemption reappeared in check.sh — it must be paid, not waived" >&2; false; }

  # And the file it was granted for is genuinely under the cap now, not merely un-exempted.
  run bash -c 'wc -l < "$1"' _ "$ROOT/bin/tq"
  [ "$output" -le 300 ]
  # ...via a real seam, not a stub: the extracted half must exist and carry both renderers.
  [ -r "$ROOT/bin/tq-output.sh" ]
  run grep -cE '^(usage|report)\(\) \{' "$ROOT/bin/tq-output.sh"
  [ "$output" -eq 2 ]
}

@test "rework ledger: never proposes a bounded rebuild of its OWN storage file" {
  # The third self-referential defect found on 2026-08-16, after candidates rank 3 feeding on its
  # own documentation and rank 1 offering the model's own unreviewed park. `record` writes a row per
  # implicated file and the ledger is touched by the work being recorded, so it climbs the threshold
  # on its own bookkeeping and then proposes rebuilding it.
  local d; d="$(_tmpd)"; git -C "$d" init -q
  mkdir -p "$d/.companion"
  # push BOTH the ledger itself and a real source file over the rebuild threshold
  local i
  for i in 1 2 3 4 5; do
    REWORK_ROOT="$d" bash "$ROOT/bin/rework.sh" record ci-red "src/thing.sh" ".companion/rework" >/dev/null
  done
  run env REWORK_ROOT="$d" bash "$ROOT/bin/rework.sh" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"⟳"* ]]                       # it still recommends SOMETHING...
  [[ "$output" == *"src/thing.sh"* ]]            # ...namely the real source file
  [[ "$output" != *"⟳ .companion/rework"* ]]     # ...but never its own record of the work
}

@test "portability-lint sedi: a bare 'sed -i' FAILS, the suffixed and temp-file forms pass" {
  # FIFTH BSD-vs-GNU incident here, and the first to be caught by a lint instead of by CI. GNU takes
  # the next argument as the SCRIPT; BSD takes it as the BACKUP SUFFIX, so the edit silently does
  # not happen — and a test that depended on it then passes for the wrong reason. That is exactly
  # how it reddened the macOS lane on 3.87.0.
  local d; d="$(_tmpd)"
  printf 'sed -i "s@a@b@" f.sh\n' > "$d/bad.sh"   # sedi-ok: deliberately bad FIXTURE data
  run bash "$DEV/portability-lint.sh" sedi "$d/bad.sh"
  [ "$status" -eq 1 ]; [[ "$output" == *"BACKUP SUFFIX"* ]]

  printf 'sed -i.bak "s@a@b@" f.sh\nsed "s@a@b@" f > t && mv t f\n' > "$d/good.sh"
  run bash "$DEV/portability-lint.sh" sedi "$d/good.sh"
  [ "$status" -eq 0 ]

  # a comment mentioning it is documentation, not a call
  printf '# never use sed -i without a suffix\n' > "$d/doc.sh"   # sedi-ok: fixture data
  run bash "$DEV/portability-lint.sh" sedi "$d/doc.sh"
  [ "$status" -eq 0 ]
}

@test "rework ledger: a 'rebuilt' event retires that path's ⟳ recommendation, and only that path's" {
  # #116, owner-decided 2026-08-16. The list counted every failure ever recorded, so it kept
  # proposing rebuilds for work already done — lib/companion.sh and the test monolith were both
  # still listed an hour after being decomposed and split. A recommendation nothing can satisfy is
  # noise, and burn-down rank 5 CONSUMES this list, so the noise can become generated work.
  local d; d="$(_tmpd)"; git -C "$d" init -q
  local R="$ROOT/bin/rework.sh" i
  for i in 1 2 3 4; do
    REWORK_ROOT="$d" bash "$R" record ci-red "src/a.sh" "src/b.sh" >/dev/null
  done
  run env REWORK_ROOT="$d" bash "$R" report
  [[ "$output" == *"⟳ src/a.sh"* ]] && [[ "$output" == *"⟳ src/b.sh"* ]]

  REWORK_ROOT="$d" bash "$R" record rebuilt "src/a.sh" >/dev/null
  run env REWORK_ROOT="$d" bash "$R" report
  [[ "$output" != *"⟳ src/a.sh"* ]]      # retired by the rebuild...
  [[ "$output" == *"⟳ src/b.sh"* ]]      # ...and nothing else moved
  [[ "$output" != *"rebuilt"* ]]         # a rebuild is not a rework label

  # A REBUILD THAT DID NOT HOLD says so on its own. These land in the SAME second as the rebuilt
  # row, which is exactly the case a timestamp-only comparison dropped silently — the ledger is
  # append-only, so row order is the tiebreak.
  for i in 1 2 3; do REWORK_ROOT="$d" bash "$R" record ci-red "src/a.sh" >/dev/null; done
  run env REWORK_ROOT="$d" bash "$R" report
  [[ "$output" == *"⟳ src/a.sh implicated in 3 failures"* ]]

  # append-only: nothing was deleted from the ledger
  run grep -c "src/a.sh" "$d/.companion/rework"
  [ "$output" -eq 8 ]
}

@test "rework ledger: structured DATA is never a rebuild candidate, but code and prose still are" {
  # #115, owner-decided 2026-08-16. /companion:redesign does a CONTRACT-PRESERVING rebuild, which is
  # meaningless for a version manifest and actively wrong for the contract itself — the thing a
  # rebuild must preserve. Both were being recommended because every ship touches them.
  # Structural detection, never an extension list (R9): jq settles JSON, and a `key:`/`- ` line
  # ratio settles YAML. Measured on the real repo: data 50-59%, code and prose 0-8%.
  local d; d="$(_tmpd)"; git -C "$d" init -q
  local R="$ROOT/bin/rework.sh" i
  mkdir -p "$d/cfg"
  printf '{"name":"x","version":"1.2.3","plugins":[{"a":1}]}\n'      > "$d/cfg/manifest.json"
  printf -- '- id: R1\n  requirement: a thing\n- id: R2\n  requirement: another\n' > "$d/cfg/contract.yaml"
  printf '#!/usr/bin/env bash\nf() { echo hi; }\nif true; then f; fi\n'   > "$d/code.sh"
  printf '# A doc\n\nSome prose about the system, written for a reader.\n' > "$d/prose.md"
  for i in 1 2 3 4; do
    REWORK_ROOT="$d" bash "$R" record ci-red cfg/manifest.json cfg/contract.yaml code.sh prose.md >/dev/null
  done
  run env REWORK_ROOT="$d" bash "$R" report
  [ "$status" -eq 0 ]
  [[ "$output" != *"manifest.json"* ]]   # a version manifest has nothing to redesign
  [[ "$output" != *"contract.yaml"* ]]   # the contract is what a rebuild PRESERVES
  [[ "$output" == *"⟳ code.sh"* ]]       # code still is
  [[ "$output" == *"⟳ prose.md"* ]]      # ...and so is prose: the rule is "not DATA", not "not text"
}

@test "token-budget: an oversized injected core FAILS, and the marker must appear exactly once" {
  # Extracted from check.sh 2026-08-16 for the R78 reason — inline, the SUITE could not invoke it,
  # so the gate that decides what every session pays for had no test of its own. It reads
  # repo-relative paths, so the fixture mirrors the real layout and the test runs from inside it.
  local d; d="$(_tmpd)"
  mkdir -p "$d/plugins/companion/commands" "$d/plugins/companion/mcp-server" "$d/docs/adr" "$d/dev"
  printf '  "board",\n' > "$d/plugins/companion/mcp-server/index.js"   # token-budget calls command-lint
  cp "$DEV/token-budget.sh" "$d/dev/"
  cp "$DEV/doc-lint.sh" "$DEV/command-lint.sh" "$d/dev/"
  cp docs/adr/PROVENANCE.md "$d/docs/adr/" 2>/dev/null || printf '| **R1** | x |\n' > "$d/docs/adr/PROVENANCE.md"
  cp docs/requirements.yaml "$d/docs/" 2>/dev/null || printf -- '- id: R1\n' > "$d/docs/requirements.yaml"
  printf -- '---\ndescription: short\n---\n\nBody calls `board`.\n' > "$d/plugins/companion/commands/ok.md"

  # a core comfortably UNDER the cap, with exactly one marker
  { printf 'tiny core\n'; printf 'injection stops here\n'; printf 'rationale below\n'; } \
    > "$d/plugins/companion/STEERING.md"
  run bash -c 'cd "$1" && dev/token-budget.sh' _ "$d"
  [ "$status" -eq 0 ]

  # an OVERSIZED core must fail — this is the number every session pays
  { head -c 20000 /dev/zero | tr '\0' 'x'; printf '\ninjection stops here\n'; } \
    > "$d/plugins/companion/STEERING.md"
  run bash -c 'cd "$1" && dev/token-budget.sh' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"injected core"* ]]

  # the marker must appear EXACTLY once, or the split between injected and on-demand is undefined
  { printf 'core\ninjection stops here\nmore\ninjection stops here\n'; } \
    > "$d/plugins/companion/STEERING.md"
  run bash -c 'cd "$1" && dev/token-budget.sh' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"marker count"* ]]
}

@test "feature-class: a flow page CHANGED ALONGSIDE code is user-visible; the other shapes are not (R116)" {
  # Owner-decided 2026-08-20: one bit derived from the contract, NOT a hand-set task level. A level
  # would be a second classification beside needs->requirements->tests, unverifiable, and most likely
  # used to justify a LOWER bar. This uses a signal the repo already maintains (R58) and cannot rot,
  # because it IS the contract. Generic by construction: "implementation" is any changed path
  # outside docs/ and .companion/, never a language or extension list (R9).
  _fc() { run bash -c '. "$1"; companion_is_feature_class "$2" && echo FEATURE || echo ordinary' \
            _ "$ROOT/lib/companion.sh" "$2"; }

  _fc x "$(printf 'docs/flows/checkout.md\nplugins/companion/bin/tq\n')"
  [ "$output" = FEATURE ]                       # behaviour documented AND implemented

  _fc x "$(printf 'docs/flows/checkout.md\n')"
  [ "$output" = ordinary ]                      # a typo in a flow page is not a release

  _fc x "$(printf 'plugins/companion/bin/tq\n')"
  [ "$output" = ordinary ]                      # a fix that alters no documented behaviour

  _fc x "$(printf 'docs/flows/checkout.md\n.companion/tasks/1.json\n')"
  [ "$output" = ordinary ]                      # queue churn is not implementation

  _fc x ""
  [ "$output" = ordinary ]                      # nothing changed
}

@test "command-lint portability floor: a command with no portable footing FAILS; a reasoned cli-only marker passes" {
  # The plugin's thesis is portable CAPABILITY + native PRESENTATION. A command naming no MCP tool
  # and no bin/ script is a capability reachable only from Claude Code — the drift that thesis loses
  # to. Stated ceiling: this checks that a portable mechanism is NAMED, not that it is the right one
  # or that the real work goes through it. A floor, not a proof.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/commands" "$d/plugins/companion/mcp-server" "$d/dev"
  cp "$DEV/command-lint.sh" "$DEV/doc-lint.sh" "$d/dev/"
  printf '  "tq_add",\n  "board",\n' > "$d/plugins/companion/mcp-server/index.js"
  local _cl; _cl() { run bash -c 'cd "$1" && dev/command-lint.sh' _ "$d"; }

  # names an MCP tool -> fine
  printf -- '---\ndescription: does a thing\n---\n\nCall the `board` tool.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 0 ]

  # names a bin/ script -> also fine
  printf -- '---\ndescription: does a thing\n---\n\nRun `candidates.sh`.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 0 ]

  # names NEITHER -> the capability exists only as Claude-Code prose
  printf -- '---\ndescription: does a thing\n---\n\nThink hard and write it down.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 1 ]; [[ "$output" == *"reachable only from Claude Code"* ]]

  # an exemption WITH a reason is honoured
  printf -- '---\ndescription: does a thing\n---\n<!-- cli-only: wires a Claude Code settings file -->\n\nThink hard.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 0 ]

  # ...but a bare marker is refused: "cli-only" with no argument is how a real leak gets waved through
  printf -- '---\ndescription: does a thing\n---\n<!-- cli-only: -->\n\nThink hard.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 1 ]; [[ "$output" == *"NO reason"* ]]

  # and it refuses to pass VACUOUSLY when it can derive no tool names at all
  printf '\n' > "$d/plugins/companion/mcp-server/index.js"
  printf -- '---\ndescription: does a thing\n---\n\nCall the `board` tool.\n' > "$d/plugins/companion/commands/a.md"
  _cl; [ "$status" -eq 1 ]; [[ "$output" == *"vacuously"* ]]
}

@test "contract-guard: blocks contract REVERSALS and needs authoring, allows additions (R86, CLI-only)" {
  # Restored 2026-08-22 by owner decision. R86 ("satisfy the contract, never rewrite it") has been
  # prose since R100/Pass 3 retired this guard for portability — and prose is skippable: I skipped it
  # twice in one session on this very repo. Claude-Code-only by nature: MCP ships no interception
  # primitive, so this guarantee has no portable home (R100).
  local G="$ROOT/bin/contract-guard.sh" d; d="$(_tmpd)"; mkdir -p "$d/docs"; git -C "$d" init -q
  _cg() { run bash -c 'printf "%s" "$1" | "$2"' _ "$1" "$G"; }
  local req="$d/docs/requirements.yaml" needs="$d/docs/needs.yaml"

  # THE ASYMMETRY: adding is ordinary and already gated by trace.sh (a requirement naming no test
  # fails there). Removing is a reversal, and reversals are the owner's.
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$req"'","old_string":"- id: R1\n","new_string":"- id: R1\n- id: R2\n"}}'
  [ "$status" -eq 0 ]; [[ "$output" != *deny* ]]

  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$req"'","old_string":"- id: R1\n- id: R2\n","new_string":"- id: R1\n"}}'
  [[ "$output" == *deny* ]]; [[ "$output" == *"REMOVES 1 requirement"* ]]

  # a requirement whose test reference is dropped still CLAIMS to be guaranteed while nothing checks
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$req"'","old_string":"    - \"a\"\n    - \"b\"\n","new_string":"    - \"a\"\n"}}'
  [[ "$output" == *deny* ]]; [[ "$output" == *"verified_by"* ]]

  # ...but RENAMING one (same count) is the legitimate "the test moved" case and must pass
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$req"'","old_string":"    - \"old name\"\n","new_string":"    - \"new name\"\n"}}'
  [[ "$output" != *deny* ]]

  # a whole-file Write is never a considered edit
  _cg '{"tool_name":"Write","tool_input":{"file_path":"'"$req"'","content":"- id: R1\n"}}'
  [[ "$output" == *deny* ]]

  # authoring a NEED is never the model's — needs define what "useful" means
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$needs"'","old_string":"a","new_string":"b"}}'
  [[ "$output" == *deny* ]]; [[ "$output" == *"never yours to write"* ]]

  # anything else is none of its business
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$d"'/src.sh","old_string":"- id: R1\n- id: R2\n","new_string":"- id: R1\n"}}'
  [[ "$output" != *deny* ]]

  # and a per-repo `contract=off` disables it (R50)
  local enc; enc="$(printf '%s' "$(git -C "$d" rev-parse --show-toplevel)" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  mkdir -p "$CLAUDE_COMPANION_STATE_DIR/features"
  printf 'contract=off\n' > "$CLAUDE_COMPANION_STATE_DIR/features/$enc"
  _cg '{"tool_name":"Edit","tool_input":{"file_path":"'"$req"'","old_string":"- id: R1\n- id: R2\n","new_string":"- id: R1\n"}}'
  [[ "$output" != *deny* ]]
}
