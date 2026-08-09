#!/usr/bin/env bash
# Toggle per-repo autopilot. ON = run autonomous, keep draining the queue, park decisions as
# ❓/⏳; OFF = normal review loop. The flag PERSISTS (survives a restart/crash). NOT enforced
# anymore (R100/Pass 4 retired ask-guard.sh and stop-autopilot.sh — there is no more Stop hook to
# force continuation and no more PreToolUse hook to deny AskUserQuestion): this flag is now a
# STATED preference STEERING reads, not a mechanism. Run via /companion:autopilot or directly.
# Best-effort.
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
# A pause marker is TRANSIENT — it means "this review disarmed autopilot and owes it back", and it
# is only meaningful inside the session that wrote it. Unstamped it outlived its session: a review
# on 2026-08-08 paused, never resumed, and the NEXT DAY a review that had found autopilot already
# OFF (so its own `pause` was a correct no-op) hit the day-old marker on `resume` and armed a mode
# the owner had never turned on. Reproduced live, then fixed here. Same resolution as `tq`, which is
# the other reader of session identity.
SID="${CLAUDE_COMPANION_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
# Stamp both paths `companion_mode_set` writes, so a mixed-version read (repo CLI vs cached hook)
# cannot see a stamped marker through one path and a bare one through the other.
# REPLACES `companion_mode_set` for this one marker rather than stamping after it: two writers for
# one file meant `mode_set` could succeed and the stamp still fail (ENOSPC — `: >` needs no data
# block, `printf` does), leaving a marker that `pause` called recorded and `resume` correctly
# refuses. One write, one failure path, and the caller's existing refuse-to-disarm guard covers it.
# Mirrors `companion_mode_set`'s dual-write; the LEGACY copy stays best-effort because a pre-fix
# reader ignores content anyway, so failing there costs nothing this version relies on.
_pause_stamp() {
  local f g; f="$(companion_autopilot_paused_flag "$1")"; g="$(companion_mode_legacy "$1" autopilot-paused)"
  mkdir -p "${f%/*}" 2>/dev/null || return 1
  printf '%s\n' "${SID:--}" > "$f" 2>/dev/null || return 1
  mkdir -p "${g%/*}" 2>/dev/null && printf '%s\n' "${SID:--}" > "$g" 2>/dev/null
  return 0
}
# Honour a marker ONLY when it names THIS session. Anything else — a different session, an unstamped
# marker from a pre-fix version, or no session id to compare against — is refused. The direction is
# deliberate: failing to auto-resume is visible and one `autopilot on` away, while wrongly arming
# starts unattended work the owner never asked for and may not be watching.
_pause_is_ours() {
  local f owner; f="$(companion_autopilot_paused_flag "$1")"
  [ -n "$SID" ] || return 1
  # Test the VARIABLE, not `read`'s status: a marker with no trailing newline still sets it (LESSONS).
  read -r owner < "$f" 2>/dev/null
  [ -n "${owner:-}" ] && [ "$owner" = "$SID" ]
}
case "$cmd" in
  on)  companion_mode_set "$root" autopilot \
       && echo "✈️  autopilot ON for $root — I'll keep draining the queue and PARK decisions (❓) / owner-actions (⏳) until you turn it off. I should SATISFY the recorded contract, not rewrite it — STEERING's rule, not enforced anymore (R100/Pass 3 retired contract-guard.sh): docs/needs.yaml is still never mine to write, and a docs/requirements.yaml change is mine to propose-and-park, not decide — my own discipline now, nothing blocks either for me." ;;
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
         if ! _pause_stamp "$root"; then
           echo "autopilot NOT paused — could not record the paused state at $pflag, so refusing to disarm (autopilot stays ON)." >&2
           exit 1
         fi
         companion_autopilot_clear "$root"
         echo "autopilot PAUSED for $root — disarmed so the review can ask; it will re-arm when the review finishes."
         [ -n "$SID" ] || echo "autopilot: no session id, so this pause cannot be verified on resume — re-arm with 'autopilot on' after the review." >&2
       else
         echo "autopilot was already off — nothing to pause."
       fi ;;
  resume) pflag="$(companion_autopilot_paused_flag "$root")"
       if [ -f "$pflag" ] && ! _pause_is_ours "$root"; then
         # Stale or foreign: clear it rather than leave it to mis-fire again on the next review.
         companion_mode_clear "$root" autopilot-paused
         echo "autopilot NOT resumed — the pause marker was not written by this session (stale or from another session), so it is discarded rather than trusted. Autopilot stays OFF; run 'autopilot on' if you want it armed."
       elif [ -f "$pflag" ]; then
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
