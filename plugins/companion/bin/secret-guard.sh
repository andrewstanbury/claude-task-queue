#!/usr/bin/env bash
# PreToolUse[Write|Edit] — the ONE enforced content gate: block a write that would land a
# hardcoded credential before it reaches disk. Native permissions scan bash *commands*, not
# file *content*, and a committed key is irreversible — so this earns a real block (exit 2).
# Everything else the companion does is steering prose (STEERING.md), never a block.
# Best-effort: any parse issue fails OPEN (allow). Disable with CLAUDE_COMPANION_SECSCAN=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && exit 0

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
content="$(printf '%s' "$in" | jq -r '.tool_input.content // .tool_input.new_string // empty' 2>/dev/null || true)"
path="$(printf '%s' "$in" | jq -r '.tool_input.file_path // "the file"' 2>/dev/null || true)"
[ -n "$content" ] || exit 0

# Prefix-anchored credential shapes (AWS / GitHub / Slack / Stripe / Google / private key),
# plus a placeholder-filtered generic "SECRET = '…'". High precision so false blocks are ~0.
anchored='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
generic='(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_/+.-]{12,}['"'"'"]'
placeholder='(your|example|placeholder|xxx+|<[a-z]|changeme|dummy|redacted|test[_-]?(key|token|secret))'

hit=""
printf '%s' "$content" | grep -qE "$anchored" && hit="1"
if [ -z "$hit" ] && printf '%s' "$content" | grep -qiE "$generic" \
   && ! printf '%s' "$content" | grep -qiE "$placeholder"; then hit="1"; fi

if [ -n "$hit" ]; then
  echo "BLOCKED: $path appears to contain a hardcoded credential. Move it to an env var or secret store — a committed key is irreversible. (CLAUDE_COMPANION_SECSCAN=0 overrides.)" >&2
  exit 2
fi
exit 0
