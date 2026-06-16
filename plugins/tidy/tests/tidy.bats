#!/usr/bin/env bats
#
# Tests for the tidy plugin. Go tooling is faked via stub executables on PATH so
# the dispatch is exercised deterministically without installing goimports /
# golangci-lint (which the CI runner doesn't have either).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  TOUCH="$ROOT/bin/tidy-touch.sh"
  STANDARD="$ROOT/bin/tidy-standard.sh"
  DOCTOR="$ROOT/bin/tidy-doctor.sh"
  WORK="$(mktemp -d)"
  FAKEBIN="$(mktemp -d)"          # prepended to PATH; empty unless a test fills it
  export CLAUDE_TIDY_LOG_DIR="$WORK/log"
}

teardown() { rm -rf "$WORK" "$FAKEBIN"; }

# A goimports stub that rewrites the file (so content changes -> "formatted").
fake_goimports() {
  printf '#!/usr/bin/env bash\n[ "$1" = "-w" ] && printf "\\n// tidied\\n" >> "$2"\n' > "$FAKEBIN/goimports"
  chmod +x "$FAKEBIN/goimports"
}

# A golangci-lint stub: two findings, one for a.go and one for another file,
# to prove the hook scopes surfaced findings to the touched file.
fake_golangci() {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'echo "a.go:3:6: exported function Foo should have comment (revive)"\n'
    printf 'echo "other.go:1:1: unrelated finding (govet)"\n'
  } > "$FAKEBIN/golangci-lint"
  chmod +x "$FAKEBIN/golangci-lint"
}

