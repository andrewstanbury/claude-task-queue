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

scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)
manifests=(plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json)

section "JSON valid"
for f in .claude-plugin/marketplace.json "${manifests[@]}"; do
  if jq empty "$f" 2>/dev/null; then echo "  ok   $f"; else echo "  FAIL $f"; fail=1; fi
done

section "Marketplace manifest"
if have claude; then
  if claude plugin validate . >/dev/null 2>&1; then echo "  ok"; else
    echo "  FAIL — claude plugin validate ."; claude plugin validate . 2>&1 | sed 's/^/    /'; fail=1
  fi
else
  echo "  SKIP — claude CLI not installed (run locally before publishing)"
fi

section "Version match (each plugin.json == its marketplace entry)"
vm_fail=0
for pj in plugins/*/.claude-plugin/plugin.json; do
  name=$(jq -r '.name // empty' "$pj")
  pv=$(jq -r '.version // empty' "$pj")
  mkt=$(jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .version' .claude-plugin/marketplace.json)
  if [ -z "$name" ] || [ -z "$pv" ]; then
    echo "  FAIL $pj: missing name/version"; vm_fail=1; fail=1
  elif [ -z "$mkt" ] || [ "$mkt" = "null" ]; then
    echo "  FAIL $name: no marketplace entry"; vm_fail=1; fail=1
  elif [ "$pv" != "$mkt" ]; then
    echo "  FAIL $name: plugin.json $pv != marketplace $mkt"; vm_fail=1; fail=1
  fi
done
[ "$vm_fail" -eq 0 ] && echo "  ok"

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

section "Token budget (injected artifacts stay capped — R69)"
# Every byte here is paid EVERY session in EVERY installed repo; the budget is enforced, not
# advisory (the pre-R69 STEERING silently grew to 2.5x its documented token size — a doc-only
# budget demonstrably fails). BSD wc pads output — strip whitespace before numeric use (LESSONS).
tok_fail=0
core_b="$(awk '/injection stops here/{exit} {print}' plugins/companion/STEERING.md | wc -c | tr -d '[:space:]')"
marker_n="$(grep -c 'injection stops here' plugins/companion/STEERING.md || true)"
# Marker must appear EXACTLY once: zero → the whole doc gets injected; two+ → the awk cut
# silently truncates the core at the first occurrence while this gate keeps reading green.
if [ "${marker_n:-0}" -ne 1 ]; then
  echo "  FAIL STEERING.md: 'injection stops here' marker count is ${marker_n:-0}, must be exactly 1"; tok_fail=1; fail=1
elif [ "${core_b:-0}" -gt 12288 ]; then
  echo "  FAIL STEERING.md injected core: ${core_b}B > 12288B"; tok_fail=1; fail=1
fi
for spec in "CLAUDE.md:4096" "docs/LESSONS.md:6144"; do
  f="${spec%%:*}"; cap="${spec##*:}"; [ -f "$f" ] || continue
  b="$(wc -c < "$f" | tr -d '[:space:]')"
  if [ "${b:-0}" -gt "$cap" ]; then echo "  FAIL $f: ${b}B > ${cap}B (auto-loaded/injected every session)"; tok_fail=1; fail=1; fi
done
# Command `description:` frontmatter is ALSO always-loaded injection (the whole command list rides
# every session), yet R69 never capped it — the same silent-growth class. Cap each at 140B (a label,
# not a summary of the body); ceiling with working room over the current max (116B, handoff.md), not
# reverse-engineered. Prevention > detection (N7) — keeps a paragraph from creeping back in.
for f in plugins/companion/commands/*.md; do
  d="$(awk -F'description: ' '/^description: /{print $2; exit}' "$f")"
  db="$(printf '%s' "$d" | wc -c | tr -d '[:space:]')"
  if [ "${db:-0}" -gt 140 ]; then echo "  FAIL $(basename "$f") description: ${db}B > 140B (per-session command-list injection)"; tok_fail=1; fail=1; fi
done
[ "$tok_fail" -eq 0 ] && echo "  ok (STEERING core ${core_b}B/12288B; command descriptions ≤140B)"

# NOTE: the contract-drift backstop (bin/contract-drift.sh) deliberately does NOT run here
# (R58 amended 2026-07-22): a warning on every mid-work gate run — where drift is the normal
# intermediate state — trains its own tune-out, and CI is a clean-tree no-op anyway. It runs at
# the ONE boundary where drift is real and actionable: /companion:ship-it's contract-sync step.

section "Tests (bats)"
if have bats; then
  for d in plugins/*/tests tests; do
    [ -d "$d" ] || continue
    echo "  -- $d --"
    bats --print-output-on-failure "$d" || fail=1
  done
else
  echo "  FAIL — bats not installed (required to run tests)"; fail=1
fi

section "Result"
if [ "$fail" -eq 0 ]; then echo "  PASS"; else echo "  FAILURES — see above"; fi
exit "$fail"
