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
      # web: require a TEST-SHAPED name (.test./.spec./__tests__) — a same-stem
      # non-test sibling (foo.md, foo.snap) must NOT count as a test, or the
      # ratchet fails open and silently stops nudging genuinely untested code.
      *) for g in "$d/tests/${stem}".test.* "$d/tests/${stem}".spec.* \
                  "$d/test/${stem}".test.* "$d/test/${stem}".spec.* \
                  "$d/__tests__/${stem}".*; do [ -e "$g" ] && return 0; done ;;
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

# Scar-tissue hotspots — files this repo has REPEATEDLY had to FIX, by the git
# rework ratio (NOT raw churn), most-reworked first. Format: "<fixes>\t<changes>\t
# <path>". A hand mirror of charter_hotspots (the install boundary forbids a shared
# lib; tests/drift-guard.bats asserts the two stay byte-identical). Empty outside a
# git repo or with no rework signal. Word-boundaried keywords so "prefix" ≠ "fix".
tidy_hotspots() {
  local root="$1" max="${2:-5}"
  [ -d "$root" ] || return 0
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  git -C "$root" log -n 300 --no-merges --pretty=format:':C:%s' --name-only 2>/dev/null \
    | awk '
        /^:C:/ { rw = (tolower($0) ~ /(^|[^a-z])(fix|bugfix|hotfix|bug|revert|undo|rollback|regression|rework)([^a-z]|$)/) ? 1 : 0; next }
        NF     { c[$0]++; if (rw) r[$0]++ }
        END    { for (f in r) if (r[f] >= 2 && r[f] / c[f] >= 0.34) printf "%d\t%d\t%s\n", r[f], c[f], f }
      ' 2>/dev/null \
    | sort -rn -k1,1 \
    | while IFS=$'\t' read -r rf cf pf; do [ -f "$root/$pf" ] && printf '%s\t%s\t%s\n' "$rf" "$cf" "$pf"; done \
    | head -n "$max"
}

# The regression gate's target: changed source files that are BOTH untested AND
# scar-tissue hotspots — a repeatedly-fixed file, still uncharacterized, being
# touched again (the highest regression risk in the tree). Intersection of
# tidy_untested_changed and tidy_hotspots' paths. Empty when there's no such file.
tidy_untested_hotspots() {
  local root="$1" untested hot f
  untested="$(tidy_untested_changed "$root")"; [ -n "$untested" ] || return 0
  hot="$(tidy_hotspots "$root" 50 | cut -f3)"; [ -n "$hot" ] || return 0
  printf '%s\n' "$untested" | while IFS= read -r f; do
    [ -n "$f" ] || continue
    printf '%s\n' "$hot" | grep -qxF -- "$f" && printf '%s\n' "$f"
  done
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