# Feed tidy-touch a PostToolUse payload for $1; echo additionalContext or "".
run_touch() {
  local json
  json="$(jq -nc --arg p "$1" \
            '{tool_name:"Write", tool_input:{file_path:$p}, session_id:"sess1234abcd"}')"
  PATH="$FAKEBIN:$PATH" bash -c 'printf "%s" "$1" | "$2"' _ "$json" "$TOUCH" \
    | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

# ---- SessionStart standard --------------------------------------------------

# Run the standard hook with an explicit cwd ($WORK, a clean dir with no policy
# marker) so quiet-mode detection is deterministic. $1=source (default startup).
run_standard() {
  local src="${1:-startup}" cwd="${2:-$WORK}" json
  json="$(jq -nc --arg s "$src" --arg c "$cwd" '{source:$s, cwd:$c}')"
  printf '%s' "$json" | "$STANDARD" | jq -r '.hookSpecificOutput.additionalContext // empty'
}

@test "standard hook emits valid SessionStart JSON with the clean-as-you-go policy" {
  json="$(jq -nc --arg c "$WORK" '{cwd:$c}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.hookEventName' _ "$json" "$STANDARD"
  [ "$status" -eq 0 ]
  [ "$output" = "SessionStart" ]
  run run_standard startup
  [[ "$output" == *"Clean-as-you-go"* ]]
  [[ "$output" == *"scoped to what you touch"* ]]
}

@test "standard hook: full on startup, lean re-anchor on compact" {
  run run_standard startup
  [[ "$output" == *"ratchet, do not sweep"* ]]          # full standard
  [[ "$output" != *"(reminder)"* ]]
  run run_standard compact
  [[ "$output" == *"(reminder)"* ]]                     # lean
  [[ "$output" != *"ratchet, do not sweep"* ]]
}

@test "standard hook bakes in the subtractive prune posture (startup + lean)" {
  run run_standard startup
  [[ "$output" == *"Subtract as you add"* ]]
  [[ "$output" == *"redundant"* ]]
  [[ "$output" == *"reuse"* ]]                          # reuse before create
  run run_standard compact
  [[ "$output" == *"reuse before create"* ]]            # short form survives in lean
}

@test "standard: verification is the floor (test where it earns keep), plus simplicity + domain naming" {
  run run_standard startup
  [[ "$output" == *"Verify the behavior you change"* ]]
  [[ "$output" == *"earns its keep"* ]]                 # judicious tests, not test-everything
  [[ "$output" == *"green"* ]]                          # nothing done until green
  [[ "$output" == *"simplest design that fits"* ]]      # complexity-proportional simplicity
  [[ "$output" == *"domain language"* ]]                # ubiquitous language
  [[ "$output" == *"non-technical"* ]]                  # owner-aware posture
  [[ "$output" == *"plain language"* ]]                 # ask outcomes in plain terms
  [[ "$output" != *"failing test before changing"* ]]   # rigid test-first ritual dropped
}

@test "standard: tidy keeps boring/reversible and delegates the owner loop to charter" {
  run run_standard startup
  [[ "$output" == *"boring, reversible"* ]]                   # build-time design choice stays in tidy
  [[ "$output" == *"charter owns the owner loop"* ]]          # intent/demo/consent live in charter
  [[ "$output" != *"reversibility + cost + data-safety"* ]]   # consent line moved out of tidy
  [[ "$output" != *"demonstrate it working"* ]]               # observable demo moved out of tidy
  run run_standard compact
  [[ "$output" == *"boring & reversible"* ]]                  # short form survives in lean
  [[ "$output" == *"charter owns the owner loop"* ]]
}

@test "standard: blast-radius is the lead anchor, including coupling-at-scale" {
  run run_standard startup
  [[ "$output" == *"Blast radius first"* ]]             # the #1 principle leads
  [[ "$output" == *"smallest reach"* ]]                 # contain per-change ripple
  [[ "$output" == *"compounding debt is blast radius at scale"* ]]   # the system-trend clause
}

@test "quiet mode: standard in CLAUDE.md (marker) -> lean re-anchor + bootstrap tip when absent" {
  # not documented -> full standard carries the bootstrap tip naming the marker
  run run_standard startup
  [[ "$output" == *"claude-companion"* ]]
  # documented -> lean even on a fresh context, full standard suppressed
  printf '# CLAUDE.md\nour standard <!-- claude-companion -->\n' > "$WORK/CLAUDE.md"
  run run_standard startup
  [[ "$output" == *"standard in CLAUDE.md"* ]]
  [[ "$output" != *"ratchet, do not sweep"* ]]
}

# ---- no-op paths ------------------------------------------------------------

@test "an unsupported file type is left untouched (silent)" {
  printf 'hello\n' > "$WORK/notes.txt"
  run run_touch "$WORK/notes.txt"
  [ -z "$output" ]
}

@test "an already-clean Go test file is a silent no-op" {
  # *_test.go gets no TDD nudge; already-formatted content means no format change
  # and (no fake linter) no findings -> nothing to say.
  printf 'package x\n' > "$WORK/a_test.go"
  run run_touch "$WORK/a_test.go"
  [ -z "$output" ]
}

@test "a missing file path is ignored" {
  run run_touch "$WORK/does-not-exist.go"
  [ -z "$output" ]
}

# ---- Go format + lint -------------------------------------------------------

@test "a Go file is auto-formatted and the model is told to re-read it" {
  fake_goimports
  printf 'package x\nfunc Foo(){}\n' > "$WORK/a.go"
  run run_touch "$WORK/a.go"
  [[ "$output" == *"auto-formatted"* ]]
  [[ "$output" == *"re-read"* ]]
  grep -q '// tidied' "$WORK/a.go"          # the formatter actually ran
}

@test "linter findings are surfaced, scoped to the touched file" {
  fake_goimports
  fake_golangci
  printf 'package x\nfunc Foo(){}\n' > "$WORK/a.go"
  run run_touch "$WORK/a.go"
  [[ "$output" == *"exported function Foo should have comment"* ]]
  [[ "$output" != *"unrelated finding"* ]]   # other.go finding filtered out
}

@test "generated Go files are skipped even when tooling is present" {
  fake_goimports
  fake_golangci
  printf '// Code generated by protoc. DO NOT EDIT.\npackage x\n' > "$WORK/gen.go"
  before="$(cksum "$WORK/gen.go")"
  run run_touch "$WORK/gen.go"
  [ -z "$output" ]                            # silent
  [ "$(cksum "$WORK/gen.go")" = "$before" ]   # and untouched
}

# (The test-coverage nudge moved to the generalized coverage ratchet —
# see tests/coverage.bats.)

# ---- payload-drift canary ---------------------------------------------------

@test "a payload missing tool_input.file_path is logged as drift" {
  run bash -c 'printf "{\"tool_name\":\"Edit\",\"tool_input\":{}}" | "$1"' _ "$TOUCH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                              # stays silent
  grep -q "no tool_input.file_path" "$CLAUDE_TIDY_LOG_DIR/activity.log"
}

# ---- web edit-time linters (shift the Lighthouse audit left) ----------------

# A linter stub that reports one problem on stdout and exits 1 (eslint/stylelint
# "problems found"). $1 = tool name.
fake_web_linter() {
  printf '#!/usr/bin/env bash\necho "$1: 3:5  error  <button> has no accessible label (jsx-a11y/control-has-associated-label)"\nexit 1\n' \
    > "$FAKEBIN/$1"
  chmod +x "$FAKEBIN/$1"
}

@test "web: surfaces project eslint findings for a touched JSX file" {
  fake_web_linter eslint
  printf '<button></button>\n' > "$WORK/Button.jsx"
  run run_touch "$WORK/Button.jsx"
  [[ "$output" == *"jsx-a11y"* ]]
  [[ "$output" == *"linter findings"* ]]
}

@test "web: surfaces project stylelint findings for a touched CSS file" {
  fake_web_linter stylelint
  printf 'a{color:red}\n' > "$WORK/styles.css"
  run run_touch "$WORK/styles.css"
  [[ "$output" == *"styles.css"* ]]
  [[ "$output" == *"linter findings"* ]]
}

@test "web: silent when the linter reports no problems (exit 0)" {
  export CLAUDE_TIDY_COVERAGE=0   # isolate the linter from the coverage ratchet
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/eslint"; chmod +x "$FAKEBIN/eslint"
  printf 'const ok = 1\n' > "$WORK/clean.tsx"
  run run_touch "$WORK/clean.tsx"
  [ -z "$output" ]
}

@test "web: silent when the project has no linter available" {
  export CLAUDE_TIDY_COVERAGE=0   # isolate the linter from the coverage ratchet
  command -v eslint >/dev/null 2>&1 && skip "eslint present on PATH"
  printf 'const x = 1\n' > "$WORK/y.jsx"
  run run_touch "$WORK/y.jsx"
  [ -z "$output" ]
}

# ---- multi-stack edit-time linting (Python ruff, shell shellcheck) -----------

@test "python: surfaces project ruff findings for a touched .py file" {
  printf '#!/usr/bin/env bash\nif [ "$1" = check ]; then echo "$2:1:1: F401 [*] os imported but unused"; exit 1; fi\nexit 0\n' \
    > "$FAKEBIN/ruff"; chmod +x "$FAKEBIN/ruff"
  printf 'import os\n' > "$WORK/mod.py"
  run run_touch "$WORK/mod.py"
  [[ "$output" == *"F401"* ]]
  [[ "$output" == *"linter findings"* ]]
}

@test "python: silent when ruff reports no problems (exit 0)" {
  export CLAUDE_TIDY_COVERAGE=0   # isolate the linter from the coverage ratchet
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/ruff"; chmod +x "$FAKEBIN/ruff"
  printf 'x = 1\n' > "$WORK/clean.py"
  run run_touch "$WORK/clean.py"
  [ -z "$output" ]
}

@test "python: prefers a project virtualenv ruff over PATH" {
  mkdir -p "$WORK/proj/.venv/bin"
  printf '#!/usr/bin/env bash\n[ "$1" = check ] && { echo "$2:2:1: E701 multiple statements"; exit 1; }\nexit 0\n' \
    > "$WORK/proj/.venv/bin/ruff"; chmod +x "$WORK/proj/.venv/bin/ruff"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/ruff"; chmod +x "$FAKEBIN/ruff"   # PATH ruff = clean
  printf 'x=1\n' > "$WORK/proj/app.py"
  run run_touch "$WORK/proj/app.py"
  [[ "$output" == *"E701"* ]]                    # the venv ruff ran, not the clean PATH one
}

@test "shell: surfaces shellcheck findings for a touched .sh file" {
  printf '#!/usr/bin/env bash\necho "In %s line 2:" "$2"\necho "SC2086 Double quote to prevent globbing"\nexit 1\n' \
    > "$FAKEBIN/shellcheck"; chmod +x "$FAKEBIN/shellcheck"
  printf '#!/usr/bin/env bash\nrm $1\n' > "$WORK/run.sh"
  run run_touch "$WORK/run.sh"
  [[ "$output" == *"SC2086"* ]]
  [[ "$output" == *"linter findings"* ]]
}

@test "shell: silent when shellcheck reports no problems (exit 0)" {
  export CLAUDE_TIDY_COVERAGE=0   # isolate the linter from the coverage ratchet
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/shellcheck"; chmod +x "$FAKEBIN/shellcheck"
  printf 'echo hi\n' > "$WORK/ok.sh"
  run run_touch "$WORK/ok.sh"
  [ -z "$output" ]
}

# ---- size-vs-complexity (automatic, no manual trigger) ----------------------

@test "size: a touched file over budget is flagged for decomposition (any language)" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/big.md"
  run run_touch "$WORK/big.md"
  [[ "$output" == *"big.md is 12 lines"* ]]
  [[ "$output" == *"extract a focused unit"* ]]
}

