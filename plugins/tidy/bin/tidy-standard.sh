#!/usr/bin/env bash
# SessionStart hook — set the clean-as-you-go standard, once per session.
#
# Judgment guidance a hook can't enforce: leave files you touch cleaner than you
# found them, scoped to your change. Source-aware — the full standard on a fresh
# context (startup/clear/unknown), a lean re-anchor on compact/resume where the
# model already saw it this session. The deterministic half (format + lint + TDD
# nudge on every edit) is the PostToolUse hook (bin/tidy-touch.sh).

set -euo pipefail

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
src=""
[ -n "$input" ] && src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"

case "$src" in
  compact|resume)
    ctx='[tidy] (reminder) clean-as-you-go, scoped to your change: test-first; fix linter findings in code you touched; do not grow god-files; subtract as you add — reuse before create, delete what your change makes redundant.' ;;
  *)
    ctx='[tidy] Clean-as-you-go, scoped to what you touch — ratchet, do not sweep:
- TDD: add or extend a failing test before changing logic, then make it pass, and cover what you changed. Characterization-test legacy code before refactoring.
- Fix linter findings in code you touched (the plugin auto-formats supported files and surfaces findings); leave unrelated pre-existing issues alone.
- Clean code: small focused functions, clear names, no dead code, handled errors.
- Clean architecture: no new cross-layer or cyclic dependencies; do not grow a god-file — extract new logic into a focused unit.
- Subtract as you add: when a change makes code redundant, delete it; reuse an existing function/component before creating a new one; prefer the smaller surface. Net complexity should trend down over time, not only up.' ;;
esac

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
