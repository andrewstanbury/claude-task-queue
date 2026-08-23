#!/usr/bin/env bash

# ── ./check.sh --mutate (R78) ────────────────────────────────────────────────────────
# The gate lives in dev/ — it verifies the plugin, it is not part of it. Delegated, not
# reimplemented, and not shipped to anyone who installs the plugin.
if [ "${1:-}" = "--mutate" ]; then
  shift
  exec "$(dirname "$0")/dev/mutate-gate.sh" "$@"
fi

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
# A red verdict MUST name its cause: this once printed "FAILURES — see above" with no FAIL line
# anywhere, then passed three times. `failsec` stamps the current section so Result can say where.
CUR="(startup)"; FAILED_SECTIONS=""
section() { CUR="$1"; printf '\n== %s ==\n' "$1"; }
failsec() { fail=1   # NOT failsec — this is the definition, and a bulk rewrite ate it once
  case ";$FAILED_SECTIONS;" in
    *";$CUR;"*) ;;
    *) FAILED_SECTIONS="${FAILED_SECTIONS}${FAILED_SECTIONS:+;}$CUR" ;;
  esac
}

# `bin/tq` has NO `.sh` extension, so `plugins/*/bin/*.sh` NEVER MATCHED IT. THE task queue (R8/R10)
# — the most-called file in the product, and the one every command and the MCP server route through
# — was invisible to ShellCheck, to portability-lint AND to the size guard below. Found 2026-08-11
# while asking why the size gate stayed green with tq at 382 lines; it had been silently growing
# (355 at the previous commit). A gate that cannot fail on the file that matters most is UN-5's
# named failure shape, and the exclusion was an accident of a filename, not a decision.
# Named explicitly rather than by widening the glob to `bin/*`: the set this iterates must stay
# something a reader can enumerate, and a bare `bin/*` would silently absorb any future non-script.
scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh plugins/*/bin/tq)
manifests=(plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json)

section "JSON valid"
for f in .claude-plugin/marketplace.json "${manifests[@]}"; do
  if jq empty "$f" 2>/dev/null; then echo "  ok   $f"; else echo "  FAIL $f"; failsec; fi
done

section "Marketplace manifest"
if have claude; then
  if claude plugin validate . >/dev/null 2>&1; then echo "  ok"; else
    echo "  FAIL — claude plugin validate ."; claude plugin validate . 2>&1 | sed 's/^/    /'; failsec
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
    echo "  FAIL $pj: missing name/version"; vm_fail=1; failsec
  elif [ -z "$mkt" ] || [ "$mkt" = "null" ]; then
    echo "  FAIL $name: no marketplace entry"; vm_fail=1; failsec
  elif [ "$pv" != "$mkt" ]; then
    echo "  FAIL $name: plugin.json $pv != marketplace $mkt"; vm_fail=1; failsec
  fi
done
[ "$vm_fail" -eq 0 ] && echo "  ok"

section "ShellCheck"
if have shellcheck; then
  # SC1091: libs are sourced by a computed path at runtime — expected.
  if shellcheck -e SC1091 "${scripts[@]}"; then echo "  ok"; else failsec; fi
else
  echo "  SKIP — shellcheck not installed (CI runs it)"
fi

# The platform traps live in dev/portability-lint.sh so the SUITE can exercise them (R78, same
# reason as doc-lint.sh). Inline here they had declared mutations and no tests, and the mutation
# gate correctly reported them as HOLES.
section "Portability lint (SC2015 · GNU-only regex escapes · bare sed -i)"
if out="$(dev/portability-lint.sh all "${scripts[@]}")"; then echo "  ok (none unmarked)"
else printf '%s\n' "$out"; failsec; fi
# ALSO over dev/ and the TESTS. A bare `sed -i` in a .bats file is what reddened macOS on 3.87.0 —
# BSD read the script as a backup suffix, the edit silently did not happen, and the test asserted
# behaviour that therefore never occurred. Scanning only the shipped scripts would have missed it,
# which is the whole reason this line exists separately from the one above.
if out="$(dev/portability-lint.sh sedi dev/*.sh dev/tests/*.bats)"; then echo "  ok (no bare sed -i in dev/ or the suite)"   # sedi-ok: this is the lint's own message
else printf '%s\n' "$out"; failsec; fi
# Fixture hygiene, scanned over the TESTS: a bare `$(mktemp -d)` leaks, and one session of leaks
# exhausted this machine's /tmp inode table.
if out="$(dev/portability-lint.sh fixtures dev/tests/*.bats)"; then echo "  ok (no leaking fixtures)"
else printf '%s\n' "$out"; failsec; fi
# A fixture pinned to a threshold the product compares against reddens CI at random (now+86400
# arrives as 86399). Broke both lanes twice in one day — see dev/portability-lint.sh.
if out="$(dev/portability-lint.sh boundary dev/tests/*.bats)"; then echo "  ok (no fixture pinned to a threshold)"
else printf '%s\n' "$out"; failsec; fi

section "Secret scan"
if have gitleaks; then
  if gitleaks detect --source . --no-git --redact; then echo "  ok"; else failsec; fi
else
  echo "  SKIP — gitleaks not installed (CI runs it)"
fi

section "File size (<= 300 lines; decompose only when this fires)"
# Lives in dev/size-lint.sh so the SUITE can exercise it (R78, same reason as doc-lint.sh) — and
# extracting it is what took THIS file back under its own warning threshold.
if out="$(dev/size-lint.sh)"; then [ -n "$out" ] && printf '%s\n' "$out"; echo "  ok"
else printf '%s\n' "$out"; failsec; fi

section "Token budget (injected artifacts stay capped — R69)"
# Lives in dev/token-budget.sh so the SUITE can exercise it (R78) — and extracting it is what took
# THIS file back under its own warning threshold, for the second time.
if out="$(dev/token-budget.sh)"; then [ -n "$out" ] && printf '%s\n' "$out"
else printf '%s\n' "$out"; failsec; fi

section "Hook budget (R81 — hooks stay O(1) in store size; MEASURED, not asserted)"
# Lives in dev/hook-budget.sh so the SUITE can exercise it (same reason as doc-lint, R78).
# Primary assertion is a SCALING RATIO, not a wall-clock cap — see that file's header for why an
# absolute-ms budget is machine-dependent and self-defeating. This is the gate that would have
# stopped the 2085ms->16108ms session-start scan (measured 8.06x, caught) from ever shipping.
if ! "$PWD/dev/hook-budget.sh"; then
  echo "  FAIL — a hook's cost grows with the task store (R81)"; failsec
fi

# Declared mutations must still APPLY. Stale patterns are this repo's most repeated defect —
# seven orphaned by extractions, three by sed-delimiter collisions — and every one was invisible
# locally, surfacing only on CI where it reddens every shard. This costs seconds, not minutes.
section "Mutation patterns still apply (no stale/orphaned declarations)"
if out="$(dev/mutate-gate.sh --validate 2>&1)"; then printf '%s\n' "$out"
else printf '%s\n' "$out"; failsec; fi

# A doc that claims something is RETIRED while the file is still shipping (R118 follow-up). This
# lint already existed and check.sh never called it — so MAP.md went on saying secret-guard.sh
# "stays retired" for three weeks after it was restored, and nothing said otherwise. A lint nobody
# runs is not a lint; it is a file that makes the repo look better tested than it is. Same class as
# the CI ceiling nothing measured and the hook budget that varied the wrong axis.
section "Retirement claims match reality (a doc cannot bury a live file)"
if out="$(dev/doc-lint.sh retired docs/MAP.md 2>&1)"; then echo "  ok (no doc buries a surviving file)"
else printf '%s\n' "$out"; failsec; fi

# The V: needs <- requirements <- tests, checked in BOTH directions. The uncomfortable one is
# test->requirement: an orphan test is a claim about the system that no requirement will own. On
# its first run it found 99 unclaimed tests and a misclassified requirement (R53 was filed as a
# principle while doc-lint enforced it with 8 cases).
section "Traceability (needs <- requirements <- tests, both directions)"
if out="$(dev/trace.sh 2>&1)"; then printf '%s\n' "$out"
else printf '%s\n' "$out"; failsec; fi

section "Tests (bats)"
if have bats; then
  # One suite, one location — the tests moved to dev/ with the gates they run (they verify the
  # plugin; they are not part of it). No glob: a loop over one fixed path is just a path.
  d=dev/tests
  if [ -d "$d" ]; then
    echo "  -- $d --"
    bats --print-output-on-failure "$d" || failsec
  else
    echo "  FAIL — $d missing"; failsec
  fi
else
  echo "  FAIL — bats not installed (required to run tests)"; failsec
fi

section "Result"
if [ "$fail" -eq 0 ]; then echo "  PASS"; else
  echo "  FAILURES in: $(printf '%s' "${FAILED_SECTIONS:-(unattributed)}" | sed 's/;/, /g')"
  echo "  (see those sections above)"
fi
exit "$fail"

