#!/usr/bin/env bash
# SessionStart hook — set the clean-as-you-go standard, once per session.
#
# A standing instruction (judgment guidance a hook can't enforce): leave files
# you touch cleaner than you found them, scoped to your change. Said once, it
# governs the session at no per-prompt cost. The deterministic half — format +
# lint on every edit — is the PostToolUse hook (bin/tidy-touch.sh).

set -euo pipefail

STANDARD='[tidy] Clean-as-you-go standard for this session. Improve code as you touch it, but ONLY within the scope of your change — ratchet, do not sweep:
- Test-first (TDD): before changing logic, add or extend a failing test for the new behavior, then make it pass; ensure what you changed is covered. In legacy code, write a characterization test before refactoring.
- Honor the project'"'"'s formatter and linter on files you touch (this plugin auto-formats supported files and surfaces findings). Treat findings in code you touched as must-fix; leave unrelated pre-existing issues alone.
- Clean code: small focused functions, clear names, no dead code, errors handled.
- Clean architecture: no new cross-layer or cyclic dependencies; keep modules cohesive; do not grow a god-file — extract new logic into a focused unit rather than appending to a bloated one.'

jq -cn --arg c "$STANDARD" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
