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

mfile="dev/tests/mutations.txt"
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
# --shard N/M: run every Mth declared mutation, offset N. Measured 2026-08-22: 144 mutations x
# ~85s on CI is ~3.4 HOURS serially, and on GitHub a long job ALSO blocks `gh run view --log-failed`
# for the whole run — so a red check lane could not be read until this one finished, which cost real
# time. CI matrixes 10 shards (was 6, raised 2026-08-22 when the slowest shard hit 33 min).
# These numbers go stale by simply being written down, which is why the ONE that matters — whether
# the slowest shard still fits inside R74's watch ceiling — is computed on every run instead of
# recorded here. See ci_wallclock_warn below.
# Each mutation is independent by construction, so this parallelises cleanly.
do_validate=0
if [ "${1:-}" = "--validate" ]; then do_validate=1; shift; fi
shard_n=0; shard_m=1
if [ "${1:-}" = "--shard" ]; then
  case "${2:-}" in
    [0-9]*/[0-9]*) shard_n="${2%%/*}"; shard_m="${2##*/}"; shift 2 ;;
    *) echo "usage: --shard N/M" >&2; exit 2 ;;
  esac
fi
case "$shard_m" in ''|*[!0-9]*) shard_m=1 ;; esac
[ "$shard_m" -ge 1 ] || shard_m=1
mfilter=("$@")
command -v bats >/dev/null 2>&1 || { echo "  SKIP — bats not installed"; exit 0; }
# RESTORE ON ANY EXIT. This mutates the live working tree — including `prompt-continue.sh`, the
# one hook still ACTIVE in this repo (R100/Pass 4: every other former hook, `check-secrets.sh`
# included, is advisory now, but a mutated copy left staged by accident is exactly as unwelcome).
# Without a trap, one Ctrl-C leaves a mutated file staged by the next `git add -A` (R7 must never
# fail open). Belt and braces: the trap restores, and `.gitignore` covers `*.mutbak` so a stray one
# can never be committed.
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
  [ "$plan" = "$3" ] && [ "$res" = "$3" ] || return 1   # sc2015-ok: "unless both held" is the intent
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
# LIVENESS, not just presence (2026-08-16). The lock was a bare directory removed only by the EXIT
# trap, so a run killed with SIGKILL — which runs no trap — left a lock that blocked every later
# run FOREVER, and the message said "another run holds" when nothing was running. Hit twice in one
# day. The owning PID is recorded inside; a lock whose owner is gone is reclaimed rather than
# obeyed. Still refuses a LIVE concurrent run, which is the case that actually corrupts backups.
if ! mkdir "$_mut_lock" 2>/dev/null; then
  _mut_owner=""
  [ -f "$_mut_lock/pid" ] && IFS= read -r _mut_owner < "$_mut_lock/pid" 2>/dev/null
  if [ -n "$_mut_owner" ] && kill -0 "$_mut_owner" 2>/dev/null; then
    echo "  FAIL another --mutate run (pid $_mut_owner) holds $_mut_lock — concurrent runs corrupt"
    echo "       each other's backups and can leave enforced core MUTATED. Wait for it to finish."; exit 2
  fi
  # Stale: the owner is dead (or never recorded it). Reclaim, saying so — silently taking a lock is
  # how the failure it guards against comes back.
  echo "  note: reclaiming a STALE lock at $_mut_lock (owner ${_mut_owner:-unknown} is gone)" >&2
  rm -f "$_mut_lock/pid" 2>/dev/null; rmdir "$_mut_lock" 2>/dev/null
  if ! mkdir "$_mut_lock" 2>/dev/null; then
    echo "  FAIL could not reclaim $_mut_lock — remove it by hand: rmdir $_mut_lock"; exit 2
  fi
