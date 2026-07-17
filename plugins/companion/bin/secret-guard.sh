#!/usr/bin/env bash
# PreToolUse[Write|Edit|NotebookEdit] — the ONE enforced content gate: block a write that would
# land a hardcoded credential before it reaches disk. Native permissions scan bash *commands*, not
# file *content*, and a committed key is irreversible — so this earns a real block (exit 2). Covers
# every content-writing tool: Write/Edit (.content/.new_string) AND NotebookEdit (.new_source) — a
# tool the gate must not leave a hole for (R43).
# Everything else the companion does is steering prose (STEERING.md), never a block.
# Best-effort: any parse issue fails OPEN (allow). Disable with CLAUDE_COMPANION_SECSCAN=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && exit 0

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
content="$(printf '%s' "$in" | jq -r '.tool_input.content // .tool_input.new_string // .tool_input.new_source // empty' 2>/dev/null || true)"
path="$(printf '%s' "$in" | jq -r '.tool_input.file_path // "the file"' 2>/dev/null || true)"
[ -n "$content" ] || exit 0

# Per-repo `secret` toggle (R50) — inline read, NO lib source: this gate stays self-contained so a
# broken dependency can never make it fail open. Fail-safe: only an explicit `secret=off` in THIS
# repo's feature file disables it; any read error leaves the gate active. Keep path/encoding in sync
# with lib companion_feature_file. (Global CLAUDE_COMPANION_SECSCAN=0 above still wins for CI.)
fp="$(printf '%s' "$in" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -n "$fp" ]; then
  gr="$(git -C "$(dirname "$fp")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$gr" ] && grep -qs '^secret=off$' "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}/features/$(printf '%s' "$gr" | sed -e 's:%:%25:g' -e 's:/:%2F:g')" && exit 0
fi

# Prefix-anchored credential shapes (AWS / GitHub / Slack / Stripe / Google / private key),
# plus a placeholder-filtered generic "SECRET = '…'". High precision so false blocks are ~0.
anchored='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
generic='(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_/+.-]{12,}['"'"'"]'
placeholder='(your|example|placeholder|xxx+|<[a-z]|changeme|dummy|redacted|test[_-]?(key|token|secret))'

# Anchored vendor key shapes are near-zero false-positive → BLOCK (exit 2), the one sanctioned
# edit-breaker. The generic NAME="value" heuristic is lower-confidence and would break legitimate
# writes (`password_hint = "remember the dog"`, doc fixtures), so it only WARNS (R32) — blocking
# must fire only on evidence that's virtually never a false positive.
if printf '%s' "$content" | grep -qE "$anchored"; then
  echo "BLOCKED: $path contains what looks like a real credential (a recognised key prefix). Move it to an env var or secret store — a committed key is irreversible. (CLAUDE_COMPANION_SECSCAN=0 overrides.)" >&2
  exit 2
fi
if printf '%s' "$content" | grep -qiE "$generic" && ! printf '%s' "$content" | grep -qiE "$placeholder"; then
  echo "WARNING (not blocked): $path has a possible hardcoded secret (a name=value literal). If it's real, move it to an env var or secret store — the write proceeds regardless." >&2
fi
exit 0
