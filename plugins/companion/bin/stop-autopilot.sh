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

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"
companion_autopilot_on "$root" || allow

# Ship-mode (R34): capture this turn's work as a reversible COMMIT on a non-default branch — never
# the default branch, never a push. Best-effort in a subshell; nothing here may break the stop.
if companion_ship_on "$root" && [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
  ( cd "$cwd" 2>/dev/null || exit 0
    git rev-parse HEAD >/dev/null 2>&1 || exit 0                              # need ≥1 commit
    def="$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
    [ -n "$def" ] || def="$(git config --get init.defaultBranch 2>/dev/null)"; [ -n "$def" ] || def="main"
    cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$cur" in "$def"|main|master|HEAD|"")                                # protect the default branch
      git checkout -q -b "autopilot/$(date +%Y%m%d-%H%M%S)" 2>/dev/null || exit 0 ;;
    esac
    cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
    case "$cur" in "$def"|main|master|HEAD|"") exit 0 ;; esac                 # NEVER commit to default
    git add -A 2>/dev/null || true
    # Don't bake a real credential into a checkpoint (ship-mode's `git add` isn't seen by the
    # secret gate, which only scans Write/Edit). If the staged diff has a high-confidence key shape,
    # unstage and skip this commit — the owner deals with it. (R34; anchored shapes only, ~zero FP.)
    if git diff --cached 2>/dev/null | grep -qE "$(companion_secret_re)"; then
      git reset -q 2>/dev/null || true
      exit 0
    fi
    # Use the repo's own identity if configured; else a companion fallback (these throwaway
    # checkpoints get squashed under the owner's identity on /companion:ship-it). Without this the
    # commit fails wherever git identity isn't set (CI, a fresh machine) — silently capturing nothing.
    git commit -q -m "autopilot: checkpoint on $cur" 2>/dev/null \
      || git -c user.name='companion (autopilot)' -c user.email='autopilot@companion.local' \
             commit -q -m "autopilot: checkpoint on $cur" 2>/dev/null || true
  ) >/dev/null 2>&1 || true
fi

dir="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}/$sid"
files=("$dir"/*.json); [ -e "${files[0]}" ] || allow
# open = pending/in_progress and NOT deferred (❓/⏳); done = completed (progress signal).
# IFS=$'\t' on the read is load-bearing (R46): the fields are tab-joined and the subject (NEXT) can
# carry spaces — a default-IFS split would corrupt it the moment a field order changes (the R32·1
# space-in-value bug the status line already hit; keep the two parses consistent).
# SWEEP (R77): with the flag on, an already-parked ❓ stops counting as "deferred" and the drain
# keeps going instead of declaring the run finished. Eligibility is a POSITIVE MARKER the parker
# wrote, never an inference over prose: `rev:` means *reversible, but the owner's call* (a taste /
# design / wording choice — R33), which is the only class an unattended run may decide for them.
# A park is irreversible whenever it lacks `rev:`, which is the safe default for every park written
# before this existed. `rec:` must be anchored — an unanchored substring matched subjects like
# "no rec: recorded, this one is yours", i.e. exactly the opposite of what it claims to detect.
# NEVER eligible in any mode: `⏳` (blocked ON THE OWNER acting in the world — no mode clears it)
# and `decompose:` parks (R65 — questions, not options), matched case-insensitively.
sweep=false; companion_sweep_on "$root" && sweep=true
IFS=$'\t' read -r OPEN PLAIN DONE NEXT NID DONEWHEN < <(jq -rs --argjson sw "$sweep" '
  def subj: ((.subject//"")|sub("^\\s+";""));
  def parked: (subj|startswith("❓"));
  def sweepable: parked
    and ((subj|ascii_downcase|contains("decompose:"))|not)
    and (subj|test("^❓\\s*\\[parked\\]\\s*rev:"))   # the parker marked it reversible-but-yours
    and (subj|test("[;—-]\\s*rec:"));         # ...and recorded a pick to apply
  def pk: (subj|startswith("⏳")) or (parked and (($sw and sweepable)|not));
  ([.[]|select((.status=="pending" or .status=="in_progress") and (pk|not))]) as $o
  | ([$o[]|select((subj|startswith("❓"))|not)]) as $plain
  | "\($o|length)\t\($plain|length)\t\([.[]|select(.status=="completed")]|length)\t\(($o[0].subject // "")|gsub("\t";" "))\t\($o[0].id // "")\t\(($o[0].done_when // "")|gsub("\t";" "))"' "${files[@]}" 2>/dev/null)
OPEN="${OPEN:-0}"; PLAIN="${PLAIN:-0}"; DONE="${DONE:-0}"; NID="${NID:-}"; DONEWHEN="${DONEWHEN:-}"
case "$OPEN" in ''|*[!0-9]*) OPEN=0 ;; esac
case "$PLAIN" in ''|*[!0-9]*) PLAIN=0 ;; esac
case "$DONE" in ''|*[!0-9]*) DONE=0 ;; esac

cfile="$(companion_state_dir)/autopilot/continue-$(printf '%s' "${sid:-x}" | sed 's:/:-:g')"
if [ "$OPEN" -eq 0 ]; then rm -f "$cfile" 2>/dev/null; allow; fi   # nothing workable left → genuinely done

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
