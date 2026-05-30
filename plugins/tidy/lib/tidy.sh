#!/usr/bin/env bash
# tidy — support lib for the tidy-as-you-touch plugin.
#
# When you edit a file, the PostToolUse hook formats it (auto-applying only
# behavior-preserving fixes) and surfaces linter findings for the model to
# address — so an actively-worked project converges toward clean code, scoped
# to the files you touch. This lib holds the language dispatch and the Go
# handler; the bin/ entrypoints stay thin.
#
# It WRITES to your working tree (formatting), unlike a read-only plugin — so
# every operation is best-effort, behavior-preserving, scoped to the one edited
# file, and must never break the edit that triggered it.

set -uo pipefail

# ---- locations (overridable for tests) -------------------------------------

tidy_log_dir()  { printf '%s' "${CLAUDE_TIDY_LOG_DIR:-$HOME/.claude/state/tidy}"; }
tidy_log_file() { printf '%s/activity.log' "$(tidy_log_dir)"; }

# ---- helpers ---------------------------------------------------------------

tidy_have() { command -v "$1" >/dev/null 2>&1; }

# Append one best-effort log line; never fails the caller. CLAUDE_TIDY_LOG_DISABLED=1 to mute.
tidy_log() {
  [ -n "${CLAUDE_TIDY_LOG_DISABLED:-}" ] && return 0
  local event="$1" detail="${2:-}" ts dir
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '?')"
  dir="$(tidy_log_dir)"
  { mkdir -p "$dir" 2>/dev/null && printf '%s\t%s\t%s\n' "$ts" "$event" "$detail" >> "$(tidy_log_file)"; } 2>/dev/null || true
  return 0
}

# Map a path to a supported language tag, or "" (→ the hook no-ops).
tidy_lang_for_file() {
  case "$1" in
    *.go) printf 'go' ;;
    *)    printf '' ;;
  esac
}

# A Go file we must not touch: generated code carries a well-known marker.
tidy_is_generated_go() {
  head -n 10 "$1" 2>/dev/null | grep -qE '^// Code generated .* DO NOT EDIT\.$'
}

# Content fingerprint, to tell whether a formatter actually changed the file.
tidy_hash() { cksum "$1" 2>/dev/null | awk '{print $1"-"$2}'; }

# ---- Go handler ------------------------------------------------------------

# Format the touched Go file in place (behavior-preserving) and collect any
# golangci-lint findings FOR THAT FILE. Prints a tab-separated summary line:
#   "<formatted:0|1>\t<lintfindings-or-empty>"
# Prints nothing (and returns 0) when there's nothing worth saying.
tidy_handle_go() {
  local file="$1"
  [ -f "$file" ] || return 0
  if tidy_is_generated_go "$file"; then tidy_log skip "generated: $file"; return 0; fi

  local before after tool="" changed=0
  before="$(tidy_hash "$file")"
  if   tidy_have goimports; then tool=goimports; goimports -w "$file" 2>/dev/null || true
  elif tidy_have gofumpt;   then tool=gofumpt;   gofumpt   -w "$file" 2>/dev/null || true
  elif tidy_have gofmt;     then tool=gofmt;     gofmt     -w "$file" 2>/dev/null || true
  fi
  after="$(tidy_hash "$file")"
  [ -n "$tool" ] && [ "$before" != "$after" ] && changed=1

  # Lint the file's package, then keep only findings that name this file, so the
  # surfaced issues stay scoped to what was just touched. Best-effort + bounded.
  local lint="" dir base
  dir="$(dirname "$file")"; base="$(basename "$file")"
  if tidy_have golangci-lint; then
    lint="$(
      cd "$dir" 2>/dev/null || exit 0
      golangci-lint run 2>/dev/null | grep -F "$base" | head -n 20
    )"
  fi

  [ "$changed" -eq 0 ] && [ -z "$lint" ] && return 0
  tidy_log go "file=$file fmt=$tool changed=$changed lint=$( [ -n "$lint" ] && echo yes || echo no )"
  printf '%s\t%s' "$changed" "$lint"
}
