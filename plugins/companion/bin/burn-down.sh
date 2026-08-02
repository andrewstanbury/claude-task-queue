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
  projected=$(( ${u7%%.*} * WINDOW / elapsed ))
  detail="7d ${u7%%.*}% used, ${elapsed}s of ${WINDOW}s elapsed → tracking to ${projected}% (target ${TARGET}%)"
  [ "$projected" -lt "$TARGET" ] || { say "forecast ${projected}% ≥ target ${TARGET}% — on track, no spare capacity"; return; }

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
  open="$(companion_open_tasks "$root" | grep '^  ◻' | grep -cv -e '^  ◻ *❓' -e '^  ◻ *⏳' || true)"
  case "$open" in ''|*[!0-9]*) open=0 ;; esac
  [ "$open" -eq 0 ] || { say "$open task(s) still queued — real work outranks generated work"; return; }

  nb="$(unreviewed)"
  [ "$nb" -lt "$MAXBRANCH" ] || { say "$nb unreviewed burndown/* branch(es) (max $MAXBRANCH) — review or delete before more is made"; return; }

  verdict="BURN"; say "forecast underspend with an empty queue and $nb/$MAXBRANCH branches awaiting review"
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
