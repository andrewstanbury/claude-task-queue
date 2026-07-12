#!/usr/bin/env bash
# statusline — a minimal read-only status line: the companion's one glance surface.
# Shows: ⠋ animated health beacon · │ 🛡 secret gate │ (🛡✗ if disabled) · model · ✈️ autopilot ·
# ⇡ input ⇣ output tokens · ◻ open · ❓ parked · ⏳ blocked tasks · project · branch (+ *N changes,
# ↑ahead ↓behind). No hooks, no writes,
# no model cost — it only reads the JSON Claude Code pipes on stdin plus the companion's own task
# store and git. The beacon advances one braille frame per real second, so wire it with
# refreshInterval:1 (which /companion:setup sets) to repaint on a timer:
#   { "statusLine": { "type": "command", "command": "bash <THIS>", "refreshInterval": 1 } }
set -uo pipefail

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ]; then G=""; Y=""; C=""; R=""; B=""; D=""; X="";
else G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; R=$'\033[31m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'; fi

command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"
in=""; [ -t 0 ] || in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || in="{}"
read -r MODEL SID CWD ITOK OTOK < <(printf '%s' "$in" | jq -r '
  [ (.model.display_name // .model.id // "?"),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0) ] | @tsv' 2>/dev/null)
[ -n "${CWD:-}" ] || CWD="$PWD"
MODEL="$(printf '%s' "${MODEL:-?}" | sed -E 's/^claude-//; s/-[0-9]{8}$//')"

# humanize a token count: <1000 as-is, else N.Nk / N.NM (integer math, no bc).
hum() { local n="${1%%.*}"; case "$n" in ''|*[!0-9]*) printf '0'; return;; esac
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; elif [ "$n" -lt 1000000 ]; then printf '%s.%sk' "$((n/1000))" "$(((n%1000)/100))";
  else printf '%s.%sM' "$((n/1000000))" "$(((n%1000000)/100000))"; fi; }

# Tasks in this session's companion store, split by state: ◻ open · ❓ parked · ⏳ blocked
# (parked/blocked detected by the ❓/⏳ subject prefix — the same convention as the queue and
# the return-review gate). One jq pass emits the three counts, tab-separated.
NOPEN=0; NPARK=0; NBLOCK=0
store="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}/$SID"
if [ -n "${SID:-}" ] && [ -d "$store" ]; then
  files=("$store"/*.json)
  if [ -e "${files[0]}" ]; then
    read -r NOPEN NPARK NBLOCK < <(jq -rs '
      [ .[] | select(.status=="pending" or .status=="in_progress") | (.subject//"") | sub("^\\s+";"") ] as $s
      | [ ($s | map(select((startswith("❓") or startswith("⏳")) | not)) | length),
          ($s | map(select(startswith("❓"))) | length),
          ($s | map(select(startswith("⏳"))) | length) ] | @tsv' "${files[@]}" 2>/dev/null)
  fi
fi
case "$NOPEN"  in ''|*[!0-9]*) NOPEN=0;;  esac
case "$NPARK"  in ''|*[!0-9]*) NPARK=0;;  esac
case "$NBLOCK" in ''|*[!0-9]*) NBLOCK=0;; esac

# 🛡 secret gate (the one enforced guarantee) — green shield on, red ✗ when disabled.
# Brace every var: on macOS's bash 3.2 an unbraced `$B` directly before the 🛡 glyph swallows the
# emoji's leading byte into the variable name, which `set -u` then rejects (a real macOS-CI crash).
if [ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ]; then SHIELD="${R}${B}🛡✗${X}"; else SHIELD="${G}${B}🛡${X}"; fi

# repo root (git toplevel, else CWD) — one rev-parse, reused for project name + autopilot/gate flags.
ROOT="$(companion_root "$CWD")"; PROJ="${ROOT##*/}"

# git: branch + dirty count + ahead/behind in one read (branch.ab = "+A -B", upstream only).
BRANCH=""; DIRTY=0; AB=""
while IFS= read -r l; do case "$l" in
  '# branch.head '*) BRANCH="${l#\# branch.head }";;
  '# branch.ab '*)   AB="${l#\# branch.ab }";;
  '#'*) :;;
  ?*) DIRTY=$((DIRTY+1));;
esac done < <(git -C "$CWD" status --porcelain=v2 --branch 2>/dev/null)
AHEAD=0; BEHIND=0
if [ -n "$AB" ]; then a="${AB%% *}"; AHEAD="${a#+}"; b="${AB##* }"; BEHIND="${b#-}"; fi
case "$AHEAD"  in ''|*[!0-9]*) AHEAD=0;;  esac
case "$BEHIND" in ''|*[!0-9]*) BEHIND=0;; esac

# ✈️ autopilot when it's armed for this repo (an attention state) — also tints the beacon yellow.
APON=0; companion_autopilot_on "$ROOT" && APON=1
AP=""; [ "$APON" = 1 ] && AP=" ${Y}✈️${X}"

# ⠋ animated health beacon — one braille-orbit frame per real second (selected by the clock, so
# the statusLine config needs refreshInterval:1 to repaint it — /companion:setup wires that).
# Green normally, yellow under autopilot. A no-color/dumb terminal can't spin a colored glyph, so
# it falls back to a static ● (and needs no timer).
BFRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BCOL="$G"; [ "$APON" = 1 ] && BCOL="$Y"
if [ -n "$G" ]; then BEACON="${BFRAMES[$(( $(date +%s 2>/dev/null || echo 0) % ${#BFRAMES[@]} ))]}"; else BEACON="●"; fi

# assemble (│ = dim divider): ⠋ │ 🛡 │ model [✈️] · ⇡in ⇣out │ ◻open ❓parked ⏳blocked │ project ⎇branch *changes
DIV=" ${D}│${X} "
out="${BCOL}${B}${BEACON}${X}${DIV}${SHIELD}${DIV}${C}${MODEL}${X}${AP}"
[ "${ITOK:-0}" -gt 0 ] 2>/dev/null && out="$out ${D}⇡$(hum "$ITOK") ⇣$(hum "$OTOK")$X"
# tasks: ◻ open always; ❓ parked · ⏳ blocked only when present (attention states).
TASKS="${C}${B}◻$NOPEN${X}"
[ "$NPARK"  -gt 0 ] && TASKS="$TASKS ${Y}${B}❓$NPARK${X}"
[ "$NBLOCK" -gt 0 ] && TASKS="$TASKS ${Y}${B}⏳$NBLOCK${X}"
out="$out${DIV}$TASKS"
[ -n "$PROJ" ] && out="$out $PROJ"
if [ -n "$BRANCH" ]; then
  out="$out ${C}${B}⎇ $BRANCH${X}"
  [ "$DIRTY"  -gt 0 ] && out="$out ${Y}${B}*$DIRTY${X}"
  [ "$AHEAD"  -gt 0 ] && out="$out ${C}${B}↑$AHEAD${X}"
  [ "$BEHIND" -gt 0 ] && out="$out ${C}${B}↓$BEHIND${X}"
fi
printf '%s\n' "$out"
