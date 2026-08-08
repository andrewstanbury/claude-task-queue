#!/usr/bin/env bash
# check-secrets.sh — ADVISORY credential-shape scanner (R100/Pass 3). Was secret-guard.sh's
# PreToolUse hook, which BLOCKED (exit 2, deny) before a write ever reached disk — the one
# enforced content gate this plugin had. That hook is retired (docs/adr/README.md R100): nothing
# left in this plugin can deny a tool call. This is the same scanning logic, callable directly
# (CLI) or via the companion-tq MCP server's check_for_secrets tool, so a model that chooses to
# check content before a risky write still gets the same verdict — but nothing forces the call,
# and nothing stops the write if the verdict is ignored. That is the accepted cost of R100, not a
# fix for it.
#
# Unlike the old hook, this never sees Claude Code's tool_input JSON shape (there is no more
# PreToolUse dispatch across Write/Edit/NotebookEdit to cover) — it just scans whatever text it's
# given. Tool-agnostic by construction, not by extra code.
#
# Usage: check-secrets.sh [--path <path>] < content
#   exit 0, silent               — nothing suspicious
#   exit 0, "WARN: ..." on stdout — a generic name=value literal that ISN'T a known placeholder
#   exit 2, "BLOCK: ..." on stdout — an anchored, near-zero-false-positive credential shape
# Disable: CLAUDE_COMPANION_SECSCAN=0 (global) or a per-repo `secret=off` feature flag (needs --path).
set -uo pipefail

path=""
if [ "${1:-}" = "--path" ]; then path="${2:-}"; shift 2 2>/dev/null || true; fi
content="$(cat 2>/dev/null || true)"
[ -n "$content" ] || exit 0
[ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && exit 0

# Per-repo `secret=off` flag (R50) — same fail-safe-lock property as before: only an exact
# `secret=off` line disables it; any read error (missing file, wrong content) leaves it active.
gate_off() {
  [ -n "$path" ] || return 1
  local gr
  gr="$(git -C "$(dirname "$path")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$gr" ] || return 1
  grep -qs '^secret=off$' \
    "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}/features/$(printf '%s' "$gr" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
}

# Prefix-anchored credential shapes (AWS / GitHub / Slack / Stripe / Google / private key),
# plus a placeholder-filtered generic "SECRET = '...'". High precision so false BLOCKs are ~0.
anchored='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
generic='(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_/+.-]{12,}['"'"'"]'
placeholder='(your|example|placeholder|xxx+|<[a-z]|changeme|dummy|redacted|test[_-]?(key|token|secret))'

# <<< herestrings, NOT `printf ... | grep -qE` (found during R100/Pass 5 fix-forward, same class
# as dev/trace.sh's macOS break): under `pipefail`, `-q` exits the instant it finds a match, and
# for content bigger than the pipe buffer a later printf write() can land on that closed pipe and
# SIGPIPE — which flips the `if`'s truth value away from grep's own exit code. For a scanner whose
# whole contract is "never fails open" (R50/R54), that is exactly the wrong direction to be racy in.
if grep -qE "$anchored" <<< "$content"; then
  gate_off && exit 0
  echo "BLOCK: ${path:-this content} looks like it contains a real credential (a recognised key prefix). Move it to an env var or secret store before writing it — nothing will stop the write, but a committed key is irreversible. (CLAUDE_COMPANION_SECSCAN=0 overrides.)"
  exit 2
fi
if grep -qiE "$generic" <<< "$content" && ! grep -qiE "$placeholder" <<< "$content"; then
  gate_off && exit 0
  echo "WARN: ${path:-this content} has a possible hardcoded secret (a name=value literal). If it's real, move it to an env var or secret store."
fi
exit 0