@test "size: nudges at most once per file per session, and stays under budget silently" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/big.txt"
  run run_touch "$WORK/big.txt"
  [[ "$output" == *"big.txt is 12 lines"* ]]
  run run_touch "$WORK/big.txt"                 # same file, same session
  [[ "$output" != *"is 12 lines"* ]]            # deduped
  printf 'a\nb\n' > "$WORK/small.txt"
  run run_touch "$WORK/small.txt"
  [[ "$output" != *"lines (budget"* ]]          # under budget → silent
}

@test "size: test files are exempt (suites legitimately grow)" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/widget_test.go"
  run run_touch "$WORK/widget_test.go"
  [[ "$output" != *"is 12 lines"* ]]
  seq 1 12 > "$WORK/suite.bats"
  run run_touch "$WORK/suite.bats"
  [[ "$output" != *"is 12 lines"* ]]
}

@test "size: CLAUDE_TIDY_SIZE_CHECK=0 disables the touch nudge" {
  export CLAUDE_TIDY_SIZE_BUDGET=5 CLAUDE_TIDY_SIZE_CHECK=0
  seq 1 12 > "$WORK/big.txt"
  run run_touch "$WORK/big.txt"
  [[ "$output" != *"is 12 lines"* ]]
}

@test "session start auto-surfaces files over the size budget (light distill)" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/huge.txt"
  run run_standard startup
  [[ "$output" == *"over the 5-line budget"* ]]
  [[ "$output" == *"huge.txt"* ]]
  [[ "$output" == *"decomposition candidates"* ]]
}

