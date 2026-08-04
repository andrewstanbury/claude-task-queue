#!/usr/bin/env bash
# burn-down.sh — decides whether autopilot may GENERATE work, and refuses far more often than it
# agrees. Every condition below is a reason to say no; all of them must clear to say yes.
#
# WHY THE BAR IS THIS HIGH. This is the only mode in the plugin that authors its own work, so it
# is the only one that can manufacture waste. A trigger on "unspent quota" optimises for spending,
# not for value — so the meter is allowed to decide WHETHER there is spare capacity and nothing
# else. What gets built comes from signals the owner already recorded (see candidates.sh), and
# where it lands is a flagged branch nobody has to keep.
#
#   status        human-readable verdict + the reason, always exit 0
#   should-burn   exit 0 = generate, 1 = hold. The reason goes to stderr.
#
# HOLD is the safe direction and every unknown resolves to it: no snapshot, a stale snapshot, no
# window data, a broken clock, an unreadable queue — all hold. The cost of a wrong HOLD is an idle
# machine. The cost of a wrong BURN is unreviewed work you did not ask for.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

WINDOW=604800                                   # the 7d window, from the field's own name
TARGET="${BURNDOWN_TARGET_PCT:-100}"            # the utilisation you are aiming at
FRESH="${BURNDOWN_SNAPSHOT_MAX_AGE:-3600}"      # a snapshot older than this tells you nothing
MAXBRANCH="${BURNDOWN_MAX_UNREVIEWED:-3}"       # backpressure: unreviewed branches awaiting you
# FINAL STRETCH (owner-decided 2026-08-02). The forecast was never what stopped the burn — at 80%
# used with a day left the projection is 93%, which already fires BURN. The BRANCH CAP is what
# stops it, and three speculative branches cannot absorb 20% of a weekly budget. So the cap, not
# the forecast, is what lifts near the reset — bounded relief exactly where the constraint binds.
FINAL="${BURNDOWN_FINAL_STRETCH:-86400}"        # "the last day" of the 7d window, in seconds
PERDAY="${BURNDOWN_BRANCHES_PER_DAY:-3}"        # extra unreviewed branches allowed per elapsed day
BRANCHCEIL="${BURNDOWN_MAX_UNREVIEWED_CEILING:-24}"  # hard ceiling however long the absence
# How far above your own sustained rate the required rate may sit before the target is called
# unreachable. Reported, never a refusal: the owner asked to land at 100% "or as close as
# possible", so a hopeless target still burns — it just stops claiming it will get there.
UNREACH="${BURNDOWN_UNREACHABLE_FACTOR:-3}"
# TWO AGREEING SAMPLES (owner-decided 2026-08-02, after measurement). The rate-limit reading is
# live but NOT trustworthy sample-by-sample: across the 16:10 5h rollover the 7d figure was
# observed at 82% -> 61% -> 82% within ~20 seconds while r7 never moved. A single low sample
# inside the final stretch would report ~20 points of headroom that do not exist and start
# generating work on a phantom; a single high one would suppress a warranted burn. So a BURN now
# needs two DISTINCT readings that agree. Disagreement HOLDs, which is the safe direction
# everywhere else in this mode. The honest cost: a legitimate burn can be delayed by one cycle.
SAMPLETOL="${BURNDOWN_SAMPLE_TOLERANCE:-5}"     # max points two readings may differ and still count
HEADROOM5="${BURNDOWN_MIN_5H_HEADROOM:-15}"     # refuse when the 5h window is nearly spent

root="$(companion_root "${BURNDOWN_ROOT:-$PWD}")"
now="$(date +%s 2>/dev/null || echo 0)"
case "$now" in ''|*[!0-9]*) now=0 ;; esac

verdict="HOLD"; reason=""; detail=""
say() { reason="$1"; }

# Count branches this mode has produced that are not merged into the default branch — i.e. work
# already waiting for the owner. If you are not reviewing, generating more is definitionally
# waste, so this is the condition that makes the loop self-limiting rather than unbounded.
unreviewed() {
  local def n
  def="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  def="${def#origin/}"; [ -n "$def" ] || def=main
  git -C "$root" rev-parse --verify --quiet "$def" >/dev/null 2>&1 || { printf '0'; return; }
  n="$(git -C "$root" branch --no-merged "$def" --list 'burndown/*' 2>/dev/null | grep -c .)"
  case "$n" in ''|*[!0-9]*) n=0 ;; esac
  printf '%s' "$n"
}

