#!/usr/bin/env bash
# PostToolUse[Write|Edit] — clean-as-you-touch, scoped to the file you just changed:
#   1. FORMAT it in place with the project's own formatter (behavior-preserving only).
#   2. Surface its BLAST RADIUS — other files that reference it, so ripples get covered.
#   3. Flag it when it's OVER the size budget.
# Best-effort + non-blocking: any failure degrades to silence, never breaks the edit.
# Disable with CLAUDE_COMPANION_TOUCH=0; size budget CLAUDE_COMPANION_SIZE_BUDGET (default 300).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_TOUCH:-1}" = "0" ] && exit 0

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
f="$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
{ [ -n "$f" ] && [ -f "$f" ]; } || exit 0

base="${f##*/}"; ext="${base##*.}"; stem="${base%.*}"
root="$(git -C "$(dirname "$f")" rev-parse --show-toplevel 2>/dev/null || true)"
has() { command -v "$1" >/dev/null 2>&1; }

# 1) FORMAT in place — only if the tool is installed; it reads the project's OWN config. The
# per-extension command is *invocation* a hook can't avoid (allowed), not a recognition
# allowlist. Formatters are behavior-preserving, so this is a safe auto-edit.
case "$ext" in
  py)   if has ruff; then ruff format -q "$f" 2>/dev/null; elif has black; then black -q "$f" 2>/dev/null; fi ;;
  js|jsx|ts|tsx|json|css|scss|html|md|yaml|yml) has prettier && prettier --write --log-level silent "$f" 2>/dev/null ;;
  go)   has gofmt && gofmt -w "$f" 2>/dev/null ;;
  rs)   has rustfmt && rustfmt -q "$f" 2>/dev/null ;;
  sh|bash) has shfmt && shfmt -w "$f" 2>/dev/null ;;
esac

notes=""
# 2) BLAST RADIUS — other tracked files that reference this file's stem (imports/uses). A
# basename heuristic (bounded, best-effort); a nudge to cover dependents, not a proof.
if [ -n "$root" ] && [ "${#stem}" -ge 3 ]; then
  rel="${f#"$root"/}"
  dep="$(git -C "$root" grep -lF "$stem" 2>/dev/null | grep -vxF "$rel" | head -6 || true)"
  n="$(printf '%s' "$dep" | grep -c . || true)"
  [ "${n:-0}" -gt 0 ] && notes="$notes"$'\n'"· blast radius: $n file(s) reference \`$stem\` — cover them if this rippled:"$'\n'"$(printf '%s' "$dep" | sed 's/^/    /')"
fi

# 3) SIZE — flag when over budget (a signal to split on a real seam, not just to trim).
budget="${CLAUDE_COMPANION_SIZE_BUDGET:-300}"
lines="$(wc -l < "$f" 2>/dev/null | tr -d ' ')"
[ "${lines:-0}" -gt "$budget" ] 2>/dev/null && notes="$notes"$'\n'"· size: $lines lines (> $budget) — split on a cohesion seam if one exists (not just length)."

[ -n "$notes" ] || exit 0
jq -cn --arg c "[companion] touched \`$base\`:$notes" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$c}}'
