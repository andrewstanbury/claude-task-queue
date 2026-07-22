#!/usr/bin/env bash
# contract-drift.sh — the living-contract backstop (R58).
#
# Guarantees the UX/quality-attribute contract can't rot *silently*: it flags when behaviour-
# defining files changed but no contract doc did. The PREVENTION is the STEERING "contract reflex"
# (move the contract doc in the same turn as the change); this is the DETECTION net for when that
# judgment was skipped — a backstop, deliberately advisory (a warning, exit 0), NOT a hard gate:
# most code changes legitimately don't touch the contract, so blocking would false-positive into
# uselessness and get disabled. `/companion:ship-it` calls it at the ship boundary — deliberately
# NOT every gate run (tune-out; R58 amended 2026-07-22). The model reads the warning and confirms
# the contract still holds.
#
# Generic (N2/R9): no language/framework allowlist. "Behaviour" = any changed tracked/untracked
# file that is NOT documentation (not under a docs/ dir) and not release noise. "Contract" = the
# tunable doc set (companion's docs/flows/ + docs/INVARIANTS.md by default — R62 flow pages replaced
# UX.md/NFR.md). An entry is matched as an exact file OR a directory prefix, so `docs/flows` covers
# every flow page. Both are overridable so the check fits any repo's convention.
#
# Usage: contract-drift.sh [ref]      (ref defaults to HEAD — compares the working tree to it)
#   CONTRACT_DRIFT_DOCS="a.md b.md"   override the contract doc set (space-separated, repo-relative)
# Best-effort: no git / not a repo / any error → exit 0 saying nothing.
set -uo pipefail
command -v git >/dev/null 2>&1 || exit 0
git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0

ref="${1:-HEAD}"
docs="${CONTRACT_DRIFT_DOCS:-docs/flows docs/INVARIANTS.md}"

# Changed files = tracked diff vs the ref  +  untracked-but-not-ignored (new code/docs).
changed="$(
  { git diff --name-only "$ref" 2>/dev/null
    git ls-files --others --exclude-standard 2>/dev/null; } | sort -u
)"
[ -n "$changed" ] || exit 0                    # clean tree → nothing to check

contract_touched=0 behaviour=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  # Is this a contract doc? Match an exact file OR a directory prefix (docs/flows → any flow page).
  for d in $docs; do case "$f" in "$d"|"$d"/*) contract_touched=1; continue 2 ;; esac; done
  # Documentation and release noise are never "behaviour".
  case "$f" in
    docs/*|*/docs/*)                 continue ;;
    README*|*/README*|CHANGELOG*|*/CHANGELOG*|LICENSE*|*/LICENSE*) continue ;;
    *.lock|*-lock.json|*.lockb)      continue ;;
  esac
  behaviour="$behaviour  $f"$'\n'
done <<EOF
$changed
EOF

# Drift only when behaviour moved AND the contract stayed still.
if [ -n "$behaviour" ] && [ "$contract_touched" -eq 0 ]; then
  printf 'contract-drift: behaviour changed but no contract doc (%s) did — confirm the UX/quality-attribute contract still holds, or update it:\n' "$docs"
  printf '%s' "$behaviour"
fi
exit 0