fi
printf '%s\n' "$$" > "$_mut_lock/pid" 2>/dev/null || true
trap 'rm -f "$_mut_lock/pid" 2>/dev/null; rmdir "$_mut_lock" 2>/dev/null; _mut_restore' EXIT INT TERM HUP
expect="$(bats --count dev/tests 2>/dev/null | tr -d '[:space:]')"
case "${expect:-}" in ''|*[!0-9]*) expect=0 ;; esac
if [ "$expect" -lt 2 ]; then
  echo "  FAIL cannot enumerate the suite (bats --count gave '${expect}') — a gate that cannot"
  echo "       count its own tests cannot certify anything about them"; exit 2
fi
# THE CI WALL-CLOCK PROJECTION — R81 ("an unmeasured budget is not a budget") applied to CI.
# `ci-watch.sh` abandons a run after SHIP_CI_TIMEOUT and reports SHIPPED-but-UNWATCHED, so once the
# mutation set outgrows that ceiling, R74's enforced watch degrades into a no-op that still READS
# like a guarantee. That has now happened twice — 300s outgrown 2026-08-01, 1800s outgrown
# 2026-08-22 — for one reason: the mutation count only ever grows, the ceiling is a constant, and
# NOTHING compared them. The ship said so eventually, which is far too late to be useful.
# Both operands are read from their real homes, never restated here: restating either is precisely
# how the pair silently diverges. Best-effort — a fixture tree has neither file, and a projection
# is never grounds to fail a gate about mutation coverage.
sec_per_mut="${MUTGATE_SEC_PER_MUT:-85}"   # measured on CI 2026-08-22: slowest shard 1980s / 24 mutations
ci_wallclock_warn() {
  local n="$1" wf f shards ceiling per projected pct
  # Glob, not `ls | head` (SC2012): the loop stops at the first READABLE match, so an unreadable
  # or non-existent one falls through to the skip instead of being picked and then discarded.
  wf=""
  for f in .github/workflows/*.yml; do [ -r "$f" ] && { wf="$f"; break; }; done
  [ -n "$wf" ] || return 0
  # `.*` not `[^ ]*` between --shard and the /N: the workflow writes `--shard ${{ matrix.shard }}/N`
  # and that expression CONTAINS SPACES, so a no-space class silently matches nothing and the whole
  # check turns itself off — the exact failure mode this function exists to prevent, one level down.
  shards="$(sed -n 's|.*--shard .*/\([0-9][0-9]*\).*|\1|p' "$wf" | head -1)"
  ceiling="$(sed -n 's|.*SHIP_CI_TIMEOUT:-\([0-9][0-9]*\).*|\1|p' \
    plugins/companion/bin/ci-watch.sh 2>/dev/null | head -1)"
  # Validate SEPARATELY. Concatenating them to test once lets a valid operand mask an empty one
  # ("" + "5400" is all-digits and passes), which is how the first draft of this reached a bare
  # `[ "" -ge 1 ]` and an "integer expected" error instead of a clean skip.
  case "${shards:-x}" in *[!0-9]*) return 0 ;; esac
  case "${ceiling:-x}" in *[!0-9]*) return 0 ;; esac
  [ "$shards" -ge 1 ] && [ "$ceiling" -ge 1 ] || return 0
  per=$(( (n + shards - 1) / shards ))            # ceil: the SLOWEST shard sets the wall-clock
  projected=$(( per * sec_per_mut ))
  pct=$(( projected * 100 / ceiling ))
  if [ "$pct" -ge 100 ]; then
    echo "  FAIL CI wall-clock ~${projected}s ($per mutations x ${sec_per_mut}s on the slowest of"
    echo "       $shards shards) EXCEEDS the ${ceiling}s watch ceiling — every land will exit 12"
    echo "       (shipped but UNWATCHED) and R74 stops meaning anything. Add shards, or raise"
    echo "       SHIP_CI_TIMEOUT in plugins/companion/bin/ci-watch.sh."
    return 1
  elif [ "$pct" -ge 60 ]; then
    echo "  WARN CI wall-clock ~${projected}s is ${pct}% of the ${ceiling}s watch ceiling"
    echo "       ($n mutations / $shards shards) — add shards before it crosses, not after"
  fi
  return 0
}

