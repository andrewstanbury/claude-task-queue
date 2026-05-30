#!/usr/bin/env bash
# SessionStart hook — set the clean-as-you-go standard, once per session.
#
# A standing instruction (judgment guidance a hook can't enforce): leave files
# you touch cleaner than you found them, scoped to your change. Said once, it
# governs the session at no per-prompt cost. The deterministic half — format +
# lint on every edit — is the PostToolUse hook (bin/tidy-touch.sh).

set -euo pipefail

STANDARD='[tidy] Clean-as-you-go standard for this session. When you edit a file, leave it cleaner than you found it — but ONLY within the scope of your change, never repo-wide:
- Honor the project'"'"'s own formatter and linter on files you touch, and fix what they flag (this plugin auto-formats supported files and surfaces linter findings — address them before moving on).
- Apply clean-code basics: small focused functions, clear names, no dead code, errors handled.
- Respect clean-architecture boundaries: no new cross-layer or cyclic dependencies; keep modules cohesive.
- Decompose a unit you are already editing if it has clearly outgrown its responsibility — but do not start unrelated refactors.'

jq -cn --arg c "$STANDARD" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
