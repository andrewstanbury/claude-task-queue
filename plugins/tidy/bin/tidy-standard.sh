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

# Once per session, sweep stale per-session state so it never accumulates.
tidy_prune_state 2>/dev/null || true

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

lean_msg='[tidy] (reminder) clean-as-you-go: blast radius first — cover the dependents of what you touch; verify changed behavior (a test where it earns its keep, else types/build/run; suite green before done); subtract as you add — reuse before create, simplest fit, boring & reversible; resolve reversible findings yourself, recap in plain language (charter owns the owner loop: intent, demo, consent).'

if [ "$src" = "compact" ] || [ "$src" = "resume" ]; then
  ctx="$lean_msg"
elif [ "$documented" -eq 1 ]; then
  # Quiet: the standard lives in CLAUDE.md, so re-anchor lean even on a fresh context.
  ctx='[tidy] (standard in CLAUDE.md) clean-as-you-go, scoped to your change: blast radius first — cover the dependents of what you touch; verify changed behavior (test where it earns its keep, else types/build/run; suite green); simplest design that fits; subtract as you add — reuse before create, delete what a change makes redundant.'
else
  ctx='[tidy] Clean-as-you-go, scoped to what you touch — ratchet, do not sweep. You already know good engineering; these are the anchors that matter most here (the format/lint/size/test feedback you get as you work carries the rest):
- Blast radius first: before changing a file, know what depends on it (the touch hook surfaces dependents) and cover that affected surface with tests — no change lands without understanding what it can break. Contain ripple; prefer the change with the smallest reach. At scale, keep total coupling from climbing — one owner per concern, contracts not copies (compounding debt is blast radius at scale).
- Verify the behavior you change — a test where it earns its keep (core logic, contracts, regression-prone code), or types/build/running the app where that suffices; skip brittle ceremony tests for trivial glue. The suite must be green before you'"'"'re done (the verification hook enforces it).
- Subtract as you add: reuse before create, delete what a change makes redundant, simplest design that fits — net complexity should trend down, not up. Prefer boring, reversible, replaceable choices (architecture gets no human review here, and the owner can'"'"'t recover from an irreversible or exotic one).
- Name things in the owner'"'"'s domain language; the owner is non-technical, so resolve reversible/safe findings yourself and recap each unit of work in plain language (charter owns the owner loop — confirming intent, demonstrating the result back, and surfacing consent for consequential/irreversible actions).
- Record this in your CLAUDE.md and mark it "claude-companion" to make it re-anchor in one line each session.'
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
