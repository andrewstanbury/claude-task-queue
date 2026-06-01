#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Slots (left → right), each collapses when its data is absent:
#   health beacon · tasks (+ in-progress) · ⏸ paused · 🤖 agent · ✓/✗ tests ·
#   docs health · last tidy · ctx % · git branch (+ dirty) · model
#
# The beacon is a STATIC health dot (green = clean/green, yellow = paused,
# red = tests failing) — not an animation — so the status line needs no timer.
# Claude Code re-runs a statusLine command on each new message / after compact,
# which keeps every slot fresh; we deliberately set NO refreshInterval to avoid
# waking jq+git once a second on idle (battery on laptops/handhelds).
#
# Wire it (settings.json):
#   { "statusLine": { "type": "command", "command": "bash <THIS_PATH>" } }
#
# Requires bash 4+, jq. Optional git. Honours NO_COLOR / TERM=dumb.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/hud.sh
. "$PLUGIN_DIR/lib/hud.sh"

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ]; then
  Y=""; G=""; C=""; R=""; B=""; D=""; X=""
else
  Y=$'\033[33m'; G=$'\033[32m'; C=$'\033[36m'; R=$'\033[31m'
  B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
fi
SEP="  "

INPUT=""; [ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"; [ -n "$INPUT" ] || INPUT="{}"
mapfile -t F < <(printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // .model.id // "?"),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // ""),
    (.terminal_width // 0)
  ] | .[]' 2>/dev/null)
MODEL="${F[0]:-?}"; SID="${F[1]:-}"; CWD="${F[2]:-$PWD}"
CTX_PCT="${F[3]:-}"; TERM_W="${F[4]:-0}"
[ -z "$CWD" ] && CWD="$PWD"
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt 100 ] && NARROW=1

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
SHORT_MODEL="$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')"

IFS=$'\t' read -r TASK_N TASK_DOING <<<"$(hud_tasks "$SID")"
PAUSED="$(hud_paused "$ROOT")"
AGENT="$(hud_agent "$ROOT")"
VERIFY="$(hud_verify "$SID")"
QA="$(hud_qa "$ROOT")"; MAP="$(hud_map "$ROOT")"; RMAP="$(hud_roadmap "$ROOT")"
TIDY="$(hud_last_tidy)"
BRANCH="$(hud_branch "$CWD")"
# Dirty-count is only shown next to the branch (wide terminals, in a repo). Skip
# its `git status --porcelain` worktree scan otherwise — it runs every render.
DIRTY=""
[ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ] && DIRTY="$(hud_dirty "$CWD")"

# 1) Health beacon — STATIC dot, colored by overall health: red = tests failing,
# yellow = paused, green otherwise. No animation → no timer needed.
BCOL="$G"
[ "$PAUSED" = "1" ] && BCOL="$Y"
[ "$VERIFY" = "fail" ] && BCOL="$R"
printf "%s%s%s%s" "$BCOL$B" "●" "$X" "$SEP"

# 2) Tasks (+ in-progress subject)
if [ "${TASK_N:-0}" -gt 0 ] || [ -n "$TASK_DOING" ]; then
  printf "%sTasks:%s %s%s%s" "$D" "$X" "$C$B" "${TASK_N:-0}" "$X"
  [ -n "$TASK_DOING" ] && printf " %s▶ %s%s" "$D" "$TASK_DOING" "$X"
  printf "%s" "$SEP"
fi

# 3) Paused
[ "$PAUSED" = "1" ] && printf "%s⏸ paused%s%s" "$Y$B" "$X" "$SEP"

# 4) Agent-mode ON (task-queue fan-out)
[ "$AGENT" = "1" ] && printf "%s🤖 agent%s%s" "$C$B" "$X" "$SEP"

# 5) Tests — the verification floor's last outcome (the owner's trust signal)
case "$VERIFY" in
  pass)    printf "%s✓ tests%s%s" "$G$B" "$X" "$SEP" ;;
  fail)    printf "%s✗ tests%s%s" "$R$B" "$X" "$SEP" ;;
  timeout) printf "%s⚠ tests%s%s" "$Y$B" "$X" "$SEP" ;;
esac

# 6) Docs health — charter baseline (map + roadmap + QA); ✓ when all present.
DOCS_N=$(( ${QA:-0} + ${MAP:-0} + ${RMAP:-0} ))
if [ "$DOCS_N" -eq 3 ]; then printf "%sdocs%s %s✓%s%s" "$D" "$X" "$G$B" "$X" "$SEP"
else printf "%sdocs%s %s%d/3%s%s" "$D" "$X" "$Y$B" "$DOCS_N" "$X" "$SEP"; fi

# 7) Last tidy action (shed on narrow)
[ "$NARROW" -eq 0 ] && [ -n "$TIDY" ] && printf "%s✎ %s%s%s" "$D" "$TIDY" "$X" "$SEP"

# 8) Context-window fill % — "how close to a compaction" (color ramp). Uses the
# payload's pre-computed used_percentage; silent when absent (e.g. before the
# first API call or right after /compact).
if [ -n "$CTX_PCT" ]; then
  PCT="${CTX_PCT%.*}"; PCT="${PCT//[^0-9]/}"; [ -n "$PCT" ] || PCT=0
  PCOL="$G"; [ "$PCT" -ge 60 ] && PCOL="$Y"; [ "$PCT" -ge 85 ] && PCOL="$R"
  printf "%sctx%s %s%s%%%s%s" "$D" "$X" "$PCOL$B" "$PCT" "$X" "$SEP"
fi

# 9) Branch (+ dirty-file count), shed on narrow
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  printf "%s⎇ %s%s" "$C$B" "$BRANCH" "$X"
  [ -n "$DIRTY" ] && printf " %s*%s%s" "$Y$B" "$DIRTY" "$X"
  printf "%s" "$SEP"
fi

# 10) Model
printf "%sModel:%s %s%s%s" "$D" "$X" "$C" "$SHORT_MODEL" "$X"
printf '\n'
