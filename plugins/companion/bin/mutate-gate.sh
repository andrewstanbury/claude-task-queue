#!/usr/bin/env bash
# mutate-gate.sh — THE MUTATION GATE (R78). Extracted from check.sh 2026-08-01: fixing it pushed
# that file past the 300-line guard, and — as with doc-lint.sh, da-gate.sh and hook-budget.sh —
# living in bin/ is what lets the SUITE exercise it. A gate whose whole job is proving tests can
# fail spent its life untested, and shipped two defects that made it certify coverage it had
# never observed. Invoked as `./check.sh --mutate [file...]`; runnable standalone.
# Args: optional file filter — only mutations targeting those paths run.
#
# A green suite proves the tests pass, not that they CAN fail. Three fixtures in one session were
# vacuous — each masked by another rule it also tripped — and every one hid a real defect. This
# mode applies each declared mutation to the enforced core and asserts the suite goes RED. A
# mutation that stays green is a hole: a test that cannot fail. CI-only by design; it costs a full
# suite run per mutation, so it is never part of the default gate.

mfile="plugins/companion/tests/mutations.txt"
[ -f "$mfile" ] || { echo "no $mfile"; exit 2; }
# Optional file filter: `--mutate <file>...` runs ONLY the mutations targeting those files, so a
# ship can afford to check the files it actually touched. The full set is ~9 minutes, which is why
# it is CI-only — and that is exactly how a pattern stale-ed by the commit that changed its target
# reached main (3.24.2). Bounded per-file, it becomes affordable pre-push.
# NO shift here. `check.sh --mutate` already drops its own flag before exec'ing this script; the
# shift that used to live here (when the code was INSIDE check.sh) then ate the FIRST filter path,
# so every `--mutate <file>` silently ran the whole 31-mutation set — ~35 minutes instead of ~2,
# which is what made every local filtered run look like a hang. CI never noticed: it passes no
# filter, so the bug was invisible to the one place that runs this gate on every push.
mfilter=("$@")
command -v bats >/dev/null 2>&1 || { echo "  SKIP — bats not installed"; exit 0; }
# RESTORE ON ANY EXIT. This mutates the live working tree — including `secret-guard.sh`, a hook
# that is ACTIVE in this repo. Without a trap, one Ctrl-C leaves the secret gate disabled and a
# mutated file staged by the next `git add -A` (R7 must never fail open). Belt and braces: the
# trap restores, and `.gitignore` covers `*.mutbak` so a stray one can never be committed.
# shellcheck disable=SC2329,SC2317  # invoked via the trap below, not by name.
# BOTH codes: local shellcheck 0.11 flags SC2329, CI's older build flags SC2317 for the same
# function — a version split that has now shipped red CI twice (cf. SC2015 in LESSONS).
_mut_restore() {
  # NOT `find plugins` — mutations target check.sh at the repo root too, and scoping the restore
  # to plugins/ left check.sh mutated after an interrupted run (found by a real timeout).
  find . -name '*.mutbak' -print0 2>/dev/null |
    while IFS= read -r -d '' b; do mv -f "$b" "${b%.mutbak}"; done
}
# A run is COMPLETE when its TAP plan and its result lines both match the calibrated count.
# ERE, not BRE: `\|` alternation is a GNU extension BSD reads literally (LESSONS).
# shellcheck disable=SC2329,SC2317  # called above; some shellcheck builds miss indirect use.
_mut_complete() {  # $1 rc · $2 output · $3 expected test count
  local plan res
  [ "$1" -ne 0 ] || return 1
  plan="$(printf '%s\n' "$2" | sed -n 's/^1\.\.\([0-9][0-9]*\)$/\1/p' | head -1)"
  res="$(printf '%s\n' "$2" | grep -cE '^(ok|not ok) ')"
  [ "$plan" = "$3" ] && [ "$res" = "$3" ] || return 1
  printf '%s\n' "$2" | grep -q '^not ok'
}
trap '_mut_restore' EXIT INT TERM HUP
# CALIBRATE FIRST. Every verdict below is "did the suite go red?", which is meaningless unless we
# know what a COMPLETE run looks like. `bats --count` enumerates without executing; on a suite it
# cannot parse it emits TAP instead of a number, so this also catches a broken .bats file BEFORE
# any mutation runs — the hole a devil's-advocate pass found in the first version of this fix,
# where a single syntax error made every mutation report "caught" and the gate exit 0.
# ONE RUN AT A TIME, per tree. This gate mutates LIVE enforced-core files; two concurrent runs
# restore each other's *.mutbak and leave a file MUTATED behind. That is not theoretical — it
# happened here, leaving doc-lint.sh with BOM-stripping disabled (a gate failing OPEN) and
# ship.sh unable to see untracked critical paths, both sitting in the working tree ready to be
# committed. `git status` was the only thing that revealed it.
_mut_lock="${TMPDIR:-/tmp}/companion-mutate-$(printf '%s' "$PWD" | cksum | cut -d' ' -f1).lock"
if ! mkdir "$_mut_lock" 2>/dev/null; then
  echo "  FAIL another --mutate run holds $_mut_lock — concurrent runs corrupt each other's"
  echo "       backups and can leave enforced core MUTATED. Wait, or remove the dir if stale."; exit 2
