#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Three zones joined by a dim │ divider; empty slots (and empty zones) collapse:
#   [ ● health · 🛡 safety(✗N off) · ✓/✗ tests · 🎨 design-gate · 🔒 review-gate · ❓ decisions · ⏳ owner-blocked ]
#   [ ✈️ autopilot · 🤖 agents  (green on, grey off) ]
#   [ model · tok ⇡in ⇣out · ⎇ branch (+ dirty * · ↑ahead ↓behind) ]
# Decode any symbol on demand with /hud:legend.
#
# Scoped to signals a status line is the BEST surface for — persistent
# state/health you want at a glance. Deliberately NOT re-rendered here: the task
# list (Claude Code shows it natively), docs-health (charter nudges it at session
# start), and last-tidy (ephemeral) — surfacing those again was duplication, and
# the docs mirror was the heaviest cross-plugin maintenance burden.
#
# The beacon is an ANIMATED braille-orbit spinner (green = clean/green, yellow = solo
# mode, red = tests failing), advancing one frame per real second. That needs a timer,
# so hud-install.sh sets refreshInterval=1 in the statusLine config; Claude Code re-runs
# this command every second (plus its event-driven refreshes on each message / after
# compact), which both animates the beacon AND keeps every other slot fresh. The cost is
# waking jq+git once a second on idle — a deliberate battery trade the owner opted into
# for a live status line (a no-color terminal falls back to a static ●, needing no timer).
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
  # Default terminal palette — plain ANSI SGR colors, not pinned 24-bit RGB, so the
  # line inherits the user's terminal theme (the same colors the Claude Code CLI
  # itself renders with) and adapts to light/dark and any scheme. Green = on,
  # yellow = attention, cyan = info, red = alert; GREY (dim bright-black) recedes
  # OFF features. No truecolor branch to keep re-tuning — the terminal owns the hue.
  G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; R=$'\033[31m'
  B=$'\033[1m'; D=$'\033[2m'; GREY=$'\033[90m'; X=$'\033[0m'
fi
# On-demand: print the symbol key and exit (the /hud:legend command). No stdin.
if [ "${1:-}" = "--legend" ]; then hud_legend; exit 0; fi