@test "session start stays quiet about size when nothing is over budget" {
  printf 'a\nb\n' > "$WORK/small.txt"
  run run_standard startup                      # default budget 300
  [[ "$output" != *"decomposition candidates"* ]]
}

@test "session start: light distill is omitted on compact (token-light)" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/huge.txt"
  run run_standard compact
  [[ "$output" != *"decomposition candidates"* ]]
}

# ---- blast-radius -----------------------------------------------------------

@test "blast-radius: surfaces importers of a touched source file" {
  local repo="$WORK/br1"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'export const UserCard = () => null\n' > "$repo/UserCard.tsx"
  printf "import { UserCard } from './UserCard'\n" > "$repo/Page.tsx"
  git -C "$repo" add -A
  run run_touch "$repo/UserCard.tsx"
  [[ "$output" == *"blast-radius"* ]]
  [[ "$output" == *"Page.tsx"* ]]
}

@test "blast-radius: Go grep fallback keys on the package import path, not the basename" {
  export CLAUDE_TIDY_BLAST_GOLIST=0            # force the grep heuristic deterministically
  local repo="$WORK/gobr"; mkdir -p "$repo/pkg"; git -C "$repo" init -q
  printf 'module example.com/proj\n\ngo 1.21\n' > "$repo/go.mod"
  printf 'package pkg\nfunc F() {}\n' > "$repo/pkg/foo.go"
  printf 'package main\nimport "example.com/proj/pkg"\nfunc main() { pkg.F() }\n' > "$repo/main.go"
  git -C "$repo" add -A
  run run_touch "$repo/pkg/foo.go"
  [[ "$output" == *"blast-radius"* ]]
  [[ "$output" == *"example.com/proj/pkg"* ]]   # import path, not "foo"
  [[ "$output" == *"main.go"* ]]
}

