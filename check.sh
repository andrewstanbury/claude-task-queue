#!/usr/bin/env bash
# One-command check — the single source of truth for what this repo enforces.
#
# CI (.github/workflows/ci.yml) provisions every tool and runs THIS script, so
# "green locally" == "green in CI", except that tools you don't have installed
# locally are SKIPPED with a note (CI has them all and is authoritative).
# Exits non-zero on any failure.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
shopt -s nullglob

fail=0
have()    { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$1"; }

scripts=(check.sh flow.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)
manifests=(plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json)

section "JSON valid"
for f in .claude-plugin/marketplace.json "${manifests[@]}"; do
  if jq empty "$f" 2>/dev/null; then echo "  ok   $f"; else echo "  FAIL $f"; fail=1; fi
done

section "ShellCheck"
if have shellcheck; then
  # SC1091: libs are sourced by a computed path at runtime — expected.
  if shellcheck -e SC1091 "${scripts[@]}"; then echo "  ok"; else fail=1; fi
else
  echo "  SKIP — shellcheck not installed (CI runs it)"
fi

section "Secret scan"
if have gitleaks; then
  if gitleaks detect --source . --no-git --redact; then echo "  ok"; else fail=1; fi
else
  echo "  SKIP — gitleaks not installed (CI runs it)"
fi

section "File size (<= 300 lines; decompose only when this fires)"
size_fail=0
for f in "${scripts[@]}"; do
  n=$(wc -l < "$f")
  if [ "$n" -gt 300 ]; then echo "  FAIL $f: $n > 300"; size_fail=1; fail=1; fi
done
[ "$size_fail" -eq 0 ] && echo "  ok"

section "Tests (bats)"
if have bats; then
  for d in plugins/*/tests tests; do
    [ -d "$d" ] || continue
    echo "  -- $d --"
    bats "$d" || fail=1
  done
else
  echo "  FAIL — bats not installed (required to run tests)"; fail=1
fi

section "Result"
if [ "$fail" -eq 0 ]; then echo "  PASS"; else echo "  FAILURES — see above"; fi
exit "$fail"
