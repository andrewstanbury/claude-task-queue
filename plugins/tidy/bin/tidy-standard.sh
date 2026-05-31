#!/usr/bin/env bash
# SessionStart hook — set the clean-as-you-go standard, once per session.
#
# Judgment guidance a hook can't enforce: leave files you touch cleaner than you
# found them, scoped to your change. Source-aware — the full standard on a fresh
# context (startup/clear/unknown), a lean re-anchor on compact/resume where the
# model already saw it this session. The deterministic half (format + lint + TDD
# nudge on every edit) is the PostToolUse hook (bin/tidy-touch.sh).

set -uo pipefail

# Resolve symlinks so a relocated entrypoint still finds lib/ (for the size lib).
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tidy.sh
. "$PLUGIN_DIR/lib/tidy.sh"

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
src=""; cwd=""
if [ -n "$input" ]; then
  src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Bootstrap-once + drift-detect: if this project records the standard in its own
# CLAUDE.md (always loaded) and marks it "claude-companion", re-anchor in one line
# instead of re-injecting the full standard every session. Self-contained
# detection (install boundary): resolve the repo root, then grep the manual.
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
  d="$cwd"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { root="$d"; break; }
    d="$(dirname "$d")"
  done
  [ -n "$root" ] || root="$cwd"
fi
documented=0
for f in CLAUDE.md AGENTS.md docs/CLAUDE.md; do
  [ -f "$root/$f" ] && grep -q 'claude-companion' "$root/$f" 2>/dev/null && { documented=1; break; }
done

lean_msg='[tidy] (reminder) clean-as-you-go, scoped to your change: cover changes with passing tests; fix linter findings you touched; simplest design that fits; name things in the domain'"'"'s language; do not grow god-files; subtract as you add — reuse before create, delete what your change makes redundant.'

if [ "$src" = "compact" ] || [ "$src" = "resume" ]; then
  ctx="$lean_msg"
elif [ "$documented" -eq 1 ]; then
  # Quiet: the standard lives in CLAUDE.md, so re-anchor lean even on a fresh context.
  ctx='[tidy] (standard in CLAUDE.md) clean-as-you-go, scoped to your change: cover changes with passing tests; fix linter findings you touched; simplest design that fits; subtract as you add — reuse before create, delete what a change makes redundant.'
else
  ctx='[tidy] Clean-as-you-go, scoped to what you touch — ratchet, do not sweep:
- Tests are the safety net: cover the behavior you change with a passing test (write it first when it helps pin the spec). Nothing is done until the suite is green. Characterization-test legacy code before refactoring.
- Fix linter findings in code you touched (the plugin auto-formats supported files and surfaces findings); leave unrelated pre-existing issues alone.
- Clean code: small focused functions, clear names, no dead code, handled errors.
- Right-size the design to the requirement: the simplest maintainable solution, no speculative layers or patterns — let complexity earn its keep.
- Name things in the project'"'"'s own domain language (the words the product owner uses), not generic tech abstractions, so non-technical contributors can follow the code.
- Clean architecture: no new cross-layer or cyclic dependencies; do not grow a god-file — extract new logic into a focused unit.
- Subtract as you add: when a change makes code redundant, delete it; reuse an existing function/component before creating a new one; prefer the smaller surface. Net complexity should trend down over time, not only up.
- Owner may be non-technical: resolve technical findings yourself (lint, size, blast-radius; apply safe patch/minor dependency upgrades when tests cover the area) rather than escalating them. Only ask about product/outcome choices, in plain language. When you finish a unit of work, recap what changed in plain, non-technical terms.
- To make this nudge re-anchor in one line each session, record this standard in your CLAUDE.md and mark it "claude-companion".'
fi

# Light distill (auto, no manual trigger): on a fresh context, surface files over
# the size budget so decomposition candidates show up on their own — quiet unless
# there's drift. This is STATE, not policy, so it appends even in quiet mode; it's
# omitted on compact/resume (already seen) to stay token-light.
if [ "$src" != "compact" ] && [ "$src" != "resume" ]; then
  over="$(tidy_oversized_files "$root" 2>/dev/null || true)"
  if [ -n "$over" ]; then
    budget="$(tidy_size_budget)"
    n="$(printf '%s\n' "$over" | grep -c .)"
    list="$(printf '%s\n' "$over" | head -n 5 | awk -F'\t' '{printf "%s (%d), ", $2, $1}')"
    list="${list%, }"
    ctx="$ctx"$'\n\n'"[tidy] $n file(s) over the $budget-line budget — decomposition candidates: $list. Run /tidy:distill for the full prune pass."
  fi
fi

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
