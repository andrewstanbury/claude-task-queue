#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Slots (left → right), each collapses when its data is absent:
#   beacon (animated) · tasks (+ in-progress) · ⏸ paused · QA · last tidy ·
#   tokens up/down · git branch · model
#
# Wire it (settings.json):
#   { "statusLine": { "type": "command",
#                     "command": "bash <THIS_PATH>",
#                     "refreshInterval": 1 } }   # 1s keeps the beacon animating
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
  Y=""; G=""; C=""; B=""; D=""; X=""
else
  Y=$'\033[33m'; G=$'\033[32m'; C=$'\033[36m'
  B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'
fi
SEP="  "

INPUT=""; [ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"; [ -n "$INPUT" ] || INPUT="{}"
mapfile -t F < <(printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // .model.id // "?"),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.terminal_width // 0)
  ] | .[]' 2>/dev/null)
MODEL="${F[0]:-?}"; SID="${F[1]:-}"; CWD="${F[2]:-$PWD}"
IN_TOK="${F[3]:-0}"; OUT_TOK="${F[4]:-0}"; TERM_W="${F[5]:-0}"
[ -z "$CWD" ] && CWD="$PWD"
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt 100 ] && NARROW=1

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
SHORT_MODEL="$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')"

IFS=$'\t' read -r TASK_N TASK_DOING <<<"$(hud_tasks "$SID")"
PAUSED="$(hud_paused "$ROOT")"
QA="$(hud_qa "$ROOT")"
TIDY="$(hud_last_tidy)"
BRANCH="$(hud_branch "$CWD")"

# 1) Beacon — animated glyph (advances once per second with refreshInterval:1).
SPIN=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)
BEACON="${SPIN[$(( $(date +%s 2>/dev/null || echo 0) % ${#SPIN[@]} ))]}"
BCOL="$G"; [ "$PAUSED" = "1" ] && BCOL="$Y"
printf "%s%s%s%s" "$BCOL$B" "$BEACON" "$X" "$SEP"

# 2) Tasks (+ in-progress subject)
if [ "${TASK_N:-0}" -gt 0 ] || [ -n "$TASK_DOING" ]; then
  printf "%sTasks:%s %s%s%s" "$D" "$X" "$C$B" "${TASK_N:-0}" "$X"
  [ -n "$TASK_DOING" ] && printf " %s▶ %s%s" "$D" "$TASK_DOING" "$X"
  printf "%s" "$SEP"
fi

# 3) Paused
[ "$PAUSED" = "1" ] && printf "%s⏸ paused%s%s" "$Y$B" "$X" "$SEP"

# 4) Quality attributes
if [ "$QA" = "1" ]; then printf "%sQA%s %s✓%s%s" "$D" "$X" "$G$B" "$X" "$SEP"
else printf "%sQA%s %s·%s%s" "$D" "$X" "$Y$B" "$X" "$SEP"; fi

# 5) Last tidy action (shed on narrow)
[ "$NARROW" -eq 0 ] && [ -n "$TIDY" ] && printf "%s✎ %s%s%s" "$D" "$TIDY" "$X" "$SEP"

# 6) Tokens — current-context up (sent) / down (received)
printf "%sTokens:%s %s↑%s %s%s%s %s↓%s %s%s%s%s" \
  "$D" "$X" "$C" "$X" "$B" "$(hud_fmt_k "$IN_TOK")" "$X" \
  "$C" "$X" "$B" "$(hud_fmt_k "$OUT_TOK")" "$X" "$SEP"

# 7) Branch (shed on narrow)
[ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ] && printf "%s⎇ %s%s%s%s" "$C$B" "$BRANCH" "$X" "$X" "$SEP"

# 8) Model
printf "%sModel:%s %s%s%s" "$D" "$X" "$C" "$SHORT_MODEL" "$X"
printf '\n'