@test "blast-radius: Go uses go list for exact importing packages when go is present" {
  # Stub `go list` so the test is deterministic without a real toolchain: package
  # example.com/proj imports example.com/proj/pkg (the touched file's package).
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [ "$1" = "list" ]; then\n'
    printf '  echo "example.com/proj example.com/proj/pkg fmt"\n'
    printf '  echo "example.com/proj/pkg fmt"\n'
    printf '  exit 0\n'
    printf 'fi\nexit 0\n'
  } > "$FAKEBIN/go"; chmod +x "$FAKEBIN/go"
  local repo="$WORK/golist"; mkdir -p "$repo/pkg"; git -C "$repo" init -q
  printf 'module example.com/proj\n\ngo 1.21\n' > "$repo/go.mod"
  printf 'package pkg\nfunc F() {}\n' > "$repo/pkg/foo.go"
  git -C "$repo" add -A
  run run_touch "$repo/pkg/foo.go"
  [[ "$output" == *"blast-radius"* ]]
  [[ "$output" == *"package(s) import example.com/proj/pkg"* ]]
  [[ "$output" == *"e.g. example.com/proj"* ]]   # the importing package, from go list
}

@test "blast-radius: go list says nothing when no package imports the touched one" {
  {
    printf '#!/usr/bin/env bash\n'
    printf 'if [ "$1" = "list" ]; then echo "example.com/proj/pkg fmt"; exit 0; fi\nexit 0\n'
  } > "$FAKEBIN/go"; chmod +x "$FAKEBIN/go"
  local repo="$WORK/golist2"; mkdir -p "$repo/pkg"; git -C "$repo" init -q
  printf 'module example.com/proj\n\ngo 1.21\n' > "$repo/go.mod"
  printf 'package pkg\nfunc F() {}\n' > "$repo/pkg/foo.go"
  git -C "$repo" add -A
  run run_touch "$repo/pkg/foo.go"
  [[ "$output" != *"blast-radius"* ]]            # go ran, nothing imports it → silent
}

@test "blast-radius: skips generic basenames" {
  local repo="$WORK/br2"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'x\n' > "$repo/index.ts"
  printf "import './index'\n" > "$repo/a.ts"
  git -C "$repo" add -A
  run run_touch "$repo/index.ts"
  [[ "$output" != *"blast-radius"* ]]
}

@test "blast-radius: matches a bare import (python) — recall for bare imports" {
  export CLAUDE_TIDY_COVERAGE=0
  local repo="$WORK/brpy"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'def f(): pass\n' > "$repo/widget.py"
  printf 'import widget\nwidget.f()\n' > "$repo/app.py"     # bare import, no quote/slash
  git -C "$repo" add -A
  run run_touch "$repo/widget.py"
  [[ "$output" == *"blast-radius"* ]]
  [[ "$output" == *"app.py"* ]]
}