# --validate: check that every declared mutation APPLIES to its target, without running the suite.
# Seconds instead of ~10 minutes, so it belongs in the default gate. Stale patterns have been this
# repo's most repeated defect — seven orphaned by extractions, three more by sed-delimiter
# collisions (a pattern containing the delimiter, e.g. `@{u}` or `"$@"` under `s@…@…@`). Every one
# of those was invisible locally and only surfaced on CI, where it reddened every shard at once.
if [ "$do_validate" = 1 ]; then
  vbad=0; vn=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    tgt="${line%%::*}"; tmp="${line#*::}"; sedscript="${tmp%%::*}"; what="${tmp#*::}"
    [ -f "$tgt" ] || { echo "  FAIL missing target: $tgt ($what)"; vbad=1; continue; }
    vn=$((vn+1))
    # An unescaped `&` in the REPLACEMENT expands to the whole match, silently re-inserting the
    # text the mutation was meant to remove. The result changes the file (so it validates) while
    # leaving the target string in place — which then reads as a HOLE in whatever guard searches
    # for that string, sending you to debug the guard instead of the mutation. Caught statically.
    if printf '%s' "$sedscript" | awk -v FS="" '{d=$2; n=0; for(i=3;i<=NF;i++){ if($i==d && $(i-1)!="\\") n++; if(n==1 && $i=="&" && $(i-1)!="\\") { exit 1 } } }'; then :
    else echo "  FAIL replacement contains an unescaped & (expands to the whole match): $what"; vbad=1; mv "$tgt.mutbak" "$tgt" 2>/dev/null; continue; fi
    cp "$tgt" "$tgt.mutbak"
    if ! sed -i.bak "$sedscript" "$tgt" 2>/dev/null; then
      echo "  FAIL sed script is invalid (delimiter collision?): $what"; vbad=1
    elif cmp -s "$tgt" "$tgt.mutbak"; then
      echo "  FAIL pattern matches NOTHING (stale — was the target edited or moved?): $what"; vbad=1
    fi
    rm -f "$tgt.bak"; mv "$tgt.mutbak" "$tgt"
  done < "$mfile"
  if [ "$vbad" -eq 0 ]; then
    echo "  ok ($vn declared mutations all still apply)"
    # A projection at/over 100% is not a forecast, it is a CURRENT defect: the watch cannot
    # outlast the run, so R74 is already dead. Fail on it — that is the whole point of measuring.
    ci_wallclock_warn "$vn" || vbad=1
  fi
  exit "$vbad"
fi


# RESTORE, VERIFIED. `mv "$tgt.mutbak" "$tgt"` used to be fire-and-forget, and on 2026-08-16 it
# failed twice — two "mv: cannot stat ...mutbak" lines to stderr that nothing read — leaving
# lib/task-store.sh MUTATED while the gate printed "ok caught" and exited 0. The tree it left behind
# had companion_open_tasks returning nothing, i.e. the crash-resume path dead, and every other gate
# still green. A verification tool that can silently corrupt the thing it verifies is worse than no
# tool, because its green is trusted.
#
# So: checksum before mutating, put back, checksum again, and treat any mismatch as a HARD failure
# of the whole run rather than a per-mutation note. `cksum` is POSIX and present on the macOS lane;
# read from STDIN so the filename never enters the digest.
_mut_sum() { cksum < "${1:?}" 2>/dev/null || printf 'UNREADABLE'; }
_mut_put_back() {  # $1 target · $2 checksum taken before the mutation
  local tgt="$1" want="$2" got
  mv "$tgt.mutbak" "$tgt" 2>/dev/null
  got="$(_mut_sum "$tgt")"
  if [ "$got" != "$want" ]; then
    echo "  FAIL RESTORE FAILED for $tgt — the working tree is LEFT MUTATED. Recover with:"
    echo "         git checkout -- $tgt      (or, if untracked, undo the mutation by hand)"
    restore_broken=1
    return 1
  fi
  return 0
}
restore_broken=0

