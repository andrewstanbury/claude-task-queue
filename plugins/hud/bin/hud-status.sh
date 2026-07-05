#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Three zones joined by a dim │ divider; empty slots (and empty zones) collapse:
#   [ ● health · ✓/✗ tests · 🛡✗ floors-off · ❓ parked/open-Qs ]
#   [ ✈️ autopilot · 🤖 agents · 🧷 logs  (green on, grey off) ]
#   [ model · tok ⇡in ⇣out · ⎇ branch (+ dirty * · ↑ahead ↓behind) ]
# Decode any symbol on demand with /hud:legend.
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
  Y=""; G=""; C=""; R=""; B=""; D=""; GREY=""; X=""
else
  # Bright (9x) foregrounds — vivid on a 256-color/truecolor terminal, still the
  # portable 16-color range. GREY stays dim (90) so OFF features recede.
  Y=$'\033[93m'; G=$'\033[92m'; C=$'\033[96m'; R=$'\033[91m'
  B=$'\033[1m'; D=$'\033[2m'; GREY=$'\033[90m'; X=$'\033[0m'
fi
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

# The line is three ZONES joined by a dim divider (│): [health & alerts] │ [feature
# modes] │ [context]. Within a zone slots are single-space separated so the group
# reads as one unit; an empty zone (and its divider) collapses. Grouped layout chosen
# by the owner over the old flat SEP-joined list.
DIVSEP=" $GREY│$X "
join_slots() { local out="" s; for s in "$@"; do [ -n "$s" ] && out="${out:+$out }$s"; done; printf '%s' "$out"; }

# Zone 1 — health & alerts: the beacon, the tests outcome, any disabled safety floors,
# and the ❓ count (parked decisions / open questions — the pile the owner reviews).
Z1=("$BCOL$B●$X")
case "$VERIFY" in
  pass)    Z1+=("$G$B✓ tests$X") ;;
  fail)    Z1+=("$R$B✗ tests$X") ;;
  timeout) Z1+=("$Y$B⚠ tests$X") ;;
esac
DISABLED="$(hud_floors_disabled 2>/dev/null || true)"
if [ -n "$DISABLED" ]; then
  NOFF="$(printf '%s' "$DISABLED" | wc -w | tr -d ' ')"
  Z1+=("$R$B🛡✗$NOFF$X")     # a disabled guard makes the green dot misleading — always shown
fi
OPENQ="$(hud_open_questions "$SID" 2>/dev/null || printf 0)"
[ "${OPENQ:-0}" -gt 0 ] 2>/dev/null && Z1+=("$Y$B❓$OPENQ$X")

# Zone 2 — feature modes: ALWAYS shown, each mode led by its icon (✈️ autopilot · 🤖
# agents · 🧷 logs — 🧷 is the crash-checkpoint feature, labelled "logs" in this line
# only). green = on, grey = off. On a NARROW terminal it collapses to only the ON
# features to protect width. Emoji ignore ANSI color, so when color is OFF we spell
# out on/off.
FEAT=""
add_feat() {  # $1 icon  $2 label  $3 on(1)/off(0)
  local seg word=""
  if [ "$3" = "1" ]; then
    [ -z "$G" ] && word=" on"
    seg="$1 $G$B$2$word$X"
  elif [ "$NARROW" -eq 0 ]; then
    [ -z "$GREY" ] && word=" off"
    seg="$1 $GREY$2$word$X"
  else return 0; fi
  [ -n "$FEAT" ] && FEAT="$FEAT "        # single space within the zone
  FEAT="$FEAT$seg"
}
add_feat "✈️" autopilot "$AWAY"
add_feat "🤖" agents    "$AGENT"
add_feat "🧷" logs      "$CKPT"

# Zone 3 — context: model · token throughput (⇡ input in the current context incl.
# cache · ⇣ the last response; gated on input>0 so it's silent before the first API
# call / right after compact) · git branch (+ dirty * · ↑ahead ↓behind). Tokens and
# branch shed on a narrow terminal.
Z3=("$C$SHORT_MODEL$X")
if [ "$NARROW" -eq 0 ]; then
  ITOK="${IN_TOK%.*}"; OTOK="${OUT_TOK%.*}"
  HIN="$(hud_human_tokens "$ITOK")"
  if [ -n "$HIN" ] && [ "${ITOK:-0}" -gt 0 ] 2>/dev/null; then
    HOUT="$(hud_human_tokens "$OTOK")"
    Z3+=("${D}tok ⇡$HIN ⇣${HOUT:-0}$X")
  fi
fi
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  bseg="$C$B⎇ $BRANCH$X"
  [ -n "$DIRTY" ] && bseg="$bseg $Y$B*$DIRTY$X"
  if [ -n "$AB" ]; then
    AHEAD="${AB%% *}"; BEHIND="${AB##* }"
    [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && bseg="$bseg $C$B↑$AHEAD$X"
    [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && bseg="$bseg $Y$B↓$BEHIND$X"
  fi
  Z3+=("$bseg")
fi

# Join each non-empty zone (single-space within), then the zones with the dim │.
line=""
for zone in "$(join_slots "${Z1[@]}")" "$FEAT" "$(join_slots "${Z3[@]}")"; do
  [ -n "$zone" ] || continue
  line="${line:+$line$DIVSEP}$zone"
done
printf '%s\n' "$line"
