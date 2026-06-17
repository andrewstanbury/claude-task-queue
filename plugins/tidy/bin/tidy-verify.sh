#!/usr/bin/env bash
# Stop hook — the verification floor. When Claude finishes, if the working tree
# has changes and the project has a discoverable test command, run it; if it
# FAILS, block the stop and feed the failure back so Claude fixes it — nothing is
# "done" until the suite is green. This is the safety net a non-technical owner
# can't produce themselves.
#
# Bounded so it can never loop forever: at most CLAUDE_TIDY_VERIFY_MAX (default 3)
# forced fix cycles per session, then it lets the stop through with a visible
# warning. Disable entirely with CLAUDE_TIDY_CHECKS=0. Best-effort: any internal
# error degrades to "allow the stop".

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tidy.sh
. "$PLUGIN_DIR/lib/tidy.sh"
# shellcheck source=../lib/checks.sh
. "$PLUGIN_DIR/lib/checks.sh"
# shellcheck source=../lib/coverage.sh
. "$PLUGIN_DIR/lib/coverage.sh"
# shellcheck source=../lib/arch.sh
. "$PLUGIN_DIR/lib/arch.sh"

allow() { exit 0; }                                   # let the stop proceed

[ "${CLAUDE_TIDY_CHECKS:-1}" = "0" ] && allow

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; sid=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Resolve the repo root (git top, else walk, else cwd).
root="$(tidy_root_for_cwd "$cwd")"

# Only verify when there's something to verify: a dirty working tree. A clean
# repo (or a pure-conversation turn) means no changes → nothing to run.
if git -C "$root" rev-parse >/dev/null 2>&1; then
  [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] && allow
fi

# Per-session state: the attempt counters and the last-green tree fingerprint.
cdir="$(tidy_log_dir)/verify"
key="$(printf '%s' "${sid:-nosession}" | sed 's:/:-:g')"
cfile="$cdir/$key"
hfile="$cdir/hash-$key"
rfile="$cdir/result-$key"          # last verification outcome, for hud's tests slot
gfile="$cdir/covgate-$key"         # coverage-ratchet block counter
rgfile="$cdir/regress-$key"        # regression-gate block counter
pfile="$cdir/prune-$key"           # debt-surfaced-this-episode flag (Stop debt nudge)
cpfile="$(tidy_log_dir)/coupling/$(printf '%s' "$root" | sed 's:/:-:g')"  # coupling-density baseline (per repo)
chfile="$(tidy_log_dir)/coupling-hud/$(printf '%s' "$root" | sed 's:/:-:g')"  # cached coupling direction for hud (up|steady)
cyfile="$cdir/cycles-$key"         # last-surfaced import-cycle set (content hash)
qfile="$cdir/quality-$key"         # quality-floor block counter

