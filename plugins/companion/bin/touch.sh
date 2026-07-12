#!/usr/bin/env bash
# PostToolUse[Write|Edit] — clean-as-you-touch, FORMAT-ONLY: format the file you just changed
# with the project's OWN formatter (behavior-preserving). Formatting is a mechanical *execution*,
# so it earns a hook; blast-radius and size are *judgment nudges* and live in STEERING.md now
# (R28 — hooks only for what must execute or block). Best-effort + non-blocking: any failure
# degrades to silence, never breaks the edit. Disable with CLAUDE_COMPANION_TOUCH=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_TOUCH:-1}" = "0" ] && exit 0

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
f="$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
{ [ -n "$f" ] && [ -f "$f" ]; } || exit 0
ext="${f##*.}"
has() { command -v "$1" >/dev/null 2>&1; }

# Format in place — only if the tool is installed; it reads the project's OWN config. The
# per-extension command is *invocation* a hook can't avoid (allowed, R9), not a recognition
# allowlist. Formatters are behavior-preserving, so this is a safe auto-edit.
case "$ext" in
  py)   if has ruff; then ruff format -q "$f" 2>/dev/null; elif has black; then black -q "$f" 2>/dev/null; fi ;;
  js|jsx|ts|tsx|json|css|scss|html|md|yaml|yml) has prettier && prettier --write --log-level silent "$f" 2>/dev/null ;;
  go)   has gofmt && gofmt -w "$f" 2>/dev/null ;;
  rs)   has rustfmt && rustfmt -q "$f" 2>/dev/null ;;
  sh|bash) has shfmt && shfmt -w "$f" 2>/dev/null ;;
esac
exit 0