@test "blast-radius: regex metachars in the basename are escaped (no over-match)" {
  export CLAUDE_TIDY_COVERAGE=0
  local repo="$WORK/brmeta"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'export const x=1\n' > "$repo/my.util.ts"          # stem 'my.util'
  printf "import './myXutil'\n" > "$repo/decoy.ts"          # '.' must be literal, not 'X'
  git -C "$repo" add -A
  run run_touch "$repo/my.util.ts"
  [[ "$output" != *"decoy.ts"* ]]
}

@test "blast-radius: doc/prose mentions don't count (tighter non-Go heuristic)" {
  local repo="$WORK/brn"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'export const Widget = 1\n' > "$repo/Widget.tsx"
  printf '# Notes\nimport Widget guidance here\n' > "$repo/NOTES.md"   # doc file — excluded
  printf 'const x = Widget + 1\n' > "$repo/consumer.tsx"               # bare word, no quote/slash
  git -C "$repo" add -A
  run run_touch "$repo/Widget.tsx"
  [[ "$output" != *"blast-radius"* ]]
}

@test "blast-radius: expanded generic-name skip (e.g. service)" {
  local repo="$WORK/brg"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'x\n' > "$repo/service.ts"
  printf "import './service'\n" > "$repo/a.ts"
  git -C "$repo" add -A
  run run_touch "$repo/service.ts"
  [[ "$output" != *"blast-radius"* ]]
}

@test "blast-radius: silent when nothing references the file, and when disabled" {
  local repo="$WORK/br3"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'export const Lonely = 1\n' > "$repo/Lonely.tsx"
  git -C "$repo" add -A
  run run_touch "$repo/Lonely.tsx"
  [[ "$output" != *"blast-radius"* ]]
  printf "import './Lonely'\n" > "$repo/uses.tsx"; git -C "$repo" add -A
  export CLAUDE_TIDY_BLAST=0
  run run_touch "$repo/Lonely.tsx"
  [[ "$output" != *"blast-radius"* ]]
}

# ---- currency / modernization ----------------------------------------------

@test "currency: surfaces nearest package.json pins (deduped per session)" {
  printf '{"dependencies":{"react":"^17.0.0"},"devDependencies":{"jest":"^26.0.0"}}\n' > "$WORK/package.json"
  printf 'hello\n' > "$WORK/notes.txt"
  run run_touch "$WORK/notes.txt"
  [[ "$output" == *"react@^17.0.0"* ]]
  [[ "$output" == *"safe (patch/minor) upgrades"* ]]
  run run_touch "$WORK/notes.txt"               # same manifest, same session
  [[ "$output" != *"react@"* ]]                 # deduped
}

@test "currency: surfaces go.mod version pins" {
  printf 'module x\n\ngo 1.19\n\nrequire (\n\tgithub.com/foo/bar v1.2.3\n)\n' > "$WORK/go.mod"
  printf 'note\n' > "$WORK/readme.txt"
  run run_touch "$WORK/readme.txt"
  [[ "$output" == *"go 1.19"* ]]
  [[ "$output" == *"safe (patch/minor) upgrades"* ]]
}

@test "currency: silent when there is no manifest, and when disabled" {
  printf 'x\n' > "$WORK/lonely.txt"
  run run_touch "$WORK/lonely.txt"
  [[ "$output" != *"currency:"* ]]
  printf '{"dependencies":{"react":"^17.0.0"}}\n' > "$WORK/package.json"
  export CLAUDE_TIDY_CURRENCY=0
  run run_touch "$WORK/lonely2.txt"
  [[ "$output" != *"currency:"* ]]
}

# ---- tidy-distill (whole-project weight report) -----------------------------

