#!/usr/bin/env bash
# hud — a consolidated status line for the companion plugins. One line, rendered
# from the JSON Claude Code pipes to a statusLine command on stdin plus the
# read-only state the sibling plugins maintain. No model calls, no hooks, no
# writes — it only reads and prints, so it can't interfere with anything.
#
# Three zones joined by a dim │ divider; empty slots (and empty zones) collapse:
#   [ ● health · 🎨 design-gate · 🔒 review-gate · ❓ decisions · ⏳ owner-blocked ]
#   [ 🛡 safety(✗N off) · ✈️ autopilot · 🤖 agents ]
#   [ model · tok ⇡in ⇣out · ⎇ branch (+ dirty * · ↑ahead ↓behind) ]
# Decode any symbol on demand with /hud:legend.
#
# Scoped to signals a status line is the BEST surface for — persistent
# state/health you want at a glance. Deliberately NOT re-rendered here: the task
# list (Claude Code shows it natively), docs-health (charter nudges it at session
# start), and last-tidy (ephemeral) — surfacing those again was duplication, and
# the docs mirror was the heaviest cross-plugin maintenance burden.
#
# The beacon is a STATIC ● tinted by health (green = clean/green, yellow = solo mode,
# red = tests failing). It used to be an animated braille spinner advancing one frame per
# second — but that FORCED a per-second (later per-2s) refreshInterval, and on a handheld
# (Steam Deck) waking jq+git ~1800×/hour on idle defeated the CPU's race-to-idle and kept
# fans spinning. The animation was pure decoration, so it was dropped: the status line now
# refreshes EVENT-DRIVEN only (Claude Code repaints it on each message / after compact),
# which keeps every slot fresh at ~zero idle cost. hud-install.sh no longer sets
# refreshInterval. Everything below is written to be cheap per render (one git read, no
# animation timer) since a render can still fire on every message.
#
# Wire it (settings.json):
#   { "statusLine": { "type": "command", "command": "bash <THIS_PATH>" } }
#
# Requires bash 4+, jq. Optional git. Honours NO_COLOR / TERM=dumb.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="${SELF%/*}/$link" ;; esac   # ${%/*} = dirname, no fork
done
THIS_DIR="$(cd "${SELF%/*}" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/hud.sh
. "$PLUGIN_DIR/lib/hud.sh"

# A TERM=dumb terminal can't handle ANSI, so drop color there — same effect as NO_COLOR.
# (The beacon is a plain ● now, which renders anywhere, so this only governs the palette.)
DUMB=""; [ "${TERM:-}" = "dumb" ] && DUMB=1
if [ -n "${NO_COLOR:-}" ] || [ -n "$DUMB" ]; then
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
REVIEW="$(hud_review_pending "$ROOT")"   # 🔒 return-review gate armed (edits blocked)
DESIGN="$(hud_design_pending "$SID")"    # 🎨 design preview pending (edits blocked)
# Branch + dirty-count + ahead/behind in ONE git read (hud_git), replacing four per-render
# git forks. Split the tab-separated fields by hand rather than `read` — tab is whitespace,
# so `IFS=$'\t' read` COLLAPSES the empty dirty field (a clean tree) and shifts the columns.
GITF="$(hud_git "$CWD")"
BRANCH="${GITF%%$'\t'*}"; GITF="${GITF#*$'\t'}"
DIRTY="${GITF%%$'\t'*}";  GITF="${GITF#*$'\t'}"
AHEAD="${GITF%%$'\t'*}";  BEHIND="${GITF##*$'\t'}"

# 1) Health beacon — a STATIC ● tinted by overall health: yellow = autopilot (an attention
# state), green otherwise. It used to animate (braille orbit, one frame/second), but that
# forced a per-second refresh timer whose idle cost spun handheld fans; the animation was
# decoration, so the dot is now static and the line refreshes event-driven (see the header
# note + hud-install.sh, which no longer sets refreshInterval).
BCOL="$G"
[ "$AWAY" = "1" ] && BCOL="$Y"
BEACON="●"

# The line is three ZONES joined by a dim divider (│): [health & alerts] │ [feature
# modes] │ [context]. Within a zone slots are single-space separated so the group
# reads as one unit; an empty zone (and its divider) collapses. Grouped layout chosen
# by the owner over the old flat SEP-joined list.
DIVSEP=" $GREY│$X "
join_slots() { local out="" s; for s in "$@"; do [ -n "$s" ] && out="${out:+$out }$s"; done; printf '%s' "$out"; }

# Zone 1 — health & alerts: the beacon, the two active EDIT-GATES (🎨 design-preview
# pending · 🔒 return-review armed — each blocks edits, so like the safety marker they
# never shed on a narrow terminal), the ❓ count (parked decisions the owner reviews) and
# the ⏳ count (items blocked on a manual owner action).
Z1=("$BCOL$B$BEACON$X")
# Edit-GATES keep a one-word tag while armed (🎨 design · 🔒 review): unlike the toggles,
# a bare lock that's silently BLOCKING your edits is a "why can't I save?" trap — the word
# earns its space exactly where the icon is both cryptic and consequential.
[ "$DESIGN" = "1" ] && Z1+=("$Y$B🎨 design$X")   # design preview pending — edits gated until shown
[ "$REVIEW" = "1" ] && Z1+=("$Y$B🔒 review$X")   # return-review armed — edits gated until the ❓ pile clears (sits next to ❓)
# The open-work count + current-task breadcrumb (the old 📋 N ▸ slot) was REMOVED: the
# full task LIST + status is a scrollable report now, not a status-line glance — task-queue's
# `tq report` prints it on each completion (and on demand). The status line keeps only the
# two owner ALERTS below (❓ decisions · ⏳ owner-blocked): things needing your attention,
# which a persistent glance surface is genuinely the best place for.
OPENQ="$(hud_open_questions "$SID" 2>/dev/null || printf 0)"
[ "${OPENQ:-0}" -gt 0 ] 2>/dev/null && Z1+=("$Y$B❓$OPENQ$X")
BLOCKED="$(hud_blocked "$SID" 2>/dev/null || printf 0)"
[ "${BLOCKED:-0}" -gt 0 ] 2>/dev/null && Z1+=("$Y$B⏳$BLOCKED$X")

# Zone 2 — the safety shield LEADS, then feature modes as bare ICONS, PRESENCE = on
# (✈️ autopilot · 🤖 agents). The word was redundant next to a self-evident icon, and
# presence-as-signal removes the color-off ambiguity a greyed "off" icon would have: a
# mode icon appears only when ON and is simply absent otherwise. The shield anchors the
# zone so it never fully collapses — safety is the one thing that ALWAYS shows (grouped
# here with the modes by owner request; the toggles read as one status cluster).
# Discoverability of what the icons mean lives in /hud:legend.
#
# Safety shield — ALWAYS shown: green 🛡 when every floor is on, red 🛡✗N when N are off.
# A permanent positive shield (chosen for a non-technical owner who verifies by SEEING)
# actively signals "protected" rather than leaving it to the absence-means-safe
# convention; the ✗N suffix distinguishes the alarm state even with color off. Never
# sheds on a narrow terminal — this zone isn't gated on width.
DISABLED="$(hud_floors_disabled 2>/dev/null || true)"
if [ -n "$DISABLED" ]; then
  NOFF="$(printf '%s' "$DISABLED" | wc -w | tr -d ' ')"
  FEAT="$R$B🛡✗$NOFF$X"       # a disabled guard makes the green dot misleading
else
  FEAT="$G$B🛡$X"             # all floors on
fi
[ "$AWAY"  = "1" ] && FEAT="$FEAT ✈️"
[ "$AGENT" = "1" ] && FEAT="$FEAT 🤖"

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
  RNAME="${ROOT##*/}"                       # basename, no fork
  [ "${#RNAME}" -gt 14 ] && RNAME="${RNAME:0:13}…"
  # Normal (bright) weight — NOT dim, NOT bold: the project reads clearly and stands apart
  # from the dim token counts and the cyan branch without the heaviness of bold. A glanceable
  # "which project" anchor, not a footnote.
  [ -n "$RNAME" ] && Z3+=("$RNAME")
  bseg="$C$B⎇ $BRANCH$X"
  [ -n "$DIRTY" ] && bseg="$bseg $Y$B*$DIRTY$X"
  [ "${AHEAD:-0}" -gt 0 ] 2>/dev/null && bseg="$bseg $C$B↑$AHEAD$X"
  [ "${BEHIND:-0}" -gt 0 ] 2>/dev/null && bseg="$bseg $Y$B↓$BEHIND$X"
  Z3+=("$bseg")
fi

# Join the zones with the dim │ divider. The FEATURE zone (Zone 2) is always a wide emoji
# (✈️/🤖): those advance 2 cells but many fonts under-fill the glyph, so a normal " │ " AFTER
# one looks like a double space before the bar. Give the feature zone a TIGHT trailing divider
# (no leading space) so the emoji's own advance supplies that gap and "│ 🤖 │" reads even.
DIVTIGHT="$GREY│$X "        # no leading space — for the boundary right after the wide-emoji zone
Z1J="$(join_slots "${Z1[@]}")"
Z3J="$(join_slots "${Z3[@]}")"
line="$Z1J"
if [ -n "$FEAT" ]; then
  line="${line:+$line$DIVSEP}$FEAT"                 # …│ 🤖
  [ -n "$Z3J" ] && line="$line$DIVTIGHT$Z3J"        # 🤖│ … — tight: the emoji's advance is the gap
elif [ -n "$Z3J" ]; then
  line="${line:+$line$DIVSEP}$Z3J"
fi
printf '%s\n' "$line"
