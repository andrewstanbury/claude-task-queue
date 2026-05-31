#!/usr/bin/env bats
#
# Tests for the charter plugin: the quality-attributes gate + source-aware
# SessionStart nudge, and charter-doctor. Faked via a temp git repo and
# CLAUDE_CHARTER_* overrides.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STANDARD="$ROOT/bin/charter-standard.sh"
  DOCTOR="$ROOT/bin/charter-doctor.sh"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  export CLAUDE_CHARTER_LOG_DIR="$(mktemp -d)"
}

teardown() { rm -rf "$(dirname "$REPO")" "$CLAUDE_CHARTER_LOG_DIR"; }

run_standard() {
  local src="${1:-startup}" json
  json="$(jq -nc --arg c "$REPO" --arg s "$src" '{cwd:$c, source:$s}')"
  printf '%s' "$json" | "$STANDARD" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "nudges to document quality attributes when none exist (startup)" {
  run run_standard startup
  [[ "$output" == *"no documented quality attributes"* ]]
}

@test "lean reminder on compact when QA is missing" {
  run run_standard compact
  [[ "$output" == *"(reminder)"* ]]
  [[ "$output" != *"no documented quality attributes"* ]]
}

@test "honor-reminder when QA is documented via QUALITY.md (startup)" {
  printf '# Quality Attributes\n- perf: p95 < 200ms\n' > "$REPO/QUALITY.md"
  run run_standard startup
  [[ "$output" == *"documents its quality attributes"* ]]
}

@test "silent on compact when QA is documented" {
  printf '# Quality Attributes\n' > "$REPO/QUALITY.md"
  run run_standard compact
  [ -z "$output" ]
}

@test "includes the orientation (CLAUDE.md) nudge on a fresh context" {
  run run_standard startup                      # QA missing
  [[ "$output" == *"record it in CLAUDE.md"* ]]
  printf '# Quality Attributes\n' > "$REPO/QUALITY.md"
  run run_standard startup                      # QA documented
  [[ "$output" == *"record it in CLAUDE.md"* ]]
}

@test "omits orientation in lean mode (token-light)" {
  run run_standard compact                      # QA missing → lean reminder only
  [[ "$output" != *"record it in CLAUDE.md"* ]]
}

@test "qa-status: missing, then documented via QUALITY.md / ADR / CLAUDE.md section" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  : > "$REPO/QUALITY.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "documented" ]

  rm "$REPO/QUALITY.md"; mkdir -p "$REPO/docs/adr"; : > "$REPO/docs/adr/0001-x.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "documented" ]

  rm -rf "$REPO/docs"; printf '## Non-functional requirements\n' > "$REPO/CLAUDE.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "documented" ]
}

@test "doctor reports QA status (missing then documented)" {
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"not documented"* ]]
  : > "$REPO/QUALITY.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"quality attributes are documented"* ]]
}

@test "roadmap-status: missing, then present via docs/ROADMAP.md" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_roadmap_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  mkdir -p "$REPO/docs"; : > "$REPO/docs/ROADMAP.md"
  run bash -c "$src"' charter_roadmap_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]

  run bash -c "$src"' charter_roadmap_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "docs/ROADMAP.md" ]
}

@test "nudges to generate a roadmap/backlog file when missing (startup)" {
  run run_standard startup
  [[ "$output" == *"docs/ROADMAP.md"* ]]
  [[ "$output" == *"backlog"* ]]
  [[ "$output" == *"git history"* ]]   # generate from git history + codebase
}

@test "surfaces the roadmap to read + reconcile when present (startup)" {
  mkdir -p "$REPO/docs"; printf '# Roadmap\n## Next\n- ship it\n' > "$REPO/docs/ROADMAP.md"
  run run_standard startup
  [[ "$output" == *"docs/ROADMAP.md"* ]]
  [[ "$output" == *"reconcile"* ]]
  [[ "$output" != *"generate"* ]]      # present → no generate instruction
}

@test "omits the roadmap nudge in lean mode (token-light)" {
  run run_standard compact                      # QA + roadmap missing → lean QA reminder only
  [[ "$output" != *"ROADMAP.md"* ]]
  [[ "$output" != *"backlog"* ]]
}

@test "doctor reports roadmap status (missing then present)" {
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"no roadmap/backlog file"* ]]
  mkdir -p "$REPO/docs"; : > "$REPO/docs/ROADMAP.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"docs/ROADMAP.md"* ]]
}

@test "SessionStart output is valid JSON with the SessionStart event name" {
  json="$(jq -nc --arg c "$REPO" '{cwd:$c, source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.hookEventName' _ "$json" "$STANDARD"
  [ "$output" = "SessionStart" ]
}
