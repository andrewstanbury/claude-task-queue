#!/usr/bin/env bash
# tidy — architecture checks (clean-architecture reinforcement, ZERO owner config).
#
# A circular dependency is ALWAYS a problem and needs no rules declared, so this
# surfaces import cycles that involve a file changed THIS turn. It DETECTS AND RUNS
# the project's own cycle tool (madge) rather than reinventing a cross-language
# import resolver in bash — that would be fragile (tsconfig path aliases, barrel
# files, dynamic imports) and false-alarm, the opposite of "boring & reversible",
# and false alarms train rubber-stamping. Silent when madge isn't present, outside
# a git repo, or with no cycles. Go/Rust import cycles are compiler errors the
# verification floor already catches, so they're out of scope here. Surfaced
# NON-blocking and content-deduped per session. Disable: CLAUDE_TIDY_CYCLE_CHECK=0.

# Resolve a runnable madge: project-local bin first, then PATH. Empty if absent.
_tidy_madge() {
  local root="$1"
  [ -x "$root/node_modules/.bin/madge" ] && { printf '%s' "$root/node_modules/.bin/madge"; return 0; }
  command -v madge >/dev/null 2>&1 && { printf 'madge'; return 0; }
  return 1
}

# Files changed this turn (tracked diff vs HEAD + untracked).
_tidy_arch_changed() {
  local root="$1"
  { git -C "$root" diff --name-only HEAD 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null; } | sort -u
}

# Print each import cycle (as "a → b → … → a") that includes a file changed this
# turn. Empty when madge is absent / no cycles / not a git repo.
tidy_cycles_changed() {
  local root="$1" madge changed targets d to cyc
  [ "${CLAUDE_TIDY_CYCLE_CHECK:-1}" = "0" ] && return 0
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  changed="$(_tidy_arch_changed "$root")"; [ -n "$changed" ] || return 0
  madge="$(_tidy_madge "$root")" || return 0
  to="${CLAUDE_TIDY_VERIFY_TIMEOUT:-60}"
  # Scan the common source roots that exist, else the repo. madge skips
  # node_modules by default.
  targets=""
  for d in src app lib packages components; do [ -d "$root/$d" ] && targets="$targets $d"; done
  [ -n "$targets" ] || targets="."
  # madge --circular --json → a JSON array of cycles (each an array of module
  # paths); rebuild "a → b → a" and keep only cycles mentioning a changed file.
  # shellcheck disable=SC2086
  cyc="$(cd "$root" 2>/dev/null && timeout "$to" $madge --circular --json $targets 2>/dev/null \
          | jq -r 'if type=="array" then .[] | select(length>0) | (join(" → ") + " → " + .[0]) else empty end' 2>/dev/null)"
  [ -n "$cyc" ] || return 0
  printf '%s\n' "$cyc" | while IFS= read -r line; do
    [ -n "$line" ] || continue
    printf '%s\n' "$changed" | while IFS= read -r f; do
      case "$line" in *"$(basename "$f")"*) printf '%s\n' "$line"; break ;; esac
    done
  done | sort -u
}

# A cheap, deterministic proxy for coupling DENSITY: import/require/include edges
# per source file across the repo's tracked files, as a centi-integer (edges*100/
# files). DENSITY, not raw count — a healthily growing project (more files,
# proportional imports) keeps density flat, so this only climbs when each file
# genuinely depends on more (real coupling creep). A trend signal, not a precise
# graph. Prints 0 on a non-git repo or with fewer than 5 source files (too small
# to trend meaningfully).
tidy_coupling_density() {
  local root="$1" list files edges
  git -C "$root" rev-parse >/dev/null 2>&1 || { printf 0; return 0; }
  list="$(cd "$root" 2>/dev/null && git ls-files 2>/dev/null \
          | grep -iE '\.(go|js|jsx|ts|tsx|mjs|cjs|vue|svelte|py|rb|rs|java|kt|kts|c|h|cc|cpp|hpp|cs|php|swift|scala)$')"
  [ -n "$list" ] || { printf 0; return 0; }
  files="$(printf '%s\n' "$list" | grep -c .)"
  [ "$files" -ge 5 ] || { printf 0; return 0; }
  edges="$( ( cd "$root" 2>/dev/null && printf '%s\n' "$list" | tr '\n' '\0' \
              | xargs -0 grep -hE '^[[:space:]]*(import|from|require|#include|use)[[:space:](]' 2>/dev/null ) | grep -c . )"
  printf '%s' "$(( edges * 100 / files ))"
}