@test "distill: flags over-budget files, junk, and cruft markers (git repo)" {
  local repo="$WORK/proj"; mkdir -p "$repo"; git -C "$repo" init -q
  printf 'package main\n' > "$repo/small.go"
  printf 'a\nb\nc\nd\ne\nf\n# TODO: trim\n' > "$repo/big.txt"
  : > "$repo/scratch.bak"
  git -C "$repo" add -A
  run env CLAUDE_TIDY_SIZE_BUDGET=5 bash "$ROOT/bin/tidy-distill.sh" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"weight report"* ]]
  [[ "$output" == *"big.txt"* ]]
  [[ "$output" == *"over budget"* ]]
  [[ "$output" == *"scratch.bak"* ]]             # junk artefact
  [[ "$output" == *"TODO/FIXME/HACK/XXX"* ]]
  [[ "$output" == *"subtractive pass"* ]]        # hands off to model judgment
}

@test "distill: works on a non-git directory (find fallback), exits 0" {
  local dir="$WORK/plain"; mkdir -p "$dir"
  printf 'x\ny\n' > "$dir/a.txt"
  run bash "$ROOT/bin/tidy-distill.sh" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"weight report"* ]]
  [[ "$output" == *"a.txt"* ]]
}

@test "distill: empty repo reports zero files and exits 0" {
  local repo="$WORK/empty"; mkdir -p "$repo"; git -C "$repo" init -q
  run bash "$ROOT/bin/tidy-distill.sh" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0 text files"* ]]
}

@test "distill: surfaces the complexity surface (deps + top-level areas, YAGNI note)" {
  local repo="$WORK/cx"; mkdir -p "$repo/src" "$repo/lib"; git -C "$repo" init -q
  printf '{"dependencies":{"react":"^18"},"devDependencies":{"jest":"^29","eslint":"^8"}}\n' > "$repo/package.json"
  printf 'a\n' > "$repo/src/a.js"; printf 'b\n' > "$repo/lib/b.js"
  git -C "$repo" add -A
  run bash "$ROOT/bin/tidy-distill.sh" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Complexity surface"* ]]
  [[ "$output" == *"dependencies: 3"* ]]        # 1 dep + 2 devDeps
  [[ "$output" == *"top-level areas:"* ]]        # src + lib counted (package.json is a root file)
  [[ "$output" == *"YAGNI"* ]]                   # burden of proof on complexity
}

# ---- tidy-doctor ------------------------------------------------------------

@test "doctor exits 0 (no hard failure) and reports OK" {
  # jq + bash are always present, so there's no hard FAIL regardless of the Go
  # toolchain — don't assume gofmt is absent (it ships with Go on most systems).
  run "$DOCTOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"OK — tidy can run here."* ]]
}

@test "doctor reports goimports as the formatter when it's on PATH" {
  fake_goimports
  run env PATH="$FAKEBIN:$PATH" "$DOCTOR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"formatter: goimports"* ]]   # goimports preferred over gofmt
}

# ---- state pruning (no cruft accumulation) ----------------------------------

@test "prune: removes stale dedup/verify state, keeps recent" {
  export CLAUDE_TIDY_LOG_DIR="$WORK/state"
  mkdir -p "$WORK/state/nudged" "$WORK/state/verify"
  : > "$WORK/state/nudged/recent"
  : > "$WORK/state/verify/old"
  touch -d '10 days ago' "$WORK/state/verify/old" 2>/dev/null || skip "touch -d unsupported"
  src='. "$1/lib/tidy.sh";'
  run bash -c "$src"' tidy_prune_state' bash "$ROOT"
  [ "$status" -eq 0 ]
  [ -f "$WORK/state/nudged/recent" ]                  # recent kept
  [ ! -f "$WORK/state/verify/old" ]                   # stale swept
}

@test "session start light-distill exempts test files too (consistent with the touch nudge)" {
  local repo="$WORK/ld"; mkdir -p "$repo"
  seq 1 12 > "$repo/big.bats"                          # over budget, but a test file
  seq 1 12 > "$repo/src.go"                            # over budget, real source
  export CLAUDE_TIDY_SIZE_BUDGET=5
  run run_standard startup "$repo"
  [[ "$output" == *"src.go"* ]]
  [[ "$output" != *"big.bats"* ]]
}
