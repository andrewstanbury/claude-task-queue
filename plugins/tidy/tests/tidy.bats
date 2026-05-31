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
