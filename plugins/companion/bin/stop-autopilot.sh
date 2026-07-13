#!/usr/bin/env bash
# Stop hook — while autopilot is ON for this repo and non-deferred work remains in the queue,
# AUTO-CONTINUE instead of stopping (keep-going mode, R36). Self-terminates when only
# ❓/⏳ deferred items are left. A no-progress cap (consecutive stops with no task completed)
# yields so a stuck model can't spin forever. Best-effort: any error degrades to "allow the
# stop". Disable: CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0; cap: CLAUDE_COMPANION_AUTOPILOT_MAX (8).
set -uo pipefail
allow() { exit 0; }
command -v jq >/dev/null 2>&1 || allow
[ "${CLAUDE_COMPANION_AUTOPILOT_CONTINUE:-1}" = "0" ] && allow
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
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
IFS=$'\t' read -r OPEN DONE NEXT < <(jq -rs '
  def pk: ((.subject//"")|sub("^\\s+";"")|(startswith("❓") or startswith("⏳")));
  ([.[]|select((.status=="pending" or .status=="in_progress") and (pk|not))]) as $o
  | "\($o|length)\t\([.[]|select(.status=="completed")]|length)\t\(($o[0].subject // "")|gsub("\t";" "))"' "${files[@]}" 2>/dev/null)
OPEN="${OPEN:-0}"; DONE="${DONE:-0}"
case "$OPEN" in ''|*[!0-9]*) OPEN=0 ;; esac
case "$DONE" in ''|*[!0-9]*) DONE=0 ;; esac

cfile="$(companion_state_dir)/autopilot/continue-$(printf '%s' "${sid:-x}" | sed 's:/:-:g')"
if [ "$OPEN" -eq 0 ]; then rm -f "$cfile" 2>/dev/null; allow; fi   # only ❓/⏳ left → genuinely done

# No-progress cap: reset the stall counter whenever a task completed since last stop.
last=0; stall=0
[ -f "$cfile" ] && read -r last stall < "$cfile" 2>/dev/null
case "$last" in ''|*[!0-9]*) last=0 ;; esac; case "$stall" in ''|*[!0-9]*) stall=0 ;; esac
if [ "$DONE" -gt "$last" ]; then stall=0; else stall=$((stall+1)); fi
max="$(printf '%s' "${CLAUDE_COMPANION_AUTOPILOT_MAX:-8}" | tr -dc '0-9')"; max="${max:-8}"
if [ "$stall" -ge "$max" ]; then rm -f "$cfile" 2>/dev/null; allow; fi   # stuck → yield
{ mkdir -p "$(dirname "$cfile")" 2>/dev/null && printf '%s %s' "$DONE" "$stall" > "$cfile"; } 2>/dev/null || true

jq -cn --arg n "$NEXT" --arg c "$OPEN" '{decision:"block", reason:
  ("✈️ Autopilot: \($c) task(s) still open — next: “\($n)”. Keep going (autopilot means do not stop): DO NOT stop and DO NOT ask. Take the next task, do it, verify your own work (you have a shell), `tq done` it, and continue. PARK what genuinely needs the owner — `❓ [parked]` for a decision or a visual/design/direction choice, `⏳ [blocked]` for an owner-only action — and decide the routine, low-stakes rest yourself. Keep going until only ❓/⏳ items remain.")}'
