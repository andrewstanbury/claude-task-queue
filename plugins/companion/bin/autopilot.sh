#!/usr/bin/env bash
# Toggle per-repo autopilot. ON = run autonomous, keep draining the queue, park decisions as
# ❓/⏳; OFF = normal review loop. The flag PERSISTS (survives a restart/crash), and is
# ENFORCED: the Stop hook auto-continues the queue while it's on, and the ask-guard blocks
# AskUserQuestion. Run via /companion:autopilot or directly. Best-effort.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

cmd="${1:-status}"
root="$(companion_root "$PWD")"
case "$cmd" in
  on)  companion_mode_set "$root" autopilot \
       && echo "✈️  autopilot ON for $root — I'll keep draining the queue and PARK decisions (❓) / owner-actions (⏳) until you turn it off. I may SATISFY the recorded contract but not rewrite it (R86): a change to docs/requirements.yaml gets parked for you, and docs/needs.yaml is never mine to edit." ;;
  off) companion_autopilot_clear "$root"
       # An explicit OFF outranks any pending resume: clear the paused marker so a review that
       # runs later cannot silently re-arm something the owner deliberately turned off.
       rm -f "$(companion_autopilot_paused_flag "$root")" 2>/dev/null || true
       echo "autopilot OFF for $root — normal review loop resumes; run /companion:review to walk any parked ❓ / blocked ⏳ items." ;;
  # pause/resume exist so a REVIEW is transparent to autopilot: it must disarm to ask anything
  # (the ask-guard blocks questions), and the owner should not have to re-arm by hand afterwards.
  pause) pflag="$(companion_autopilot_paused_flag "$root")"
       if companion_autopilot_on "$root"; then
         # ORDER IS THE WHOLE GUARANTEE: record that autopilot was armed BEFORE disarming it, and
         # refuse to disarm at all if that record cannot be written. The first version cleared the
         # flag unconditionally, so an unwritable state dir silently and permanently lost autopilot
         # while printing a message promising it would come back — destroying the exact state this
         # verb exists to protect. Failing loudly with autopilot still ON is the safe direction:
         # the review cannot ask, which is visible, rather than the drain quietly never resuming.
         if ! companion_mode_set "$root" autopilot-paused; then
           echo "autopilot NOT paused — could not record the paused state at $pflag, so refusing to disarm (autopilot stays ON)." >&2
           exit 1
         fi
         companion_autopilot_clear "$root"
         echo "autopilot PAUSED for $root — disarmed so the review can ask; it will re-arm when the review finishes."
       else
         echo "autopilot was already off — nothing to pause."
       fi ;;
  resume) pflag="$(companion_autopilot_paused_flag "$root")"
       if [ -f "$pflag" ]; then
         # SAME ORDER RULE AS `pause`, and it was missing here: ARM FIRST, and only destroy the
         # marker once arming has actually succeeded. Deleting the marker first meant an unwritable
         # state dir left autopilot OFF, the marker GONE, and "RESUMED" printed — unrecoverable,
         # and the exact defect `pause` had just been fixed for. A half-corrected class is worse
         # than an uncorrected one: the ledger says it is handled.
         aflag="$(companion_autopilot_flag "$root")"
         if ! companion_mode_set "$root" autopilot; then
           echo "autopilot NOT resumed — could not re-arm at $aflag. The paused marker is KEPT, so run resume again once the state dir is writable." >&2
           exit 1
         fi
         companion_mode_clear "$root" autopilot-paused
         echo "✈️  autopilot RESUMED for $root — picking the drain back up where the review interrupted it."
       else
         echo "autopilot was not paused by a review — leaving it off."
       fi ;;
  status) companion_autopilot_on "$root" && echo on || echo off ;;
  ship) sub="${2:-status}"
    case "$sub" in
      on)  companion_mode_set "$root" ship \
           && echo "📦 ship-mode ON for $root — while autopilot is on I'll auto-commit completed work to an autopilot/* branch (never main, never a push), for you to review + /companion:ship-it on return." ;;
      off) companion_mode_clear "$root" ship; echo "ship-mode OFF for $root — autopilot won't auto-commit." ;;
      status) companion_ship_on "$root" && echo on || echo off ;;
      *) echo "usage: autopilot ship on|off|status" >&2; exit 1 ;;
    esac ;;
  decisive) sub="${2:-status}"
    case "$sub" in
      on)  companion_mode_set "$root" decisive \
           && echo "⚡ decisive mode ON for $root — while autopilot is on I'll PICK my recommended option for reversible decisions (design/wording included) and record each, instead of parking. I still park (❓) / block (⏳) only what's irreversible, externally-binding, or destructive. Review the auto-picks any time with /companion:review." ;;
      off) companion_mode_clear "$root" decisive; echo "decisive mode OFF for $root — autopilot parks decisions (❓) again instead of auto-deciding." ;;
      status) companion_decisive_on "$root" && echo on || echo off ;;
      *) echo "usage: autopilot decisive on|off|status" >&2; exit 1 ;;
    esac ;;
  burndown) sub="${2:-status}"
    case "$sub" in
      on)  companion_mode_set "$root" burndown \
           && echo "🔥 burn-down ON for $root — when the 7d window is forecast to end UNDERSPENT and the queue is empty, I may GENERATE work from signals you already recorded (parked decisions with a rec:, ROADMAP items, TODOs, untested flows) and build each on a burndown/* branch behind a flag that defaults OFF. Nothing merges, nothing pushes. It stops on its own once 3 branches are awaiting your review — check them with: burndown-branch.sh list. This is the only mode that authors its own work; turn it off with: /companion:autopilot burndown off" ;;
      off) companion_mode_clear "$root" burndown; echo "burn-down OFF for $root — I will idle rather than generate work." ;;
      status) if companion_burndown_on "$root"; then echo on; else echo off; fi ;;
      *) echo "usage: autopilot.sh burndown on|off|status" >&2; exit 2 ;;
    esac
    exit 0 ;;
  sweep) sub="${2:-status}"
    case "$sub" in
      on)  companion_mode_set "$root" sweep \
           && echo "🧹 sweep mode ON for $root — while autopilot is on I'll also work the ALREADY-parked ❓ pile, applying each item's recorded recommendation. Only reversible options-parks: anything irreversible becomes ⏳ for you, and decompose: parks + ⏳ are never touched. Every pick is a tq note — walk them with /companion:review." ;;
      off) companion_mode_clear "$root" sweep; echo "sweep mode OFF for $root — the parked ❓ pile waits for you again (autopilot stops when only ❓/⏳ remain)." ;;
      status) companion_sweep_on "$root" && echo on || echo off ;;
      *) echo "usage: autopilot sweep on|off|status" >&2; exit 1 ;;
    esac ;;
  *) echo "usage: autopilot on|off|status | ship on|off|status | decisive on|off|status | sweep on|off|status" >&2; exit 1 ;;
esac
