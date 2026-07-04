#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Slots (left → right); the feature-status slot is always shown, the rest collapse
# when their data is absent:
#   health beacon · ✈️ autopilot/🧷 checkpoint/🤖 agents (green on, dim off) · ✓/✗ tests · 🛡✗ floors-off ·
#   ❓ open-Qs · 🔗↑ coupling · tok ⇡in ⇣out · git branch (+ dirty * · ↑ahead ↓behind)
#   · model.  Decode any symbol on demand with /hud:legend.
#
# Scoped to signals a status line is the BEST surface for — persistent
# state/health you want at a glance. Deliberately NOT re-rendered here: the task
# list (Claude Code shows it natively), docs-health (charter nudges it at session
# start), and last-tidy (ephemeral) — surfacing those again was duplication, and
# the docs mirror was the heaviest cross-plugin maintenance burden.
#
# The beacon is a STATIC health dot (green = clean/green, yellow = solo mode,
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

# On-demand: print the symbol key and exit (the /hud:legend command). No stdin.
if [ "${1:-}" = "--legend" ]; then hud_legend; exit 0; fi

INPUT=""; [ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"; [ -n "$INPUT" ] || INPUT="{}"
mapfile -t F < <(printf '%s' "$INPUT" | jq -r '[
    (.model.display_name // .model.id // "?"),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.terminal_width // 0),
    (.context_window.total_input_tokens // ""),
    (.context_window.total_output_tokens // "")
  ] | .[]' 2>/dev/null)
MODEL="${F[0]:-?}"; SID="${F[1]:-}"; CWD="${F[2]:-$PWD}"
TERM_W="${F[3]:-0}"; IN_TOK="${F[4]:-}"; OUT_TOK="${F[5]:-}"
[ -z "$CWD" ] && CWD="$PWD"
[ "${TERM_W:-0}" -le 0 ] && TERM_W="${COLUMNS:-0}"
[ "$TERM_W" -le 0 ] && TERM_W=200
NARROW=0; [ "$TERM_W" -lt 100 ] && NARROW=1

ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
SHORT_MODEL="$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')"

AGENT="$(hud_agent "$ROOT")"
AWAY="$(hud_away "$ROOT")"
CKPT="$(hud_checkpoint "$ROOT")"
VERIFY="$(hud_verify "$SID")"
BRANCH="$(hud_branch "$CWD")"
# Dirty-count + ahead/behind are only shown next to the branch (wide terminals, in
# a repo). Skip their git calls otherwise — they run every render.
DIRTY=""; AB=""
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  DIRTY="$(hud_dirty "$CWD")"
  AB="$(hud_ahead_behind "$CWD")"
fi

# 1) Health beacon — STATIC dot, colored by overall health: red = tests failing,
# yellow = autopilot (autonomous, an attention state), green otherwise. No animation
# → no timer needed.
BCOL="$G"
[ "$AWAY" = "1" ] && BCOL="$Y"
[ "$VERIFY" = "fail" ] && BCOL="$R"
printf "%s%s%s%s" "$BCOL$B" "●" "$X" "$SEP"

# 2) Feature status — ALWAYS shown, each mode led by its icon (matching the
# SessionStart banners: ✈️ autopilot · 🧷 checkpoint · 🤖 agents) so the owner can
# see each mode's state at a glance: green = on, dim = off. The leading icons make a
# separator redundant. On a NARROW terminal it collapses to only the ON features to
# protect width. Emoji ignore ANSI color, so when color is OFF (NO_COLOR/dumb) the
# green/dim can't convey state — we spell out on/off in that case only.
FEAT=""
add_feat() {  # $1 icon  $2 label  $3 on(1)/off(0)
  local seg word=""
  if [ "$3" = "1" ]; then
    [ -z "$G" ] && word=" on"
    seg="$1 $G$B$2$word$X"
  elif [ "$NARROW" -eq 0 ]; then
    [ -z "$D" ] && word=" off"
    seg="$1 $D$2$word$X"
  else return 0; fi
  [ -n "$FEAT" ] && FEAT="$FEAT$SEP"
  FEAT="$FEAT$seg"
}
add_feat "✈️" autopilot  "$AWAY"
add_feat "🧷" checkpoint "$CKPT"
add_feat "🤖" agents     "$AGENT"
[ -n "$FEAT" ] && printf '%s%s' "$FEAT" "$SEP"

# 4) Tests — the verification floor's last outcome (the owner's trust signal)
case "$VERIFY" in
  pass)    printf "%s✓ tests%s%s" "$G$B" "$X" "$SEP" ;;
  fail)    printf "%s✗ tests%s%s" "$R$B" "$X" "$SEP" ;;
  timeout) printf "%s⚠ tests%s%s" "$Y$B" "$X" "$SEP" ;;
esac

# 4a) Disabled safety floors — 🛡✗N when any anti-rework gate is switched off via a
# CLAUDE_*=0 env var. Always shown (never shed on narrow): the whole point is that a
# disabled guard makes the green dot misleading, so the warning must not collapse.
DISABLED="$(hud_floors_disabled 2>/dev/null || true)"
if [ -n "$DISABLED" ]; then
  NOFF="$(printf '%s' "$DISABLED" | wc -w | tr -d ' ')"
  printf "%s🛡✗%s%s%s" "$R$B" "$NOFF" "$X" "$SEP"
fi

# 4b) Open questions — unanswered ❓ items you still owe an answer on this session.
# Ambient nudge so lingering questions get NOTICED without anyone re-raising them.
OPENQ="$(hud_open_questions "$SID" 2>/dev/null || printf 0)"
[ "${OPENQ:-0}" -gt 0 ] 2>/dev/null && printf "%s❓%s%s%s" "$Y$B" "$OPENQ" "$X" "$SEP"

# 4c) Coupling trend — 🔗↑ only when import density climbed past the threshold at
# tidy's last verify (cached read; hud never computes it). Hidden when steady.
case "$(hud_coupling "$ROOT" 2>/dev/null)" in
  up*) printf "%s🔗↑%s%s" "$Y$B" "$X" "$SEP" ;;
