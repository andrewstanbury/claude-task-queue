#!/usr/bin/env bash
# tidy — coverage ratchet: make under-tested code accrue a spec as it's worked.
#
# On a legacy project without tests, the safety net is "characterize before you
# change" — pin the current behavior of a touched file with a test before editing
# it. This lib detects whether a source file has a test (by common per-language
# conventions) and drives two things: a touch-time nudge (default on) when you
# touch untested source, and an opt-in Stop gate that blocks until the touched-
# but-untested surface is characterized. Sourced alongside lib/tidy.sh (which
# provides tidy_lang_for_file / tidy_is_test_file / tidy_is_generated_go / logging).

set -uo pipefail

# Does a test plausibly exist for source file $1? 0 = yes (or unsupported type —
# don't nudge), 1 = no test found. Heuristic, per-language conventions only: sibling
# names, plus a `tests/`/`test/` dir found by walking up a few levels (so a
# consolidated test dir one or two levels above the source still counts).
tidy_has_test_for() {
  local f="$1" dir stem d g e x levels=0
  dir="$(cd "$(dirname "$f")" 2>/dev/null && pwd)" || return 0
  stem="$(basename "$f")"; stem="${stem%.*}"
  case "$f" in
    *.go|*.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.py|*.sh|*.bash) ;;
    *) return 0 ;;
  esac
  # Sibling JS/TS conventions (test.*/spec.*/__tests__) — exact, fast path.
  case "$f" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte)
      for e in test spec; do for x in js jsx ts tsx mjs cjs; do
        [ -f "$dir/${stem}.${e}.${x}" ] && return 0
      done; done
      for g in "$dir/__tests__/${stem}".*; do [ -e "$g" ] && return 0; done ;;
  esac
  # Walk up to 4 levels looking for the stem's test (sibling or under tests/).
  d="$dir"
  while [ -n "$d" ] && [ "$d" != "/" ] && [ "$levels" -lt 4 ]; do
    case "$f" in
      *.go) [ -f "$d/${stem}_test.go" ] && return 0 ;;
      *.py) for g in "$d/test_${stem}.py" "$d/${stem}_test.py" "$d/tests/test_${stem}.py" "$d/tests/${stem}_test.py"; do [ -f "$g" ] && return 0; done ;;
      *.sh|*.bash) for g in "$d/${stem}.bats" "$d/tests/${stem}.bats"; do [ -f "$g" ] && return 0; done ;;
      *) for g in "$d/tests/${stem}".* "$d/test/${stem}".*; do [ -e "$g" ] && return 0; done ;;
    esac
    d="$(dirname "$d")"; levels=$((levels + 1))
  done
  return 1
}

# Touch-time nudge: when a touched source file has no test, ask to characterize it
# first. Deduped per file per session. Empty when fine/disabled. Skips test files
# and generated code. CLAUDE_TIDY_COVERAGE=0 to disable.
tidy_coverage_nudge() {
  local file="$1" sid="${2:-}" mdir mark
  [ "${CLAUDE_TIDY_COVERAGE:-1}" = "0" ] && return 0
  [ -n "$(tidy_lang_for_file "$file")" ] || return 0
  tidy_is_test_file "$file" && return 0
  case "$file" in *.go) tidy_is_generated_go "$file" && return 0 ;; esac
  tidy_has_test_for "$file" && return 0
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/cov-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true
  printf 'coverage: %s has no test — characterize it before changing (pin its current behavior with a test, covering the dependents above) so this surface accrues a spec.' \
    "$(basename "$file")"
}

# List changed source files (vs HEAD + untracked) that have no test — the surface
# the opt-in Stop gate would require characterizing. Empty outside a git repo.
tidy_untested_changed() {
  local root="$1" f
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  {
    git -C "$root" diff --name-only HEAD 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null
  } | sort -u | while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$root/$f" ] || continue
    [ -n "$(tidy_lang_for_file "$f")" ] || continue
    tidy_is_test_file "$f" && continue
    case "$f" in *.go) tidy_is_generated_go "$root/$f" && continue ;; esac
    tidy_has_test_for "$root/$f" || printf '%s\n' "$f"
  done
}
