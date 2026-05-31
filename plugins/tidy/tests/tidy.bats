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

# ---- TDD nudge --------------------------------------------------------------

@test "TDD: a touched Go source file with no test is nudged to add one" {
  printf 'package x\nfunc Foo() {}\n' > "$WORK/widget.go"
  run run_touch "$WORK/widget.go"
  [[ "$output" == *"widget.go has no test"* ]]
  [[ "$output" == *"add widget_test.go"* ]]
}

@test "TDD: an existing sibling test prompts extension, not creation" {
  printf 'package x\nfunc Foo() {}\n' > "$WORK/widget.go"
  printf 'package x\n' > "$WORK/widget_test.go"
  run run_touch "$WORK/widget.go"
  [[ "$output" == *"extend widget_test.go"* ]]
  [[ "$output" != *"has no test"* ]]
}

@test "TDD: editing a test file is not nudged" {
  printf 'package x\n' > "$WORK/widget_test.go"
  run run_touch "$WORK/widget_test.go"
  [ -z "$output" ]
}

@test "TDD: a generated Go file is not nudged" {
  printf '// Code generated by x. DO NOT EDIT.\npackage x\nfunc Foo() {}\n' > "$WORK/gen.go"
  run run_touch "$WORK/gen.go"
  [[ "$output" != *"TDD"* ]]
}

@test "TDD: nudges only once per file per session" {
  printf 'package x\nfunc Foo() {}\n' > "$WORK/widget.go"
  run run_touch "$WORK/widget.go"
  [[ "$output" == *"TDD"* ]]
  run run_touch "$WORK/widget.go"          # same file, same session id
  [[ "$output" != *"TDD"* ]]               # deduped
}

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
  printf '#!/usr/bin/env bash\nexit 0\n' > "$FAKEBIN/eslint"; chmod +x "$FAKEBIN/eslint"
  printf 'const ok = 1\n' > "$WORK/clean.tsx"
  run run_touch "$WORK/clean.tsx"
  [ -z "$output" ]
}

@test "web: silent when the project has no linter available" {
  command -v eslint >/dev/null 2>&1 && skip "eslint present on PATH"
  printf 'const x = 1\n' > "$WORK/y.jsx"
  run run_touch "$WORK/y.jsx"
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
  run run_standard startup                      # default budget 400
  [[ "$output" != *"decomposition candidates"* ]]
}

@test "session start: light distill is omitted on compact (token-light)" {
  export CLAUDE_TIDY_SIZE_BUDGET=5
  seq 1 12 > "$WORK/huge.txt"
  run run_standard compact
  [[ "$output" != *"decomposition candidates"* ]]
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