fi
trap 'rmdir "$_mut_lock" 2>/dev/null; _mut_restore' EXIT INT TERM HUP
expect="$(bats --count plugins/companion/tests 2>/dev/null | tr -d '[:space:]')"
case "${expect:-}" in ''|*[!0-9]*) expect=0 ;; esac
if [ "$expect" -lt 2 ]; then
  echo "  FAIL cannot enumerate the suite (bats --count gave '${expect}') — a gate that cannot"
  echo "       count its own tests cannot certify anything about them"; exit 2
fi
# THE BASELINE MUST BE GREEN. Every verdict below is "did the suite go RED?" — which measures
# nothing if it was already red. One pre-existing failure makes EVERY mutation report "caught",
# and that is the most dangerous reading this gate can produce: a clean bill of health for
# coverage it never demonstrated. Costs one suite run; the alternative is a lie.
bout="$(bats plugins/companion/tests 2>&1)"; brc=$?
if [ "$brc" -ne 0 ]; then
  echo "  FAIL the suite is ALREADY RED before any mutation — every mutation would report"
  echo "       'caught' for a failure it did not cause. Fix the suite, then measure."
  printf '%s\n' "$bout" | grep '^not ok' | head -5 | sed 's/^/        | /'
  exit 2
fi
holes=0; errs=0; ran=0; keep=0; want=""
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  tgt="${line%%::*}"; tmp="${line#*::}"; sedscript="${tmp%%::*}"; what="${tmp#*::}"
  [ -f "$tgt" ] || { echo "  SKIP (missing) $tgt"; continue; }
  if [ "${#mfilter[@]}" -gt 0 ]; then
    keep=0; for want in "${mfilter[@]}"; do [ "$want" = "$tgt" ] && keep=1; done
    [ "$keep" = 1 ] || continue
  fi
  cp "$tgt" "$tgt.mutbak"
  if ! sed -i.bak "$sedscript" "$tgt" 2>/dev/null; then
    mv "$tgt.mutbak" "$tgt"; rm -f "$tgt.bak"
    echo "  FAIL mutation did not apply — the sed script is stale: $what"; holes=$((holes+1)); continue
  fi
  rm -f "$tgt.bak"
  if cmp -s "$tgt" "$tgt.mutbak"; then
    mv "$tgt.mutbak" "$tgt"
    echo "  FAIL mutation matched NOTHING (stale pattern): $what"; holes=$((holes+1)); continue
  fi
  ran=$((ran+1))
  # A nonzero exit is NOT proof a test failed. bats exits nonzero when it is KILLED (124, nothing
  # run) and when it cannot gather tests (a well-formed `1..1 / not ok bats-gather-tests`, also
  # nothing run). Scoring either as "caught" is how a real hole certified itself — twice. Require a
  # COMPLETE run: plan and result lines both equal to the calibrated count, with >=1 failure.
  mout="$(bats plugins/companion/tests 2>&1)"; mrc=$?
  # Retry ONLY an incomplete NONZERO run — transient load is the commonest cause. A green run is a
  # finished run: retrying it buys nothing and doubles the cost of every hole (which is how this
  # gate first blew its own timeout).
  if [ "$mrc" -ne 0 ] && ! _mut_complete "$mrc" "$mout" "$expect"; then
    mout="$(bats plugins/companion/tests 2>&1)"; mrc=$?
  fi
  if [ "$mrc" -eq 0 ]; then
    echo "  HOLE  suite stayed GREEN with: $what"; holes=$((holes+1))
  elif _mut_complete "$mrc" "$mout" "$expect"; then
    echo "  ok    caught: $what"
  else
    echo "  ERROR suite did not COMPLETE (exit $mrc, expected $expect tests) — proves nothing: $what"
    printf '%s\n' "$mout" | tail -3 | sed 's/^/        | /'
    errs=$((errs+1))
  fi
  mv "$tgt.mutbak" "$tgt"
done < "$mfile"
echo
if [ "$errs" -gt 0 ]; then printf '== Mutation result ==\n  %s INCOMPLETE RUN(S) of %s — the suite never finished, so nothing was measured\n' "$errs" "$ran"; exit 1; fi
if [ "$holes" -gt 0 ]; then printf '== Mutation result ==\n  %s HOLE(S) of %s — a test that cannot fail is not coverage\n' "$holes" "$ran"; exit 1; fi
echo "== Mutation result =="; echo "  all $ran mutations caught"; exit 0
