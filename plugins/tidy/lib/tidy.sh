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

# ---- TDD nudge --------------------------------------------------------------

# Encourage a sibling test for a touched Go SOURCE file (test-first). Skips test
# files and generated files, and is deduped per session+file (one nudge each) so
# it stays gentle in a test-poor legacy repo — the ratchet, not a nag. Prints
# the nudge line or nothing.
#   $1 file   the edited file
#   $2 sid    session id (optional; used to dedupe per session)
tidy_tdd_nudge() {
  local file="$1" sid="${2:-}"
  [ "$(tidy_lang_for_file "$file")" = "go" ] || return 0
  case "$file" in *_test.go) return 0 ;; esac
  tidy_is_generated_go "$file" && return 0

  local mdir mark
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0                         # already nudged this file this session
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true

  local sibling; sibling="${file%.go}_test.go"
  if [ -f "$sibling" ]; then
    printf 'TDD: extend %s to cover this change before moving on.' "$(basename "$sibling")"
  else
    printf 'TDD: %s has no test — add %s covering this change (test-first).' \
      "$(basename "$file")" "$(basename "$sibling")"
  fi
}

# ---- size-vs-complexity (the auto, no-trigger size check) -------------------
#
# The line budget over which a file is a decomposition candidate. A nudge, not a
# rule — a long-but-cohesive file can be fine; the model judges size-vs-complexity.
tidy_size_budget() { printf '%s' "${CLAUDE_TIDY_SIZE_BUDGET:-400}"; }

# Per-touch (PostToolUse): if the just-edited file is over budget, return a one-
# line nudge — once per file per session (deduped like the TDD nudge), skipping
# binaries and obvious non-handwritten files. Empty when fine or disabled.
tidy_size_nudge() {
  local file="$1" sid="${2:-}" budget n mdir mark
  [ "${CLAUDE_TIDY_SIZE_CHECK:-1}" = "0" ] && return 0
  [ -f "$file" ] || return 0
  LC_ALL=C grep -Iq . "$file" 2>/dev/null || return 0       # skip binaries
  case "$file" in *.lock|*-lock.json|*.min.*|*.map|*.svg|*.snap) return 0 ;; esac
  tidy_is_generated_go "$file" && return 0
  budget="$(tidy_size_budget)"
  n="$(wc -l < "$file" 2>/dev/null || printf 0)"; n="${n//[^0-9]/}"; [ -n "$n" ] || n=0
  [ "$n" -gt "$budget" ] || return 0
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/size-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true
  printf 'size: %s is %d lines (budget %d) — if it now covers more than one responsibility, extract a focused unit.' \
    "$(basename "$file")" "$n" "$budget"
}

# Whole-project (SessionStart light distill): print "<lines>\t<path>" for each
# text file over budget, heaviest first. One wc -l pass; read-only. Empty when
# nothing is over budget or the check is disabled.
tidy_oversized_files() {
  local root="$1" budget="${2:-$(tidy_size_budget)}" listing
  [ "${CLAUDE_TIDY_SIZE_CHECK:-1}" = "0" ] && return 0
  [ -d "$root" ] || return 0
  if git -C "$root" rev-parse >/dev/null 2>&1; then
    listing="$(cd "$root" && git ls-files -z --cached --others --exclude-standard 2>/dev/null | xargs -0 wc -l 2>/dev/null)"
  else
    listing="$(cd "$root" && find . -type f -not -path '*/.git/*' -print0 2>/dev/null | xargs -0 wc -l 2>/dev/null)"
  fi
  printf '%s\n' "$listing" | awk -v b="$budget" '
    { n=$1+0; $1=""; sub(/^[ \t]+/,""); p=$0 }
    p != "total" && p != "" && n > b { printf "%d\t%s\n", n, p }
  ' | sort -rn -k1,1
}