# Post-work architecture + debt surface (fires AFTER the turn's work, not before
# the user's intent). On a dirty tree that verified clean it surfaces, NON-blocking
# and in one message: (a) any import CYCLE involving a file changed this turn
# (clean-architecture — always a problem), content-deduped so an unchanged cycle
# set stays quiet; and (b) a subtractive PRUNE pass when over-budget files cross
# the threshold, throttled once per debt episode ($pfile).
surface_debt_then_allow() {
  local msg="" cyc chash over n threshold budget report dmsg ccur cprev delta pct thr cmsg cstate
  # (a) clean-architecture: import cycles touching this change (zero owner config).
  cyc="$(tidy_cycles_changed "$root" 2>/dev/null | head -n 10 || true)"
  if [ -n "$cyc" ]; then
    chash="$(printf '%s' "$cyc" | cksum | tr -d ' ')"
    if [ "$(cat "$cyfile" 2>/dev/null || true)" != "$chash" ]; then   # new cycle set → surface
      { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$chash" > "$cyfile"; } 2>/dev/null || true
      msg="[tidy] Circular dependency involving a file you changed — a cycle is always a problem (break one edge: invert a dependency, or extract the shared piece into a module both can depend on):"$'\n'"$cyc"
    fi
  else
    rm -f "$cyfile" 2>/dev/null || true        # no cycle → reset the dedup
  fi
  # (b) subtractive prune when debt crosses the threshold (throttled per episode).
  over="$(tidy_oversized_files "$root" 2>/dev/null || true)"
  n="$(printf '%s\n' "$over" | grep -c . 2>/dev/null || printf 0)"
  threshold="${CLAUDE_TIDY_PRUNE_THRESHOLD:-3}"
  if [ -n "$over" ] && [ "$n" -ge "$threshold" ]; then
    if [ ! -f "$pfile" ]; then                 # not yet surfaced this episode
      { mkdir -p "$cdir" 2>/dev/null && : > "$pfile"; } 2>/dev/null || true
      budget="$(tidy_size_budget)"
      report="$("$PLUGIN_DIR/bin/tidy-distill.sh" "$root" 2>/dev/null || true)"
      dmsg="[tidy] Debt threshold crossed — $n files over the $budget-line budget. Consider a subtractive prune pass: dead code, duplication, now-redundant surface, doc↔code drift — net complexity down; route any cuts through the task-queue review loop. Weight report:"$'\n'"$report"
      [ -n "$msg" ] && msg="$msg"$'\n\n'"$dmsg" || msg="$dmsg"
    fi
  else
    rm -f "$pfile" 2>/dev/null || true          # below threshold → reset the episode
  fi
  # (c) coupling TREND: import-edge DENSITY (per file) climbing vs the last check —
  # "watch total coupling doesn't climb" turned into a measured signal. Baseline is
  # per repo; we only re-anchor it UP when we warn (so gradual creep accumulates to
  # the threshold) or DOWN when density falls (e.g. after a prune). Non-blocking.
  if [ "${CLAUDE_TIDY_COUPLING_TREND:-1}" != "0" ]; then
    ccur="$(tidy_coupling_density "$root" 2>/dev/null || printf 0)"
    ccur="${ccur//[^0-9]/}"; [ -n "$ccur" ] || ccur=0
    if [ "$ccur" -gt 0 ]; then
      cstate=steady                          # hud cache: up only on a threshold climb
      cprev=""; [ -f "$cpfile" ] && cprev="$(cat "$cpfile" 2>/dev/null || true)"
      cprev="${cprev//[^0-9]/}"
      if [ -z "$cprev" ] || [ "$ccur" -le "$cprev" ]; then
        { mkdir -p "$(dirname "$cpfile")" 2>/dev/null && printf '%s' "$ccur" > "$cpfile"; } 2>/dev/null || true
      else
        delta=$((ccur - cprev)); pct=$((delta * 100 / cprev)); thr="${CLAUDE_TIDY_COUPLING_DELTA:-15}"
        if [ "$pct" -ge "$thr" ]; then
          cstate=up
          { mkdir -p "$(dirname "$cpfile")" 2>/dev/null && printf '%s' "$ccur" > "$cpfile"; } 2>/dev/null || true
          cmsg="[tidy] Coupling trend — import density up ${pct}% ($(printf '%d.%02d' $((cprev/100)) $((cprev%100))) → $(printf '%d.%02d' $((ccur/100)) $((ccur%100))) imports/file) since the last check. Coupling is climbing faster than the file count; consider a boundary pass (one owner per concern, reuse before create, invert a dependency) before it compounds — route any cuts through the task-queue review loop."
          [ -n "$msg" ] && msg="$msg"$'\n\n'"$cmsg" || msg="$cmsg"
        fi
        # grew but below threshold → leave the baseline so creep accumulates
      fi
      # cache the direction for hud's ambient 🔗↑ indicator (read-only, cheap)
      { mkdir -p "$(dirname "$chfile")" 2>/dev/null && printf '%s' "$cstate" > "$chfile"; } 2>/dev/null || true
    fi
  fi
  [ -n "$msg" ] && jq -cn --arg m "$msg" '{systemMessage: $m}'
  exit 0
}

# Quality floor: enforce the project's OWN declared quality gates (typecheck, a11y/
# perf, dependency-rule architecture — discovered by tidy_quality_commands) the same
# way as the test command — detect-and-run, block until green, bounded. Reaching the
# green test branch (which stores the throttle hash) therefore means quality AND
# tests both passed. Heavy audits (Lighthouse/CWV) stay in the project's CI; this
# only runs the gates the project already wired into package.json. On the first
# failing gate it blocks (bounded by $qfile, like the test floor: a give-up
# systemMessage after the cap, a timeout note that won't loop). Returns when all
# gates pass / none exist. Disable with CLAUDE_TIDY_QUALITY_FLOOR=0.
run_quality_floor() {
  local gates label cmd qout qrc qmax qcount
  gates="$(tidy_quality_commands "$root" 2>/dev/null || true)"
  [ -n "$gates" ] || return 0
  while IFS=$'\t' read -r label cmd; do
    [ -n "$cmd" ] || continue
    qout="$(tidy_run_checks "$root" "$cmd" 2>/dev/null)"; qrc=$?
    [ "$qrc" -eq 0 ] && continue
    if [ "$qrc" -eq 124 ]; then
      jq -cn --arg m "⚠️ Quality gate '$label' timed out ($cmd) — couldn't verify; run it manually if needed." '{systemMessage: $m}'
      exit 0
    fi
    qmax="${CLAUDE_TIDY_VERIFY_MAX:-3}"; qcount=0
    [ -f "$qfile" ] && qcount="$(cat "$qfile" 2>/dev/null || printf 0)"
    qcount="${qcount//[^0-9]/}"; [ -n "$qcount" ] || qcount=0
    if [ "$qcount" -ge "$qmax" ]; then
      rm -f "$qfile" 2>/dev/null || true
      jq -cn --arg m "⚠️ Quality gate '$label' still failing after $qcount attempts ($cmd) — needs attention before it's trusted." '{systemMessage: $m}'
      exit 0
    fi
    { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((qcount + 1))" > "$qfile"; } 2>/dev/null || true
    jq -cn --arg r "The project's '$label' quality gate is failing after your change — nothing is done until it passes. Run \`$cmd\`, read the output, and fix what your change introduced (leave unrelated pre-existing issues alone):"$'\n\n'"$qout" \
      '{decision: "block", reason: $r}'
    exit 0
  done <<< "$gates"
  rm -f "$qfile" 2>/dev/null || true                  # all gates green → reset counter
  return 0
}

# Coverage ratchet (opt-in, strict): block the stop until every changed source
# file has a test, so an under-tested project can't keep growing untested surface.
# Off by default — the touch-time nudge is the always-on version. Runs before the
# test-command check so it works even on a project with no runnable suite yet.
# BOUNDED, like the test path: after CLAUDE_TIDY_VERIFY_MAX blocks it gives up
# (warns, allows) so it can never loop forever — honoring this file's invariant.
if [ "${CLAUDE_TIDY_COVERAGE_RATCHET:-0}" = "1" ]; then
  untested="$(tidy_untested_changed "$root" 2>/dev/null | head -n 20)"
  if [ -n "$untested" ]; then
    gmax="${CLAUDE_TIDY_VERIFY_MAX:-3}"; gcount=0
    [ -f "$gfile" ] && gcount="$(cat "$gfile" 2>/dev/null || printf 0)"
    gcount="${gcount//[^0-9]/}"; [ -n "$gcount" ] || gcount=0
    if [ "$gcount" -ge "$gmax" ]; then
      rm -f "$gfile" 2>/dev/null || true             # gave it enough tries → allow
      jq -cn --arg m "⚠️ Coverage ratchet: still untested after $gcount prompts — characterize these when you can: $(printf '%s' "$untested" | tr '\n' ' ')" \
        '{systemMessage: $m}'
      exit 0
    fi
    { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((gcount + 1))" > "$gfile"; } 2>/dev/null || true
    jq -cn --arg r "Coverage ratchet: these changed source files have no test — characterize them (pin current behavior with a test) before finishing, so the project accrues a spec:"$'\n\n'"$untested" \
      '{decision: "block", reason: $r}'
    exit 0
  fi
  rm -f "$gfile" 2>/dev/null || true                 # satisfied → reset the counter
fi

# Regression gate (always-on, NARROW): a changed file that is BOTH a scar-tissue
# hotspot (repeatedly fixed — charter's outcome-memory signal) AND untested is the
# highest regression risk in the tree — a fix here can silently come back. Block
# until it's characterized, closing the loop charter's scar-tissue *detection*
# opens. Unlike the broad coverage ratchet above (opt-in, every untested file),
# this is safe to keep ON by default because it only fires on files that have
# PROVEN they regress, and goes quiet the moment a test lands. Bounded like the
# test floor (can't loop). Disable with CLAUDE_TIDY_REGRESSION_GATE=0; skipped when
# the broad ratchet is already forcing (it covers these too).
if [ "${CLAUDE_TIDY_REGRESSION_GATE:-1}" != "0" ] && [ "${CLAUDE_TIDY_COVERAGE_RATCHET:-0}" != "1" ]; then
  hotun="$(tidy_untested_hotspots "$root" 2>/dev/null | head -n 20)"
  if [ -n "$hotun" ]; then
    rmax="${CLAUDE_TIDY_VERIFY_MAX:-3}"; rcount=0
    [ -f "$rgfile" ] && rcount="$(cat "$rgfile" 2>/dev/null || printf 0)"
    rcount="${rcount//[^0-9]/}"; [ -n "$rcount" ] || rcount=0
    if [ "$rcount" -ge "$rmax" ]; then
      rm -f "$rgfile" 2>/dev/null || true             # gave it enough tries → allow
      jq -cn --arg m "⚠️ Regression gate: still uncharacterized after $rcount prompts — these repeatedly-fixed files need a regression test when you can: $(printf '%s' "$hotun" | tr '\n' ' ')" \
        '{systemMessage: $m}'
      exit 0
    fi
    { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((rcount + 1))" > "$rgfile"; } 2>/dev/null || true
    jq -cn --arg r "These changed files have been REPEATEDLY FIXED before (scar tissue, from git history) and still have NO test — a fix here can silently regress, which is exactly how they became debt magnets. Pin the current/fixed behavior with a regression test before finishing, so the file stops churning (this is the outcome-memory loop closing: detect repeat-fixes → force a test on the next touch):"$'\n\n'"$hotun" \
      '{decision: "block", reason: $r}'
    exit 0
  fi
  rm -f "$rgfile" 2>/dev/null || true                 # no untested hotspot → reset
fi

cmd="$(tidy_test_command "$root" 2>/dev/null || true)"

# Record the last outcome (pass|fail|timeout) so the status line can show it.
# Best-effort; never affects the stop decision.
tidy_set_result() { { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$1" > "$rfile"; } 2>/dev/null || true; }

# Throttle: if the tree is byte-for-byte what it was at the last GREEN verify,
# nothing changed since — skip the (possibly slow) quality + test run. (A failed/
# timeout verify clears the fingerprint, so we never skip past red tests/gates.)
cur="$(tidy_tree_hash "$root" 2>/dev/null || true)"
if [ -n "$cur" ] && [ -f "$hfile" ] && [ "$(cat "$hfile" 2>/dev/null || true)" = "$cur" ]; then
  allow
fi

# Enforce the project's own declared quality gates first (typecheck/a11y/dep-rules).
# Blocks on a failing gate; returns when they pass / none exist.
run_quality_floor

[ -n "$cmd" ] || surface_debt_then_allow              # no test command → still surface debt/cycles

out="$(tidy_run_checks "$root" "$cmd" 2>/dev/null)"; rc=$?

if [ "$rc" -eq 0 ]; then
  rm -f "$cfile" 2>/dev/null || true                  # green → reset counter
  if [ -n "$cur" ]; then { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$cur" > "$hfile"; } 2>/dev/null || true; fi
  tidy_set_result pass
  surface_debt_then_allow
fi

rm -f "$hfile" 2>/dev/null || true                    # not green → drop the stale pass-fingerprint

if [ "$rc" -eq 124 ]; then                            # timed out — can't verify; don't loop on it
  rm -f "$cfile" 2>/dev/null || true
  tidy_set_result timeout
  jq -cn --arg m "⚠️ Tests timed out (> ${CLAUDE_TIDY_VERIFY_TIMEOUT:-180}s, \`$cmd\`) — couldn't verify this change; run them manually if needed." \
    '{systemMessage: $m}'
  exit 0
fi

max="${CLAUDE_TIDY_VERIFY_MAX:-3}"
count=0
[ -f "$cfile" ] && count="$(cat "$cfile" 2>/dev/null || printf 0)"
count="${count//[^0-9]/}"; [ -n "$count" ] || count=0

if [ "$count" -ge "$max" ]; then
  rm -f "$cfile" 2>/dev/null || true                  # gave it enough tries
  tidy_set_result fail
  jq -cn --arg m "⚠️ Tests are still failing after $count fix attempts ($cmd) — this needs attention before the change is trusted." \
    '{systemMessage: $m}'
  exit 0
fi

{ mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((count + 1))" > "$cfile"; } 2>/dev/null || true
tidy_set_result fail
jq -cn --arg r "The project's tests are failing after your change — nothing is done until they're green. Diagnose, don't guess: (1) reproduce — confirm the failing signal (\`$cmd\`); (2) form 2-3 falsifiable hypotheses for the cause and what each predicts — don't anchor on the first idea; (3) if you add debug logging to test one, tag it (e.g. [DEBUG-x9f2]) so removing it after is a single grep; (4) fix the root cause and add a regression test that pins the bug; (5) remove the tagged instrumentation. If this is a recurring trap (not a one-off), record the lesson in the project's recorded decisions — what changed, what broke, what to do instead — so the next change avoids it (outcome memory):"$'\n\n'"$out" \
  '{decision: "block", reason: $r}'