evaluate() {
  companion_burndown_on "$root" || { say "burn-down is OFF for this repo (turn it on deliberately)"; return; }

  local snap ts u5 r5 u7 r7 age left elapsed projected open nb
  snap="$(companion_rl_snapshot)"
  [ -f "$snap" ] || { say "no rate-limit snapshot yet — the status line writes it; is it wired?"; return; }
  # Field order is the snapshot's contract; r5 is read to hold its POSITION, not to be used —
  # dropping it would silently shift u7/r7 by one, which is the whole class of bug the status
  # line's US-separator fix exists to prevent.
  # shellcheck disable=SC2034
  IFS=' ' read -r ts u5 r5 u7 r7 < "$snap" 2>/dev/null || true
  case "${ts:-}" in ''|*[!0-9]*) say "snapshot unreadable"; return ;; esac
  [ "$now" -gt 0 ] || { say "no usable clock — cannot forecast"; return; }
  age=$(( now - ts ))
  # `if`, not `A && B || C`: with two conditions the || arm fires when A is FALSE too, so the guard
  # reads as if-then-else while behaving differently. CI's shellcheck flags this (SC2015); the
  # local build does not, which is precisely how it slipped through.
  if [ "$age" -lt 0 ] || [ "$age" -gt "$FRESH" ]; then
    say "snapshot is ${age}s old (max ${FRESH}s) — stale data is not a forecast"; return
  fi

  # The 5h window has to have room or the work stalls the moment it starts.
  case "${u5:-}" in ''|*[!0-9.]*) : ;; *) if [ "$(( 100 - ${u5%%.*} ))" -lt "$HEADROOM5" ]; then
      say "5h window is at ${u5%%.*}% — less than ${HEADROOM5}% headroom to actually work"; return; fi ;;
  esac

  case "${u7:-}" in ''|*[!0-9.]*) say "no 7d usage in the snapshot — nothing to forecast"; return ;; esac
  case "${r7:-}" in ''|*[!0-9]*) say "no 7d reset time in the snapshot — nothing to forecast"; return ;; esac
  left=$(( r7 - now ))
  [ "$left" -gt 0 ] || { say "the 7d window has already rolled — waiting for fresh data"; return; }
  elapsed=$(( WINDOW - left ))
  [ "$elapsed" -gt 0 ] || { say "the 7d window just started — too early to forecast"; return; }

  # THE FORECAST: extrapolate the current rate to the end of the window. Integer maths, floored,
  # which under-states the projection slightly — the safe direction, since a lower projection is
  # what argues FOR generating work, so flooring makes the trigger slightly harder to fire.
  used_i="${u7%%.*}"

  # Record this reading IMMEDIATELY, before any verdict can return. It first sat lower down, after
  # the on-track hold — so every high reading held early and never seeded the comparison, leaving
  # the history blank exactly when usage was high and a later low sample looked like a huge drop.
  # A sample is evidence regardless of what this run decides.
  prevf="$(companion_state_dir)/burndown-lastsample"
  prev_ts=""; prev_u7=""
  [ -f "$prevf" ] && read -r prev_ts prev_u7 < "$prevf" 2>/dev/null
  if mkdir -p "${prevf%/*}" 2>/dev/null; then
    if printf '%s %s\n' "$ts" "$used_i" > "$prevf.tmp$$" 2>/dev/null; then
      mv -f "$prevf.tmp$$" "$prevf" 2>/dev/null || true
    fi
  fi
  projected=$(( used_i * WINDOW / elapsed ))

  # REQUIRED RATE (owner-decided 2026-08-02). `projected` answers "where do I land if nothing
  # changes"; it says nothing about what it would TAKE to land on target, and that gap is what
  # loses budget at rollover. `needed` is the rate that must be sustained over the time actually
  # remaining, expressed in the same %-per-full-window unit as `projected` so the two compare
  # directly. It rises steeply as `left` shrinks, which is the aggression the owner asked for —
  # arriving from the arithmetic rather than from a threshold anyone has to tune.
  needed=$(( (TARGET - used_i) * WINDOW / left ))
  detail="7d ${used_i}% used, ${elapsed}s of ${WINDOW}s elapsed → tracking to ${projected}% (target ${TARGET}%); needs ${needed}%/window sustained over the remaining ${left}s"

  # Already at target: nothing to generate, in any stretch.
  [ "$used_i" -lt "$TARGET" ] || { say "7d already at ${used_i}% of target ${TARGET}% — nothing left to burn"; return; }

  # WHICH TEST DECIDES "on track" depends on how much window is left, and that is the whole of the
  # owner's ask. Outside the final stretch a projection is sound: there is time for the sustained
  # rate to carry you to the target, so tracking at-or-above it means no spare capacity. INSIDE the
  # final stretch the projection stops being trustworthy in the direction that costs money — it
  # assumes you keep spending at your average, and a night asleep in the last day is spending that
  # never happens and can no longer be made up. There, only what is ACTUALLY used counts.
  if [ "$left" -ge "$FINAL" ]; then
    [ "$projected" -lt "$TARGET" ] || { say "forecast ${projected}% ≥ target ${TARGET}% — on track, no spare capacity"; return; }
  fi

  # Unreachable is REPORTED, never a refusal. The 5h window caps throughput, so some end-of-window
  # gaps cannot be closed at any intensity; saying so is more useful than a silent shortfall, and
  # burning anyway is what "as close as possible" means.
  if [ "$projected" -gt 0 ] && [ "$needed" -gt $(( projected * UNREACH )) ]; then
    detail="$detail — UNREACHABLE: that is over ${UNREACH}x your sustained ${projected}%/window, and the 5h window caps throughput; burning to land as close as possible, not to reach ${TARGET}%"
  fi

  # Real queued work always wins — but "real work" means work I COULD DO, i.e. plain 📋 open tasks.
  # A ❓ park is a decision waiting on the owner and a ⏳ is their manual job; neither is something
  # this loop could pick up, so counting them meant:
  #   · a rank-1 candidate (a park carrying `rec:`) was itself sufficient to make burn-down refuse,
  #     so the highest-signal source could NEVER be built;
  #   · the documented loop could not iterate — step 6 parks a ❓, which blocked step 1;
  #   · the 3-unreviewed-branch backpressure was unreachable, making R82's "it stops itself" false;
  #   · one long-lived ⏳ (which R83 explicitly expects to sit for weeks) disabled the mode forever.
  # -e alternation, NOT a [❓⏳] bracket: a bracket expression over multibyte characters is
  # not portable — BSD grep (the macOS CI lane) can match bytes rather than characters.
  open="$(companion_open_tasks "$root" | grep '^  ◻' | grep -cv -e '^  ◻ *❓' -e '^  ◻ *⏳' -e '^  ◻ *⛔' || true)"
  case "$open" in ''|*[!0-9]*) open=0 ;; esac
  [ "$open" -eq 0 ] || { say "$open task(s) still queued — real work outranks generated work"; return; }

  # Record this reading for the NEXT run, then require the PREVIOUS one to corroborate it. Writing
  # happens unconditionally so a HOLD still seeds the comparison — otherwise the mode could never
  # accumulate the second sample it now requires. Best-effort: an unwritable state dir degrades to
  # "no previous sample", which HOLDs (R7/R68).
  case "${prev_ts:-}" in ''|*[!0-9]*) say "only one rate-limit reading so far — a single sample was measured swinging 21 points at a 5h rollover, so one is not evidence"; return ;; esac
  case "${prev_u7:-}" in ''|*[!0-9]*) say "previous reading unusable — holding rather than acting on one sample"; return ;; esac
  [ "$prev_ts" != "$ts" ] || { say "the snapshot has not refreshed since the last check — same sample, not a second opinion"; return; }
  [ "$(( now - prev_ts ))" -le "$FRESH" ] || { say "previous reading is $(( now - prev_ts ))s old (max ${FRESH}s) — too stale to corroborate"; return; }
  sdiff=$(( used_i - prev_u7 )); [ "$sdiff" -ge 0 ] || sdiff=$(( 0 - sdiff ))
  [ "$sdiff" -le "$SAMPLETOL" ] || { say "the last two readings disagree by ${sdiff} points (max ${SAMPLETOL}) — that is the rollover transient, not headroom"; return; }

  # The cap lifts only inside the final stretch, and only there — outside it, three unreviewed
  # branches still means stop, because generating past what you are reviewing is waste by
  # definition. Inside it, the budget is about to expire and unspent quota is simply lost.
  # TIME-AWARE CAP (owner-decided 2026-08-04, for a week away from keyboard). A flat 3 halts the
  # mode on about day one of an unattended week, which makes "leave it on and come back to ~100%
  # usage" impossible by construction — the cap, not the forecast, is what stops the burn. It now
  # grows with the window that has actually elapsed, so backpressure still exists on any given day
  # while a long absence keeps producing. Subsumes the old final-stretch lift, which was a special
  # case of the same idea. The ceiling is what stops a runaway from producing branches forever.
  cap=$(( MAXBRANCH + PERDAY * (elapsed / 86400) ))
  [ "$cap" -le "$BRANCHCEIL" ] || cap="$BRANCHCEIL"
  nb="$(unreviewed)"
  [ "$nb" -lt "$cap" ] || { say "$nb unreviewed burndown/* branch(es) (max $cap) — review or delete before more is made"; return; }

  verdict="BURN"; say "forecast underspend with an empty queue and $nb/$cap branches awaiting review"
}

evaluate

case "${1:-status}" in
  status)
    printf '%s: %s\n' "$verdict" "$reason"
    [ -n "$detail" ] && printf '  %s\n' "$detail"
    exit 0 ;;
  should-burn)
    [ "$verdict" = BURN ] && exit 0
    printf 'hold: %s\n' "$reason" >&2
    exit 1 ;;
  *)
    printf 'usage: burn-down.sh [status|should-burn]\n' >&2; exit 2 ;;
esac