esac

# 5a) Token throughput — ⇡ input ("uploaded": tokens in the current context, incl.
# cache) and ⇣ output ("downloaded": the last response). From the same context_window
# object as ctx% — since Claude Code v2.1.132 these are CURRENT-context figures, not
# cumulative-session totals. Dim + shed on narrow; gated on input > 0 so it's silent
# before the first API call and right after /compact (when the counts reset).
if [ "$NARROW" -eq 0 ]; then
  ITOK="${IN_TOK%.*}"; OTOK="${OUT_TOK%.*}"
  HIN="$(hud_human_tokens "$ITOK")"
  if [ -n "$HIN" ] && [ "${ITOK:-0}" -gt 0 ] 2>/dev/null; then
    HOUT="$(hud_human_tokens "$OTOK")"
    printf '%stok ⇡%s ⇣%s%s%s' "$D" "$HIN" "${HOUT:-0}" "$X" "$SEP"
  fi
fi

# 6) Branch (+ dirty-file count + unpushed/unpulled), shed on narrow
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  printf "%s⎇ %s%s" "$C$B" "$BRANCH" "$X"
  [ -n "$DIRTY" ] && printf " %s*%s%s" "$Y$B" "$DIRTY" "$X"
  if [ -n "$AB" ]; then
    AHEAD="${AB%% *}"; BEHIND="${AB##* }"
    [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && printf " %s↑%s%s" "$C$B" "$AHEAD" "$X"
    [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && printf " %s↓%s%s" "$Y$B" "$BEHIND" "$X"
  fi
  printf "%s" "$SEP"
fi

# 7) Model — name only (the "Model:" label is dropped to save width)
printf "%s%s%s" "$C" "$SHORT_MODEL" "$X"
printf '\n'