# THE BASELINE MUST BE GREEN. Every verdict below is "did the suite go RED?" — which measures
# nothing if it was already red. One pre-existing failure makes EVERY mutation report "caught",
# and that is the most dangerous reading this gate can produce: a clean bill of health for
# coverage it never demonstrated. Costs one suite run; the alternative is a lie.
bout="$(bats dev/tests 2>&1)"; brc=$?
if [ "$brc" -ne 0 ]; then
  echo "  FAIL the suite is ALREADY RED before any mutation — every mutation would report"
  echo "       'caught' for a failure it did not cause. Fix the suite, then measure."
  printf '%s\n' "$bout" | grep '^not ok' | head -5 | sed 's/^/        | /'
  exit 2
fi
holes=0; errs=0; ran=0; keep=0; want=""; idx=0
while IFS= read -r line; do
  case "$line" in ''|'#'*) continue ;; esac
  tgt="${line%%::*}"; tmp="${line#*::}"; sedscript="${tmp%%::*}"; what="${tmp#*::}"
  [ -f "$tgt" ] || { echo "  SKIP (missing) $tgt"; continue; }
  if [ "${#mfilter[@]}" -gt 0 ]; then
    keep=0; for want in "${mfilter[@]}"; do [ "$want" = "$tgt" ] && keep=1; done
    [ "$keep" = 1 ] || continue
  fi
  pre_sum="$(_mut_sum "$tgt")"
  cp "$tgt" "$tgt.mutbak"
  if ! sed -i.bak "$sedscript" "$tgt" 2>/dev/null; then
    _mut_put_back "$tgt" "$pre_sum"; rm -f "$tgt.bak"
    echo "  FAIL mutation did not apply — the sed script is stale: $what"; holes=$((holes+1)); continue
  fi
  rm -f "$tgt.bak"
  if cmp -s "$tgt" "$tgt.mutbak"; then
    _mut_put_back "$tgt" "$pre_sum"
    echo "  FAIL mutation matched NOTHING (stale pattern): $what"; holes=$((holes+1)); continue
  fi
  # Shard AFTER the filter and AFTER the stale-pattern checks, so every shard still validates
  # that each pattern it reads actually matches something.
  idx=$((idx+1))
  if [ "$shard_m" -gt 1 ] && [ $(( (idx - 1) % shard_m )) -ne "$shard_n" ]; then
    _mut_put_back "$tgt" "$pre_sum"; continue
  fi
  ran=$((ran+1))
  # A nonzero exit is NOT proof a test failed. bats exits nonzero when it is KILLED (124, nothing
  # run) and when it cannot gather tests (a well-formed `1..1 / not ok bats-gather-tests`, also
  # nothing run). Scoring either as "caught" is how a real hole certified itself — twice. Require a
  # COMPLETE run: plan and result lines both equal to the calibrated count, with >=1 failure.
  mout="$(bats dev/tests 2>&1)"; mrc=$?
  # Retry ONLY an incomplete NONZERO run — transient load is the commonest cause. A green run is a
  # finished run: retrying it buys nothing and doubles the cost of every hole (which is how this
  # gate first blew its own timeout).
  if [ "$mrc" -ne 0 ] && ! _mut_complete "$mrc" "$mout" "$expect"; then
    mout="$(bats dev/tests 2>&1)"; mrc=$?
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
  _mut_put_back "$tgt" "$pre_sum"
done < "$mfile"
echo
if [ "$restore_broken" -ne 0 ]; then
  printf '== Mutation result ==\n  RESTORE FAILED — the working tree may still be MUTATED. Fix that before reading anything else below; a green gate on a mutated tree is exactly the lie this file exists to prevent.\n'
  exit 1
fi
if [ "$errs" -gt 0 ]; then printf '== Mutation result ==\n  %s INCOMPLETE RUN(S) of %s — the suite never finished, so nothing was measured\n' "$errs" "$ran"; exit 1; fi
if [ "$holes" -gt 0 ]; then printf '== Mutation result ==\n  %s HOLE(S) of %s — a test that cannot fail is not coverage\n' "$holes" "$ran"; exit 1; fi
echo "== Mutation result =="; echo "  all $ran mutations caught"; exit 0