INPUT=""; [ -t 0 ] || INPUT="$(cat 2>/dev/null || true)"; [ -n "$INPUT" ] || INPUT="{}"
# Portable read into F (no mapfile — that's bash-4-only; stock macOS ships bash 3.2).
# jq emits exactly 6 lines in this fixed order, so F[0..5] map 1:1 to the fields below.
F=()
while IFS= read -r x; do F+=("$x"); done < <(printf '%s' "$INPUT" | jq -r '[
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

# Normalize a linked git worktree to its PRIMARY worktree so per-repo flags key to the
# SAME root task-queue's toggles wrote — otherwise a worktree session's --show-toplevel
# is the worktree path, misses the main-checkout flag, and the status line lies about
# what's on. git-common-dir points at "<primary>/.git"; its parent IS the primary
# worktree (and equals --show-toplevel for a non-worktree repo, so this is a no-op
# there). A SUBMODULE's common-dir is <super>/.git/modules/<name>, whose parent is INSIDE
# .git (not a working root, shared across sibling submodules) — detect that and fall back
# to the submodule's own --show-toplevel. tq_root_for_cwd does the identical resolution;
# drift-guard.bats asserts they agree.
ROOT=""
GCD="$(git -C "$CWD" rev-parse --git-common-dir 2>/dev/null || true)"
if [ -n "$GCD" ]; then
  ROOT="$(cd "$CWD" 2>/dev/null && cd "$(dirname "$GCD")" 2>/dev/null && pwd)"
  case "$ROOT" in */.git|*/.git/*) ROOT="" ;; esac   # submodule/gitdir-inside-.git → not a real root
fi
[ -n "$ROOT" ] || ROOT="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$CWD")"
SHORT_MODEL="$(printf '%s' "$MODEL" | sed -E 's/^claude-//; s/-[0-9]{8}([^0-9]|$)/\1/')"

AGENT="$(hud_agent "$ROOT")"
AWAY="$(hud_away "$ROOT")"
VERIFY="$(hud_verify "$SID")"
REVIEW="$(hud_review_pending "$ROOT")"   # 🔒 return-review gate armed (edits blocked)
DESIGN="$(hud_design_pending "$SID")"    # 🎨 design preview pending (edits blocked)
BRANCH="$(hud_branch "$CWD")"
# Dirty-count + ahead/behind are only shown next to the branch (wide terminals, in
# a repo). Skip their git calls otherwise — they run every render.
DIRTY=""; AB=""
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  DIRTY="$(hud_dirty "$CWD")"
  AB="$(hud_ahead_behind "$CWD")"
fi

# 1) Health beacon — an ANIMATED braille-orbit spinner (dots sweeping around the cell),
# colored by overall health: red = tests failing, yellow = autopilot (autonomous, an
# attention state), green otherwise. One frame per real second, selected by the clock,
# so the statusLine config sets refreshInterval=1 to repaint it (see hud-install.sh).
# On a no-color / dumb terminal we can't spin a colored glyph meaningfully, so it falls
# back to a static ● (and no timer is needed there).
BCOL="$G"
[ "$AWAY" = "1" ] && BCOL="$Y"
[ "$VERIFY" = "fail" ] && BCOL="$R"
BEACON_FRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)   # dots rotating clockwise around the border
if [ -n "$G" ]; then
  BEACON="${BEACON_FRAMES[$(( $(date +%s 2>/dev/null || echo 0) % ${#BEACON_FRAMES[@]} ))]}"
else
  BEACON="●"
fi

# The line is three ZONES joined by a dim divider (│): [health & alerts] │ [feature
# modes] │ [context]. Within a zone slots are single-space separated so the group
# reads as one unit; an empty zone (and its divider) collapses. Grouped layout chosen
# by the owner over the old flat SEP-joined list.
DIVSEP=" $GREY│$X "
join_slots() { local out="" s; for s in "$@"; do [ -n "$s" ] && out="${out:+$out }$s"; done; printf '%s' "$out"; }

# Zone 1 — health & alerts: the beacon, the tests outcome, any disabled safety floors,
# the two active EDIT-GATES (🎨 design-preview pending · 🔒 return-review armed — each
# blocks edits, so like the safety marker they never shed on a narrow terminal), the ❓
# count (parked decisions the owner reviews) and the ⏳ count (items blocked on a manual
# owner action).
Z1=("$BCOL$B$BEACON$X")
# Safety shield — ALWAYS shown, right after the beacon: green 🛡 when every floor is on,
# red 🛡✗N when N are off. A permanent positive shield (chosen for a non-technical owner
# who verifies by SEEING) actively signals "protected" rather than leaving it to the
# absence-means-safe convention; the ✗N suffix distinguishes the alarm state even with
# color off. Never sheds on a narrow terminal — safety is the one thing that always shows.
DISABLED="$(hud_floors_disabled 2>/dev/null || true)"
if [ -n "$DISABLED" ]; then
  NOFF="$(printf '%s' "$DISABLED" | wc -w | tr -d ' ')"
  Z1+=("$R$B🛡✗$NOFF$X")     # a disabled guard makes the green dot misleading
else
  Z1+=("$G$B🛡$X")           # all floors on
fi
# Tests outcome — a self-colored emoji (✅ pass / ❌ fail / ⚠️ timeout), no "tests" word and
# no ANSI wrap: the emoji carries its own color, so it stays legible even on a no-color
# terminal (where the old ✓/✗ went monochrome). Hidden entirely when never run.
case "$VERIFY" in
  pass)    Z1+=("✅") ;;
  fail)    Z1+=("❌") ;;
  timeout) Z1+=("⚠️") ;;
esac
# Edit-GATES keep a one-word tag while armed (🎨 design · 🔒 review): unlike the toggles,
# a bare lock that's silently BLOCKING your edits is a "why can't I save?" trap — the word
# earns its space exactly where the icon is both cryptic and consequential.
[ "$DESIGN" = "1" ] && Z1+=("$Y$B🎨 design$X")   # design preview pending — edits gated until shown
[ "$REVIEW" = "1" ] && Z1+=("$Y$B🔒 review$X")   # return-review armed — edits gated until the ❓ pile clears (sits next to ❓)
OPENQ="$(hud_open_questions "$SID" 2>/dev/null || printf 0)"
[ "${OPENQ:-0}" -gt 0 ] 2>/dev/null && Z1+=("$Y$B❓$OPENQ$X")
BLOCKED="$(hud_blocked "$SID" 2>/dev/null || printf 0)"
[ "${BLOCKED:-0}" -gt 0 ] 2>/dev/null && Z1+=("$Y$B⏳$BLOCKED$X")

# Zone 2 — feature modes as bare ICONS, PRESENCE = on (✈️ autopilot · 🤖 agents). The word
# was redundant next to a self-evident icon, and presence-as-signal removes the color-off
# ambiguity a greyed "off" icon would have: the icon appears only when the mode is ON, and
# is simply absent otherwise (the whole zone collapses when both are off — the shipped
# default). Discoverability of what the icons mean lives in /hud:legend.
FEAT=""
[ "$AWAY"  = "1" ] && FEAT="✈️"
[ "$AGENT" = "1" ] && FEAT="${FEAT:+$FEAT }🤖"

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
    Z3+=("${D}⇡$HIN ⇣${HOUT:-0}$X")
  fi
fi
if [ "$NARROW" -eq 0 ] && [ -n "$BRANCH" ]; then
  # Repo-name anchor, just left of the branch — glanceable "which project is this" for a
  # multi-repo owner with several panes open. It's the basename of the already-computed
  # ROOT (no extra git call), truncated so a long name can't crowd the signals, and it
  # rides in the wide-only branch block so it's the first context to shed on a narrow term.
  RNAME="$(basename "$ROOT" 2>/dev/null || true)"
  [ "${#RNAME}" -gt 14 ] && RNAME="${RNAME:0:13}…"
  [ -n "$RNAME" ] && Z3+=("$D$RNAME$X")
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
