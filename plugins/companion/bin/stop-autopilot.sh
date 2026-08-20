#!/usr/bin/env bash
# Stop hook — while autopilot is ON for this repo and non-deferred work remains in the queue,
# AUTO-CONTINUE instead of stopping (keep-going mode, R36). Self-terminates when only
# ❓/⏳ deferred items are left. A no-progress cap (consecutive stops with no task completed)
# yields so a stuck model can't spin forever. Best-effort: any error degrades to "allow the
# stop". Disable: CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0; cap: CLAUDE_COMPANION_AUTOPILOT_MAX (8).
#
# RUN BOUNDS (R81): the no-progress cap catches a STUCK model, never a BUSY one — `stall` resets on
# every completion, so a productive drain had no plugin-side terminator at all. Two generous bounds
# now end an unattended runaway without interrupting ordinary work; `0` disables either:
#   CLAUDE_COMPANION_AUTOPILOT_HOURS (6)   wall-clock; includes suspend, which is the safe direction
#   CLAUDE_COMPANION_AUTOPILOT_TURNS (400) total continuations; suspend-immune
#
# RESTORED 2026-08-12 (owner-decided) from d8a46ff^, where R100/Pass 4 deleted it. This is a PARTIAL
# restore — 135 of the original 183 lines — and the two omissions are deliberate, because both
# concerns acquired another owner while this file was gone:
#   · SHIP-MODE AUTO-COMMIT (R34) stays deleted. `bin/ship-checkpoint.sh` owns it now, invoked
#     deliberately rather than on every stop. Restoring it here would put two owners on one concern
#     and silently re-automate a commit path the owner made manual on purpose.
#   · THE BURN-DOWN HAND-OFF (R82) was ALSO omitted here — and that omission was REVERSED
#     2026-08-15 (owner-decided). The argument for leaving it out was duplicate ownership: STEERING
#     told the model to call `burn_down` itself when the queue ran dry, so automating it here would
#     make that prose false. What the argument missed is that prose is not an owner — it is a
#     request, and the owner reasonably believed the feature was automatic while nothing ever fired
#     it. Ownership is not duplicated now because the STEERING sentence was rewritten in the SAME
#     change: the hook owns WHETHER to continue, the model owns WHAT to build (R28, and R81 — the
#     hook must not run the repo-wide `git grep` that ranking costs). See the dry-queue path below.
# What came back is exactly the guarantee that was asked for — do not stop while startable work
# remains — plus every terminator that bounds it. Restoring the continuation WITHOUT its bounds
# would have been the one genuinely dangerous version of this change.
set -uo pipefail
allow() { exit 0; }
command -v jq >/dev/null 2>&1 || allow
[ "${CLAUDE_COMPANION_AUTOPILOT_CONTINUE:-1}" = "0" ] && allow
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

# THE BURN-DOWN HAND-OFF (R82) — see the header note. Defined once and called from BOTH dry-queue
# exits: the store-has-no-files bail below AND the nothing-startable branch further down. Placing it
# in only the second was a real bug caught by its own test — a brand-new session with burn-down
# armed and no tasks ever created is the most ordinary idle case there is, and it left through the
# first bail without ever consulting the mode.
#
# It makes only the CHEAP call (should-burn: a snapshot read plus a branch count, measured at 23ms).
# Ranking is the model's job — candidates.sh git-greps the whole repo, which R81 forbids in a hook.
burn_handoff() {  # returns only when it did NOT fire; exits 0 having blocked when it did
  companion_burndown_on "$1" || return 0
  local _bd; _bd="$(cd "$(dirname "$SELF")" && pwd)/burn-down.sh"
  [ -r "$_bd" ] || return 0
  BURNDOWN_ROOT="$1" bash "$_bd" should-burn >/dev/null 2>&1 || return 0
  jq -cn '{decision:"block", reason:
    "\u2708\ufe0f\ud83d\udd25 Autopilot: the queue is DRY and burn-down says BURN — there is forecast spare capacity in the 7d window and room under the unreviewed-branch cap. DO NOT stop. Run `candidates.sh` (or the `candidates` MCP tool), take the HIGHEST-RANKED candidate, and start it via `burndown-branch.sh start \"<candidate>\" --why \"<rationale>\"` (or the `burndown_branch` tool). THE RATIONALE IS NOT OPTIONAL IN SPIRIT: name which of the project\u2019s ordered core values it serves (self-describing > blast radius > verify+align > subtract as you add), what you estimate it costs, and what you chose it OVER. It lands in the manifest, so the owner can correct your PRIORITIES and not just your output; omit it and the manifest says so in bold. Hardening ranks above features by design, and feature-shaped work is separately capped. Nothing merges and nothing pushes: the branch is for the owner to review, and the mode stops itself once enough branches are waiting. If `candidates` comes back EMPTY, there is genuinely nothing recorded to build — say so in one line and stop rather than inventing work."}'
  exit 0
}

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"
companion_autopilot_on "$root" || allow

