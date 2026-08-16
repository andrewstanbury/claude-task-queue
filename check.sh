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
# Lives in dev/size-lint.sh so the SUITE can exercise it (R78, same reason as doc-lint.sh) — and
# extracting it is what took THIS file back under its own warning threshold.
if out="$(dev/size-lint.sh)"; then [ -n "$out" ] && printf '%s\n' "$out"; echo "  ok"
else printf '%s\n' "$out"; failsec; fi

section "Token budget (injected artifacts stay capped — R69)"
# Every byte here is paid EVERY session in EVERY installed repo; the budget is enforced, not
# advisory (the pre-R69 STEERING silently grew to 2.5x its documented token size — a doc-only
# budget demonstrably fails). BSD wc pads output — strip whitespace before numeric use (LESSONS).
tok_fail=0
# ONE owner for the cap. It was hardcoded at three sites (the test, the FAIL message, the ok
# message); a raise that missed a message would report a number the gate no longer enforces —
# output that lies while staying green, which is this repo's own recorded failure shape.
core_cap=8500
# 8730 -> 8500 (2026-08-16, owner-decided after the audit). THE CAP RATCHETS DOWN ONLY: an
# addition to the injected core must be FUNDED BY A DELETION, never by another raise. Eight raises
# (6144->8730, +42%) had ended at 8725/8730 — five bytes of headroom. Full reasoning and the honest
# accounting of the 281B that made room: docs/adr/README.md R115. A bats case pins this constant at
# <= 8500, so raising it is a two-place deliberate act rather than a one-character nudge.
# 8576 -> 8730 (2026-08-12, owner-decided: "do it for me"). FIFTH raise, and it is a CONSCIOUS
# OVERRIDE of the note below, which said a fifth should rebuild the core instead (R55). Recording
# that it was overridden, not overlooked — the pre-commitment was written against a 384B ask, and
# what landed is 154B (~38 tokens/session) because the fix REPLACED the `Verify observably` bullet
# in place rather than adding beside it. That bullet already covered this ground and LOST, which is
# the whole argument: the owner reported four production misses (a fix never deployed, a route move
# proved by a typecheck that cannot see router strings, an approval gate whose accept path was
# declared untestable while pty.openpty() was available, a three-day-old bundle server) and TWO of
# them were already covered by that exact sentence. Replacing a line that lost beats stacking a
# fourth beside it. Scanned for the subtraction that funded raise #4 and there is none left: the
# core's wireframe / decompose-park / playtest mentions are two-tier POINTERS, and cutting a
# pointer breaks the reference. If a SIXTH is proposed, rebuild — and this time mean it.
core_b="$(awk '/injection stops here/{exit} {print}' plugins/companion/STEERING.md | wc -c | tr -d '[:space:]')"
marker_n="$(grep -c 'injection stops here' plugins/companion/STEERING.md || true)"
# Marker must appear EXACTLY once: zero → the whole doc gets injected; two+ → the awk cut
# silently truncates the core at the first occurrence while this gate keeps reading green.
if [ "${marker_n:-0}" -ne 1 ]; then
  echo "  FAIL STEERING.md: 'injection stops here' marker count is ${marker_n:-0}, must be exactly 1"; tok_fail=1; failsec
elif [ "${core_b:-0}" -gt "$core_cap" ]; then
  # 8384 -> 8576 (2026-08-09) funds the sketch-first reflex: a structural change (new seam or
  # dependency, data-model / interface change) states its interface delta + call-stack BEFORE code,
  # then slices into tasks carrying that sketch as `--context`. ~137B = ~34 tokens/session, with
  # 55B headroom. Owner-asked after reading humanlayer's "why software factories fail": tests
  # answer in seconds, bad structure bills for months, and nothing in this loop measured that.
  # Funded FIRST by 217B of duplication cut from the core in the same change — the advisory/`bin`
  # split (already in flows/_quality-bar.md N4 + the below-marker rationale), the wireframe clause
  # (already in `Run in auto`), Posture's autonomy sentence (already in `Run in auto`), the
  # ripples-wide nudge (the new reflex owns splitting), and a stale header claiming STEERING is
  # "never automatically" injected, which R105 made false when it reinstated SessionStart.
  # FOURTH raise, and recorded as a smell for the same reason the 2026-08-03 note gives: the cap
  # only works as a forcing function while it occasionally binds, and being AT it is what surfaced
  # the 217B of duplication above. If a fifth is proposed, rebuild the core instead (R55).
  # 8192 -> 8384 (2026-08-07) funds R99: `--context` alongside `--done` on a task (what's
  # load-bearing for it survives a compaction/clear, the way the acceptance test always did), and
  # decompose-park (R65) triggering on "wide to gather" as well as "risky" — a task that would need
  # broad re-exploration to scope is exactly as expensive to resume as a risky one is dangerous to
  # auto-drain. Owner-asked, after reporting rework from lost/oversized context; ~145B = ~35
  # tokens/session, funding the one mechanism that actually helps (resuming from durable state)
  # rather than a hook that can't be built here (see STEERING's on-demand rationale for why a
  # capture/PreCompact-shaped fix was rejected twice already, R58·a/R32·d4).
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
  echo "  FAIL STEERING.md injected core: ${core_b}B > ${core_cap}B"; tok_fail=1; failsec
fi
# LESSONS is two-tier like STEERING (owner-picked 2026-08-01): the cap applies to what is actually
# INJECTED, not to the file. Without the split the file was 5B under its ceiling while the process
# tells every session to append to it — so each new lesson was paid for by deleting a true one.
# Marker policed exactly as STEERING's: zero → the whole file injects (cap silently under-measured),
# two+ → the awk cut truncates at the first while this gate still reads green.
# 6144 -> 6528 (2026-08-07) funds the FOURTH BSD-sed-vs-GNU-sed incident record (R98/99's board.sh
# shipped a brace-address sed missing its required `;` before `}`, red on macOS CI only — the exact
# class this file already existed to stop repeating). ~248B = ~60 tokens/session against a trap
# that has now shipped red four times; the lesson earns its place in the injected core precisely
# because it keeps recurring.
les_n="$(grep -c 'lessons injection stops here' docs/LESSONS.md 2>/dev/null || true)"
if [ -f docs/LESSONS.md ] && [ "${les_n:-0}" -ne 1 ]; then
  echo "  FAIL docs/LESSONS.md: 'lessons injection stops here' marker count is ${les_n:-0}, must be exactly 1"; tok_fail=1; failsec
fi
for spec in "CLAUDE.md:4096" "docs/LESSONS.md:6528"; do
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
# Retirement claims (2026-08-16 audit): a requirement may not call a SHIPPED FILE retired while that
# file exists. Two of the three contradictions the audit found were exactly this, and one had been
# false for four days — an absence claim is the one sentence nothing fails when it stops being true.
ret_fail=0
if ! out="$(dev/doc-lint.sh retired docs/requirements.yaml)"; then
  printf '%s\n' "$out"; ret_fail=1; failsec
fi
[ "$ret_fail" -eq 0 ] && echo "  ok (no requirement calls a surviving file retired)"

[ "$tok_fail" -eq 0 ] && echo "  ok (STEERING core ${core_b}B/${core_cap}B; command descriptions ≤140B; arg-taking commands hinted)"

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

