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
pfile="$cdir/prune-$key"           # debt-surfaced-this-episode flag (Stop debt nudge)

# Whole-project debt surface (moved here from SessionStart so it fires AFTER the
# turn's work, not before the user's intent). On a dirty tree that verified clean,
# if over-budget files cross the prune threshold, recommend a subtractive prune
# pass — once per episode (a flag file, $pfile), so it doesn't nag while debt
# persists and re-fires only after it drops below and re-crosses. Non-blocking.
surface_debt_then_allow() {
  local over n threshold budget report
  over="$(tidy_oversized_files "$root" 2>/dev/null || true)"
  n="$(printf '%s\n' "$over" | grep -c . 2>/dev/null || printf 0)"
  threshold="${CLAUDE_TIDY_PRUNE_THRESHOLD:-3}"
  if [ -n "$over" ] && [ "$n" -ge "$threshold" ]; then
    [ -f "$pfile" ] && exit 0                 # already surfaced this episode → quiet
    { mkdir -p "$cdir" 2>/dev/null && : > "$pfile"; } 2>/dev/null || true
    budget="$(tidy_size_budget)"
    report="$("$PLUGIN_DIR/bin/tidy-distill.sh" "$root" 2>/dev/null || true)"
    jq -cn --arg m "[tidy] Debt threshold crossed — $n files over the $budget-line budget. Consider a subtractive prune pass: dead code, duplication, now-redundant surface, doc↔code drift — net complexity down; route any cuts through the task-queue review loop. Weight report:"$'\n'"$report" \
      '{systemMessage: $m}'
    exit 0
  fi
  rm -f "$pfile" 2>/dev/null || true          # below threshold → reset the episode
  exit 0
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

cmd="$(tidy_test_command "$root" 2>/dev/null || true)"
[ -n "$cmd" ] || surface_debt_then_allow              # no tests → still surface debt

# Record the last outcome (pass|fail|timeout) so the status line can show it.
# Best-effort; never affects the stop decision.
tidy_set_result() { { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$1" > "$rfile"; } 2>/dev/null || true; }

# Throttle: if the tree is byte-for-byte what it was at the last GREEN verify,
# nothing changed since — skip the (possibly slow) run. (A failed/timeout verify
# clears the fingerprint, so we never skip past red tests.)
cur="$(tidy_tree_hash "$root" 2>/dev/null || true)"
if [ -n "$cur" ] && [ -f "$hfile" ] && [ "$(cat "$hfile" 2>/dev/null || true)" = "$cur" ]; then
  allow
fi

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
jq -cn --arg r "The project's tests are failing after your change — nothing is done until they're green. Run \`$cmd\`, read the failure, and fix it. If this is a recurring trap (not a one-off), record the lesson in the project's recorded decisions — what changed, what broke, what to do instead — so the next change avoids it (outcome memory):"$'\n\n'"$out" \
  '{decision: "block", reason: $r}'
