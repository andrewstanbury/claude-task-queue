#!/usr/bin/env bash
# Stop hook — post-work debt surface + opt-in test gates.
#
# The end-of-turn verification floor (run the project's tests/quality gates and
# block until green) was REMOVED at the owner's request — tests are run manually,
# so the Stop hook no longer runs the suite (that was the "hangs on every stop"
# cost). What remains is cheap and non-blocking by default:
#
#   • post-work debt surface (always on, dirty tree only): import CYCLES touching a
#     file changed this turn (clean-architecture — always a problem) and a throttled
#     deliberate-PRUNE nudge when over-budget files cross the threshold. One message,
#     never blocks.
#   • two OPT-IN, off-by-default test gates that block until a changed file is
#     characterized — the coverage ratchet (every changed source file) and the
#     narrow regression gate (a changed file that is both a scar-tissue hotspot and
#     untested). These check for a test's EXISTENCE; they never run the suite.
#
# Disable the whole hook with CLAUDE_TIDY_CHECKS=0. Best-effort: any internal error
# degrades to "allow the stop".

set -uo pipefail

# Missing jq → allow the stop and no-op (this hook parses input + emits block/message
# JSON via jq; without it every emit would error). exit 0 = let the stop proceed, the
# safe degrade for a best-effort companion. Guard before the lib source.
command -v jq >/dev/null 2>&1 || exit 0

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

# Only act when there's something to look at: a dirty working tree. A clean repo (or a
# pure-conversation turn) means no changes → nothing to surface.
if git -C "$root" rev-parse >/dev/null 2>&1; then
  [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] && allow
fi

# Per-session state: the opt-in gate counters and the debt-surface dedup/throttle files.
cdir="$(tidy_log_dir)/verify"
key="$(printf '%s' "${sid:-nosession}" | sed 's:/:-:g')"
gfile="$cdir/covgate-$key"         # coverage-ratchet block counter
rgfile="$cdir/regress-$key"        # regression-gate block counter
pfile="$cdir/prune-$key"           # debt-surfaced-this-episode flag (Stop debt nudge)
cyfile="$cdir/cycles-$key"         # last-surfaced import-cycle set (content hash)

# Bounded-counter helpers for the two opt-in block-gates below (coverage ratchet,
# regression gate). Each gate reads a per-session counter, gives up after
# CLAUDE_TIDY_VERIFY_MAX tries, else increments and blocks. Centralizing the
# read+sanitize and the write keeps that "can never loop" arithmetic in ONE place.
tidy_gate_count() {                  # sanitized current count for counter-file $1 (0 if absent/garbage)
  local n=0
  [ -f "$1" ] && n="$(cat "$1" 2>/dev/null || printf 0)"
  n="${n//[^0-9]/}"; [ -n "$n" ] || n=0
  printf '%s' "$n"
}
tidy_gate_bump() { { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$(($2 + 1))" > "$1"; } 2>/dev/null || true; }

# Post-work architecture + debt surface (fires AFTER the turn's work). On a dirty tree
# it surfaces, NON-blocking and in one message: (a) any import CYCLE involving a file
# changed this turn (clean-architecture — always a problem), content-deduped so an
# unchanged cycle set stays quiet; and (b) a subtractive PRUNE pass when over-budget
# files cross the threshold, throttled once per debt episode ($pfile).
surface_debt_then_allow() {
  local msg="" cyc chash over n threshold budget report dmsg
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
  [ -n "$msg" ] && jq -cn --arg m "$msg" '{systemMessage: $m}'
  exit 0
}

# Coverage ratchet (opt-in, strict): block the stop until every changed source
# file has a test, so an under-tested project can't keep growing untested surface.
# Off by default — the touch-time nudge is the always-on version. BOUNDED: after
# CLAUDE_TIDY_VERIFY_MAX blocks it gives up (warns, allows) so it can never loop.
if [ "${CLAUDE_TIDY_COVERAGE_RATCHET:-0}" = "1" ]; then
  untested="$(tidy_untested_changed "$root" 2>/dev/null | head -n 20)"
  if [ -n "$untested" ]; then
    gmax="${CLAUDE_TIDY_VERIFY_MAX:-3}"; gcount="$(tidy_gate_count "$gfile")"
    if [ "$gcount" -ge "$gmax" ]; then
      rm -f "$gfile" 2>/dev/null || true             # gave it enough tries → allow
      jq -cn --arg m "⚠️ Coverage ratchet: still untested after $gcount prompts — characterize these when you can: $(printf '%s' "$untested" | tr '\n' ' ')" \
        '{systemMessage: $m}'
      exit 0
    fi
    tidy_gate_bump "$gfile" "$gcount"
    jq -cn --arg r "Coverage ratchet: these changed source files have no test — characterize them (pin current behavior with a test) before finishing, so the project accrues a spec:"$'\n\n'"$untested" \
      '{decision: "block", reason: $r}'
    exit 0
  fi
  rm -f "$gfile" 2>/dev/null || true                 # satisfied → reset the counter
fi

# Regression gate (OPT-IN, NARROW): a changed file that is BOTH a scar-tissue hotspot
# (repeatedly fixed — charter's outcome-memory signal) AND untested is the highest
# regression risk in the tree — a fix here can silently come back. When enabled, block
# until it's characterized, closing the loop charter's scar-tissue *detection* opens.
# OFF by default — tests are the OWNER'S call. Bounded like the ratchet (can't loop);
# skipped when the broad ratchet is already forcing.
if [ "${CLAUDE_TIDY_REGRESSION_GATE:-0}" = "1" ] && [ "${CLAUDE_TIDY_COVERAGE_RATCHET:-0}" != "1" ]; then
  hotun="$(tidy_untested_hotspots "$root" 2>/dev/null | head -n 20)"
  if [ -n "$hotun" ]; then
    rmax="${CLAUDE_TIDY_VERIFY_MAX:-3}"; rcount="$(tidy_gate_count "$rgfile")"
    if [ "$rcount" -ge "$rmax" ]; then
      rm -f "$rgfile" 2>/dev/null || true             # gave it enough tries → allow
      jq -cn --arg m "⚠️ Regression gate: still uncharacterized after $rcount prompts — these repeatedly-fixed files need a regression test when you can: $(printf '%s' "$hotun" | tr '\n' ' ')" \
        '{systemMessage: $m}'
      exit 0
    fi
    tidy_gate_bump "$rgfile" "$rcount"
    jq -cn --arg r "These changed files have been REPEATEDLY FIXED before (scar tissue, from git history) and still have NO test — a fix here can silently regress, which is exactly how they became debt magnets. Pin the current/fixed behavior with a regression test before finishing, so the file stops churning (this is the outcome-memory loop closing: detect repeat-fixes → force a test on the next touch):"$'\n\n'"$hotun" \
      '{decision: "block", reason: $r}'
    exit 0
  fi
  rm -f "$rgfile" 2>/dev/null || true                 # no untested hotspot → reset
fi

# No verification floor anymore (tests are run manually) — the Stop hook's remaining
# default job is the non-blocking post-work debt/cycle surface.
surface_debt_then_allow
