#!/usr/bin/env bash
# tidy-doctor — a manual, read-only health check for the tidy plugin.
#
# Validates the assumptions in CONTRACT.md against the live environment: jq, a
# Go formatter, golangci-lint, and the activity log. Run it when tidy seems to
# do nothing on a Go file. Read-only — it inspects, never formats. Exits
# non-zero only on a hard FAIL (something that stops the plugin working at all).

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/tidy.sh
. "$PLUGIN_DIR/lib/tidy.sh"

fails=0
warns=0
pass() { printf '  [PASS] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }

printf 'tidy-doctor — tidy plugin health check\n\n'

printf 'Requirements\n'
if tidy_have jq; then pass "jq present"
else fail "jq not found — the PostToolUse hook can't parse payloads without it"; fi
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then pass "bash ${BASH_VERSINFO[0]}.x"
else warn "bash ${BASH_VERSINFO[0]:-?} — Bash 4+ recommended"; fi

printf '\nGo toolchain (tidy targets Go)\n'
fmt=""
for t in goimports gofumpt gofmt; do tidy_have "$t" && { fmt="$t"; break; }; done
if [ -n "$fmt" ]; then pass "formatter: $fmt"
else warn "no Go formatter (goimports/gofumpt/gofmt) on PATH — Go files won't be auto-formatted"; fi
if tidy_have golangci-lint; then pass "golangci-lint present"
else warn "golangci-lint not on PATH — lint findings won't be surfaced (formatting still works)"; fi

printf '\nActivity log\n'
logf="$(tidy_log_file)"
if [ "${CLAUDE_TIDY_LOG_DISABLED:-}" ]; then warn "logging disabled (CLAUDE_TIDY_LOG_DISABLED set)"
elif [ -f "$logf" ]; then
  pass "log: $logf"
  printf '  last entries:\n'
  tail -n 15 "$logf" 2>/dev/null | sed 's/^/    /'
else
  warn "no log yet at $logf (written once the hook runs on a supported file)"
fi

printf '\n%d warning(s), %d failure(s).\n' "$warns" "$fails"
if [ "$fails" -gt 0 ]; then
  printf 'FAIL — see [FAIL] lines above; cross-check CONTRACT.md.\n'
  exit 1
fi
printf 'OK — tidy can run here.\n'