dir="$(companion_session_dir "$root" "$sid")"
files=("$dir"/*.json)
if [ ! -e "${files[0]}" ]; then burn_handoff "$root"; allow; fi   # no store yet is still a dry queue
# open = pending/in_progress and NOT deferred (❓/⏳); done = completed (progress signal).
# Split on US (0x1f), NOT tab: tab is IFS whitespace, so a run of them collapses and every field
# after an EMPTY one shifts left (LESSONS). The FIELDS and the sweep rules that produce them are
# defined by `tq stopfields` — read them there, and change them only there.
# SWEEP (R77) is passed through, not re-decided here: the flag is per-repo state this hook can see
# and tq cannot, so the hook reads the flag and tq applies the rule.
sweep=false; companion_sweep_on "$root" && sweep=true
# ONE implementation of "first startable task" (R86·b, owner-decided 2026-08-02): this used to
# re-derive the selection in its own jq, it drifted from tq, and the hook then offered a task
# blocked on an unanswered park four turns running. tq owns it; this reads it.
# Best-effort (R7/R68): a missing/empty store or an unreadable tq leaves every field empty, which
# sanitizes to 0 below and allows the stop — the hook never breaks the action that triggered it.
_tq="$(cd "$(dirname "$SELF")" && pwd)/tq"
IFS=$'\x1f' read -r OPEN PLAIN DONE NEXT NID DONEWHEN STARTABLE < <(
  CLAUDE_COMPANION_SESSION_ID="$sid" "$_tq" stopfields "$sweep" 2>/dev/null)
OPEN="${OPEN:-0}"; PLAIN="${PLAIN:-0}"; DONE="${DONE:-0}"; NID="${NID:-}"; DONEWHEN="${DONEWHEN:-}"
case "${STARTABLE:-}" in ''|*[!0-9]*) STARTABLE=0 ;; esac
case "$OPEN" in ''|*[!0-9]*) OPEN=0 ;; esac
case "$PLAIN" in ''|*[!0-9]*) PLAIN=0 ;; esac
case "$DONE" in ''|*[!0-9]*) DONE=0 ;; esac

cfile="$(companion_state_dir)/autopilot/continue-$(printf '%s' "${sid:-x}" | sed 's:/:-:g')"
# Nothing workable left → genuinely done. STARTABLE covers the second way a drain ends: open tasks
# remain, but every one of them waits on an earlier item, so pushing is asking for the impossible.
#
# NOTHING WORKABLE LEFT → end the turn. STARTABLE covers the second way a drain ends: open tasks
# remain, but every one waits on an earlier item, so pushing is asking for the impossible.
#
# The flag STAYS ARMED here (owner-asked 2026-08-05, reversing R88's self-disarm) — see below. The
# history is worth keeping straight because it looks like a contradiction: R88 disarmed on a dry
# queue to stop a stale hook nagging four turns running, and the fix turned out to be to stop
# BLOCKING, not to stop being armed. Allowing while armed keeps the fix and drops the side effect,
# so work queued later drains without the owner re-arming by hand — which is precisely the
# complaint that produced this restore (owner, 2026-08-11: "I want autopilot to keep going if
# there are new tasks in the queue and it's turned on").
if [ "$OPEN" -eq 0 ] || [ "$STARTABLE" -eq 0 ]; then
  # STAY ARMED on a dry queue (owner-asked 2026-08-05, reversing the self-disarm of R88). The turn
  # still ENDS — a queue with nothing startable must never block the session — but the flag is left
  # alone, so work queued later drains without the owner re-arming by hand. R88 disarmed to stop a
  # stale hook nagging; that nagging came from BLOCKING, not from staying armed, so allowing while
  # armed keeps the fix and drops the side effect.
  #
  # THE BURN-DOWN HAND-OFF (R82) — RESTORED 2026-08-15, owner-decided, reversing the deliberate
  # omission recorded at the top of this file. The reasoning for deleting it (one concern, one
  # owner) was sound, but the result was a feature the owner believed was automatic that only ran
  # if the model REMEMBERED to call it — and the same session that asked for this proved how that
  # class of instruction fares: 0 of 89 tasks carried the breadcrumbs STEERING has demanded since
  # R47. Continuing a turn is control-flow, the one thing a hook can actually guarantee (R28), so
  # the guarantee lives here and the prose at the top has been corrected rather than left false.
  #
  # WHAT THIS HOOK DOES NOT DO, and why (R81): it does not rank candidates. `candidates.sh` runs a
  # `git grep` over the whole repo — unbounded in repo size, on a hook that fires at every stop of
  # an autopiloted run. So the hook makes only the CHEAP decision (should-burn: one snapshot read
  # plus a branch count) and hands the expensive lookup to the model, which is the R28 split done
  # properly: the hook decides whether to continue, the model does the work.
  #
  # Reached ONLY on a dry queue with burn-down armed, so an ordinary drain never pays for it at all.
  burn_handoff "$root"
  rm -f "$cfile" 2>/dev/null
  allow
fi

# No-progress cap: reset the stall counter whenever a task completed since last stop.
# Five fields since 2026-07-29; a 3-field file from an older version reads back with the two new
# ones empty, which sanitize to 0 and re-seed on this turn — no migration, no lost run.
last=0; stall=0; swept=0; started=0; turns=0
[ -f "$cfile" ] && read -r last stall swept started turns < "$cfile" 2>/dev/null
case "$last"  in ''|*[!0-9]*) last=0 ;;  esac; case "$stall" in ''|*[!0-9]*) stall=0 ;; esac
case "$swept" in ''|*[!0-9]*) swept=0 ;; esac
case "$started" in ''|*[!0-9]*) started=0 ;; esac; case "$turns" in ''|*[!0-9]*) turns=0 ;; esac
if [ "$DONE" -gt "$last" ]; then stall=0; else stall=$((stall+1)); fi

# ---- RUN bounds (R81 follow-up): bound the RUN, not just the stall ----------------------------
# The stall cap above catches a STUCK model; it cannot catch a BUSY one, because `stall` resets to
# 0 on every completion. A drain that keeps finishing tasks — or keeps queueing new ones as it
# decomposes work — therefore had NO plugin-side terminator at all, and would run until the queue
# emptied or the account rate limit stopped it. That is not a thermal strategy on a handheld.
# Two independent bounds, whichever fires first; both yield exactly like the stall cap (allow the
# stop, clear the counter file), so a bounded run ends cleanly and `/companion:resume` picks it up.
# Defaults are deliberately GENEROUS — they must never interrupt ordinary interactive work, only
# stop an unattended runaway. `0` disables either one.
now="$(date +%s 2>/dev/null || echo 0)"; case "$now" in ''|*[!0-9]*) now=0 ;; esac
[ "$started" -eq 0 ] && started="$now"
turns=$((turns + 1))
# (a) WALL-CLOCK. Note this is real elapsed time and INCLUDES suspend — on a machine that sleeps,
# waking long after the run began yields immediately. That is the safe direction: an unattended run
# that spanned a suspend should stop, not resume drawing power.
# `10#` forces base 10: a value like "08" is otherwise read as octal, which errors under $(( ))
# and SILENTLY DISABLES the bound. Clamp the width too so a huge value cannot overflow negative.
hours="$(printf '%s' "${CLAUDE_COMPANION_AUTOPILOT_HOURS:-6}" | tr -dc '0-9')"; hours="${hours:-6}"
[ "${#hours}" -gt 6 ] && hours=999999
hours=$((10#$hours))
if [ "$hours" -gt 0 ] && [ "$now" -gt 0 ] && [ "$started" -gt 0 ] \
   && [ "$((now - started))" -ge "$((hours * 3600))" ]; then
  rm -f "$cfile" 2>/dev/null; allow
fi
# (b) TOTAL TURNS — counts every continuation regardless of progress, so it closes the
# reset-on-completion hole directly, and unlike the clock it is immune to suspend.
maxturns="$(printf '%s' "${CLAUDE_COMPANION_AUTOPILOT_TURNS:-400}" | tr -dc '0-9')"; maxturns="${maxturns:-400}"
[ "${#maxturns}" -gt 9 ] && maxturns=999999999
maxturns=$((10#$maxturns))
if [ "$maxturns" -gt 0 ] && [ "$turns" -ge "$maxturns" ]; then
  rm -f "$cfile" 2>/dev/null; allow
fi
max="$(printf '%s' "${CLAUDE_COMPANION_AUTOPILOT_MAX:-8}" | tr -dc '0-9')"; max="${max:-8}"
if [ "$stall" -ge "$max" ]; then rm -f "$cfile" 2>/dev/null; allow; fi   # stuck → yield
# SWEEP TERMINATOR (R77) — the stall cap CANNOT bound a sweep: closing a swept park advances DONE,
# which resets stall to 0, so a run that closes one park and opens another blocks forever (measured:
# 25/25 turns against a cap of 8). Sweep also removes `OPEN==0 → allow`, previously the only
# model-independent terminator. So count the turns that continue SOLELY because of sweep — no plain
# work left, only eligible parks — in a counter nothing resets, and yield at the same cap.
if [ "$sweep" = true ] && [ "$PLAIN" -eq 0 ] && [ "$OPEN" -gt 0 ]; then
  swept=$((swept+1))
  if [ "$swept" -ge "$max" ]; then rm -f "$cfile" 2>/dev/null; allow; fi   # swept enough → yield
fi
{ mkdir -p "$(dirname "$cfile")" 2>/dev/null && printf '%s %s %s %s %s' "$DONE" "$stall" "$swept" "$started" "$turns" > "$cfile"; } 2>/dev/null || true

SWEEPNOTE=""
if [ "$sweep" = true ]; then
  SWEEPNOTE=" SWEEP (R77) is on, so the next item may itself be a \`❓ [parked]\` one. If it is: apply its recorded \`rec:\` pick ONLY when the action is reversible — \`tq note\` the decision, \`tq add\` the concrete task, \`tq done\` the park. If it is irreversible, externally-binding or destructive, do NOT decide it — \`tq cancel\` it and re-\`tq add\` it as \`⏳ [blocked] <the owner action>\`, which takes it out of the sweep and leaves it for the owner. Never touch a \`decompose:\` park."
fi
jq -cn --arg n "$NEXT" --arg c "$OPEN" --arg id "$NID" --arg dw "$DONEWHEN" --arg sw "$SWEEPNOTE" '{decision:"block", reason:
  ("✈️ Autopilot: \($c) task(s) still open — next: #\($id) “\($n)”\(if $dw != "" then " (done when: \($dw))" else "" end). Keep going (autopilot means do not stop): DO NOT stop and DO NOT ask. Take task #\($id), do it, verify your own work (you have a shell), `tq done \($id)` it, and continue. PARK what genuinely needs the owner — `❓ [parked]` for a decision or a visual/design/direction choice, `⏳ [blocked]` for an owner-only action — and decide the routine, low-stakes rest yourself. Keep going until nothing workable remains.\($sw)")}'
