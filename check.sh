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

scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)
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

# The two platform traps live in dev/portability-lint.sh so the SUITE can exercise them (R78,
# same reason as doc-lint.sh). Inline here they had declared mutations and no tests, and the
# mutation gate correctly reported them as HOLES.
section "Portability lint (SC2015 · GNU-only regex escapes)"
if out="$(dev/portability-lint.sh all "${scripts[@]}")"; then echo "  ok (none unmarked)"
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
size_fail=0
for f in "${scripts[@]}"; do
  n=$(wc -l < "$f")
  if [ "$n" -gt 300 ]; then echo "  FAIL $f: $n > 300"; size_fail=1; failsec; fi
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
  echo "  FAIL STEERING.md: 'injection stops here' marker count is ${marker_n:-0}, must be exactly 1"; tok_fail=1; failsec
elif [ "${core_b:-0}" -gt 8192 ]; then
  # 7808 -> 8192 (2026-08-03). THIRD raise in one day, which is itself a smell and is recorded as
  # one. It funds scoping the closing verdict to the agent's OWN work: unscoped, it drifted into
  # apportioning blame, and the owner was told "you should have suggested this two attempts ago"
  # for a miss that was entirely the agent's. That inverts the arrangement — it makes the owner
  # responsible for supervising errors they are paying not to have. Cutting a rule that stops the
  # product insulting its user, to protect a byte count, would be the wrong trade in any budget.
  # 7360 -> 7808 (2026-08-03, same incident, second pass). The first rule was insufficient and the
  # owner said so: they had CONFIRMED the innocent component twice and it kept being re-opened, and
  # the true culprit was infrastructure CLAUDE had built wrong — trusted precisely because it was
  # ours. Neither is a timeline problem, so two rules were added: suspect your own recent work
  # first, and treat an owner confirmation as closing a hypothesis. Rework is the failure this
  # product exists to prevent; paying ~110 tokens/session to attack its most expensive form is the
  # trade this budget is FOR.
  # 7040 -> 7360 (2026-08-03) funds "debug the TIMELINE before the subsystem", owner-asked after a
  # real incident: days lost to an Apple-login config hunt whose actual cause was a recent AWS
  # change. ~80 tokens/session against a failure that cost days, and the owner chose the ALWAYS
  # INJECTED form over an on-demand command precisely because the moment you need it is the moment
  # you are already committed to a wrong hypothesis and would never type the command.
  # 12288 -> 6144 -> 6656 -> 7040. The 7040 move (2026-08-02) funds fusing the two posture
  # reflexes: the owner reported for the SECOND time (cf. R80, 2026-07-29) that recommendations
  # arrive only when asked and the honest read lands as a closing verdict AFTER the choice. R80
  # split "options" and "verdict" into separate reflexes, which is what produced that symptom, so
  # the honest read now attaches to the pick itself. ~384B = ~95 tokens/session, paid to fix the
  # product's core promise; compressing it away instead would be the documented anti-pattern below.
  # 12288 -> 6144 when the core was cut 11097B -> 5919B, then 6144 -> 6656 once a devil's-advocate
  # pass proved that 5919B core had silently DROPPED EIGHT BEHAVIOURAL RULES. The old cap was
  # calibrated against a defective measurement, so defending it meant compressing real instructions
  # to protect a number derived from bad data — which is how the rules got lost in the first place.
  # This is still a 40% cut from 11097B, with the eight restored and ~380B of honest headroom.
  # A cap should track what the content genuinely needs; it stops being a budget the moment it
  # starts deciding what the content is allowed to say.
  echo "  FAIL STEERING.md injected core: ${core_b}B > 8192B"; tok_fail=1; failsec
fi
# LESSONS is two-tier like STEERING (owner-picked 2026-08-01): the cap applies to what is actually
# INJECTED, not to the file. Without the split the file was 5B under its ceiling while the process
# tells every session to append to it — so each new lesson was paid for by deleting a true one.
# Marker policed exactly as STEERING's: zero → the whole file injects (cap silently under-measured),
# two+ → the awk cut truncates at the first while this gate still reads green.
les_n="$(grep -c 'lessons injection stops here' docs/LESSONS.md 2>/dev/null || true)"
if [ -f docs/LESSONS.md ] && [ "${les_n:-0}" -ne 1 ]; then
  echo "  FAIL docs/LESSONS.md: 'lessons injection stops here' marker count is ${les_n:-0}, must be exactly 1"; tok_fail=1; failsec
fi
for spec in "CLAUDE.md:4096" "docs/LESSONS.md:6144"; do
  f="${spec%%:*}"; cap="${spec##*:}"; [ -f "$f" ] || continue
  # Measure what session-start actually injects (same awk, same fail-open) — not the whole file.
  b="$(awk '/lessons injection stops here/{exit} {print}' "$f" | wc -c | tr -d '[:space:]')"
  if [ "${b:-0}" -gt "$cap" ]; then echo "  FAIL $f: ${b}B injected > ${cap}B (injected every session)"; tok_fail=1; failsec; fi
done
# Command contract (R75) lives in dev/command-lint.sh so the SUITE can exercise it — inline here
# it had declared mutations and nothing that could redden them (same reason as doc-lint.sh).
if out="$(dev/command-lint.sh)"; then :; else printf '%s\n' "$out"; tok_fail=1; failsec; fi
# Ledger evidence lint — also in dev/doc-lint.sh, same reason (R78).
led_fail=0
if ! out="$(dev/doc-lint.sh ledger docs/adr/PROVENANCE.md)"; then
  printf '%s\n' "$out"; led_fail=1; failsec
fi
[ "$led_fail" -eq 0 ] && echo "  ok (ledger measurements cite their evidence)"

[ "$tok_fail" -eq 0 ] && echo "  ok (STEERING core ${core_b}B/8192B; command descriptions ≤140B; arg-taking commands hinted)"

# NOTE: the contract-drift backstop (bin/contract-drift.sh) deliberately does NOT run here
# (R58 amended 2026-07-22): a warning on every mid-work gate run — where drift is the normal
# intermediate state — trains its own tune-out, and CI is a clean-tree no-op anyway. It runs at
# the ONE boundary where drift is real and actionable: /companion:ship-it's contract-sync step.

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

