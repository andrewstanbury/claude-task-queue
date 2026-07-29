#!/usr/bin/env bash
# statusline — a minimal read-only status line: the companion's one glance surface.
# Shows, in R34 section order: animated health beacon · v<version> · active features (🛡✗ only
# when the gate is off · ✈️ autopilot · 📦 ship-mode) · the queue (📋 open · ❓ parked · ⏳ blocked) ·
# 5h/7d ACCOUNT rate-limit bars (R76 — absent unless the payload carries them) · model · ⇡ input
# ⇣ output tokens · project · branch (+ *N changes, ↑ahead ↓behind). No hooks, no writes,
# no model cost — it only reads the JSON Claude Code pipes on stdin plus the companion's own task
# store and git. The beacon frame is a wall-clock function (one position per second); the bar
# repaints on its timer, so wire it with refreshInterval:3 (which /companion:setup sets, R32·5):
#   { "statusLine": { "type": "command", "command": "bash <THIS>", "refreshInterval": 3 } }
set -uo pipefail

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ]; then G=""; Y=""; C=""; R=""; B=""; D=""; X="";
else G=$'\033[32m'; Y=$'\033[33m'; C=$'\033[36m'; R=$'\033[31m'; B=$'\033[1m'; D=$'\033[2m'; X=$'\033[0m'; fi

command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"
# Plugin version (so it's clear at a glance which companion is installed) — read from the manifest.
VERSION="$(jq -r '.version // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
in=""; [ -t 0 ] || in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || in="{}"
# Split on US (0x1f), NOT tab. Tab is IFS *whitespace*, so `IFS=$'\t' read` collapses a run of
# tabs into one delimiter — every field after an EMPTY one silently shifts left. That was dormant
# while all five fields were always populated; the optional .rate_limits fields below are empty
# whenever a window is absent, which would mis-assign 7d's percentage to the 5h bar. A
# non-whitespace separator preserves empty fields positionally, so absence stays absence.
# The `gsub` is NOT optional: `@tsv` escaped \n\r\t for us, plain `join` escapes nothing, so a
# newline in a path or model name would split the record and `read` would take only the first
# line — silently dropping the tokens, both bars and the git segment. Neutralize the two
# characters that can break the framing (newline/CR) and the separator itself.
IFS=$'\x1f' read -r MODEL SID CWD ITOK OTOK RL5 RL7 RL5R RL7R < <(printf '%s' "$in" | jq -r '
  [ (.model.display_name // .model.id // "?"),
    (.session_id // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.total_input_tokens // 0),
    (.context_window.total_output_tokens // 0),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.resets_at // "") ] | map(tostring | gsub("[\n\r\u001f]"; " ")) | join("\u001f")' 2>/dev/null)
[ -n "${CWD:-}" ] || CWD="$PWD"
MODEL="$(printf '%s' "${MODEL:-?}" | sed -E 's/^claude-//; s/-[0-9]{8}$//')"

# humanize a token count: <1000 as-is, else N.Nk / N.NM (integer math, no bc).
hum() { local n="${1%%.*}"; case "$n" in ''|*[!0-9]*) printf '0'; return;; esac
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; elif [ "$n" -lt 1000000 ]; then printf '%s.%sk' "$((n/1000))" "$(((n%1000)/100))";
  else printf '%s.%sM' "$((n/1000000))" "$(((n%1000000)/100000))"; fi; }

# ▰▱ ACCOUNT rate-limit bars (R76) — the one thing on this line that is about neither this repo
# nor this session. Claude Code hands the subscription's rolling-window usage straight to the
# status line in `.rate_limits`, so this costs **no API call, no network, no token** — it is the
# same stdin payload already parsed above. Two windows: **5h** (the one that stops you mid-session)
# and **7d** (the weekly burn). NOT a billing cycle — the plans meter on rolling windows, so a
# "this month" bar would be fiction.
# The field is ABSENT for API-key users and for Pro/Max until the first API response of a session,
# and each window can vanish independently — so every path renders NOTHING rather than a
# placeholder or a zero (best-effort, R7/R68: a status line never invents a number it wasn't given).
# Percentages arrive as floats ("23.5"); bash 3.2 has no float math, so truncate to int first.
rlbar() {  # $1 used_percentage (float|"") · $2 label · $3 resets_at (epoch|"")
  local p="${1%%.*}" lab="$2" rst="${3%%.*}" n i bar col s now left
  case "${p:-}" in ''|*[!0-9]*) return 0;; esac
  # A long all-digit string passes the guard above but overflows the shell's integer
  # compare (stderr spew every refresh). Length-clamp first, then value-clamp.
  [ "${#p}" -gt 3 ] && p=100
  [ "$p" -gt 100 ] && p=100
  # 5 cells, FLOOR — so only a genuinely exhausted window shows five filled. Rounding up would
  # paint 87% and 100% identically, which is the one reading that has to stay distinguishable.
  # Floor alone would hide 1-19% entirely, so anything above zero lights at least one cell.
  n=$(( p / 20 )); [ "$p" -gt 0 ] && [ "$n" -eq 0 ] && n=1
  # 0 < raw < 1 truncates to p=0: still in use, so light one cell rather than read as idle.
  case "$1" in 0.*[1-9]*) [ "$n" -eq 0 ] && n=1 ;; esac
  bar=""; i=0
  while [ "$i" -lt 5 ]; do
    if [ "$i" -lt "$n" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
    i=$((i+1))
  done
  col="$G"; [ "$p" -ge 60 ] && col="$Y"; [ "$p" -ge 85 ] && col="$R"
  s=" ${D}${lab}${X}${col}${bar}${X}${col}${B}${p}%${X}"
  # Reset countdown only once the window is actually tight: on an always-on segment width is the
  # scarce resource, and "82%" is only actionable when you also know it clears in 40 minutes.
  if [ "$p" -ge 80 ] && [ -n "${rst:-}" ]; then
    case "$rst" in *[!0-9]*) :;; *)
      now="$(date +%s 2>/dev/null || echo 0)"; left=$(( rst - now ))
      if [ "$left" -gt 0 ]; then
        if   [ "$left" -ge 86400 ]; then s="$s ${D}↻$((left/86400))d${X}"
        elif [ "$left" -ge 3600  ]; then s="$s ${D}↻$((left/3600))h${X}"
        else                             s="$s ${D}↻$((left/60))m${X}"; fi
      fi ;;
    esac
  fi
  printf '%s' "$s"
}

# Tasks in this session's companion store, split by state: 📋 open · ❓ parked · ⏳ blocked
# (parked/blocked detected by the ❓/⏳ subject prefix — the same convention as the queue and
# the return-review gate). One jq pass emits the three counts, tab-separated.
NOPEN=0; NPARK=0; NBLOCK=0; NDOING=0
store="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}/$SID"
if [ -n "${SID:-}" ] && [ -d "$store" ]; then
  files=("$store"/*.json)
  if [ -e "${files[0]}" ]; then
    read -r NOPEN NPARK NBLOCK NDOING < <(jq -rs '
      [ .[] | select(.status=="pending" or .status=="in_progress") ] as $o
      | ($o | map((.subject//"") | sub("^\\s+";""))) as $s
      | [ ($s | map(select((startswith("❓") or startswith("⏳")) | not)) | length),
          ($s | map(select(startswith("❓"))) | length),
          ($s | map(select(startswith("⏳"))) | length),
          ($o | map(select(.status=="in_progress")) | length) ] | @tsv' "${files[@]}" 2>/dev/null)
  fi
fi
case "$NOPEN"  in ''|*[!0-9]*) NOPEN=0;;  esac
case "$NPARK"  in ''|*[!0-9]*) NPARK=0;;  esac
case "$NBLOCK" in ''|*[!0-9]*) NBLOCK=0;; esac
case "$NDOING" in ''|*[!0-9]*) NDOING=0;; esac

# repo root (git toplevel, else CWD) — one rev-parse, reused for project name + autopilot/gate flags.
ROOT="$(companion_root "$CWD")"; PROJ="${ROOT##*/}"

# 🛡️✗ secret-gate WARNING — shown ONLY when the gate is DISABLED (the contextually-important state:
# a safety feature is off). When the gate is on (the default), NO icon: a persistent "all fine" badge
# is noise, so the guard shows an icon only when there's something to say (owner request 2026-07-19).
# ✗ fires by the same global-then-per-repo order the hook resolves (R50): the env var kills the gate
# everywhere; a per-repo `secret=off` flag kills it here. Leading space so it slots into the features
# block. Brace every var: on macOS's bash 3.2 an unbraced `$B` before the 🛡 glyph swallows the emoji's
# leading byte into the variable name (set -u then rejects it — a real macOS-CI crash). 🛡️ carries
# U+FE0F for full emoji width, matching ✈️/📦.
SHIELD=""
if [ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] || companion_feature_off secret "$ROOT"; then
  SHIELD=" ${R}${B}🛡️✗${X}"; fi

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
# ⚡ appended when DECISIVE mode is also on (R59): autopilot auto-decides reversible choices rather
# than parking — a distinct, louder state the owner should see at a glance.
APON=0; companion_autopilot_on "$ROOT" && APON=1
# One space before each feature icon (🛡 ✈️ 📦) — single, even separation.
AP=""
if [ "$APON" = 1 ]; then
  AP=" ${Y}✈️${X}"
  companion_decisive_on "$ROOT" && AP=" ${Y}${B}✈️⚡${X}"
  # 🧹 sweep (R77) — a louder state still: autopilot is also working the already-parked pile.
  companion_sweep_on "$ROOT" && AP="${AP%"${X}"}🧹${X}"
fi

# ⠋ health beacon — animates ONLY while there's work in motion (autopilot draining or a task
# in-progress); otherwise a static ● (R30·d9 — no pointless idle spinning). The frame is a
# wall-clock function (advances one position per second), repainted on the refresh timer —
# refreshInterval:3 (R32·5), so it visibly steps every ~3s. Green normally, yellow under autopilot.
# A no-color/dumb terminal can't spin a colored glyph, so it's always ● there.
# (Note: refreshInterval wakes the command every ~3s — the frame keeps advancing while active;
# dropping refreshInterval entirely is the fully-static option.)
ACTIVE=0; { [ "$APON" = 1 ] || [ "$NDOING" -gt 0 ]; } && ACTIVE=1
BFRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BCOL="$G"; [ "$APON" = 1 ] && BCOL="$Y"
if [ -n "$G" ] && [ "$ACTIVE" = 1 ]; then
  BEACON="${BFRAMES[$(( $(date +%s 2>/dev/null || echo 0) % ${#BFRAMES[@]} ))]}"
else
  BEACON="●"
fi

# assemble (: = dim divider, owner-picked over │/- 2026-07-19), plugin-relevance order (R34):
# ⠋ [: features] : 📋 tasks : model ⇡in ⇣out : project ⎇branch *changes
# ACTIVE FEATURES = 🛡️✗ gate-off-warning · ✈️ autopilot · 📦 ship-mode — each shows only when
# relevant, so the whole section (and its divider) is OMITTED when nothing is active (owner request:
# the guard shows an icon only when contextually important). Then the QUEUE, then model/tokens · git.
DIVC="${D}:${X}"; DIV=" $DIVC "
SHIP=""; companion_ship_on "$ROOT" && SHIP=" ${Y}${B}📦${X}"
FEAT="${SHIELD}${AP}${SHIP}"          # each item carries its own leading space; empty when none active
# The queue section — shown ONLY when it has something to say, like every other indicator here
# (🛡✗ only when the gate is off, ✈️/📦 only when armed, ↑↓ only when diverged). `📋 0` used to render
# permanently, which is the always-on zero that rule exists to prevent; a drained queue now renders
# no section at all, and the section reappearing IS the signal that there is work.
TASKS=""
[ "$NOPEN"  -gt 0 ] && TASKS="${C}${B}📋 $NOPEN${X}"
[ "$NPARK"  -gt 0 ] && TASKS="${TASKS:+$TASKS }${Y}${B}❓ $NPARK${X}"
[ "$NBLOCK" -gt 0 ] && TASKS="${TASKS:+$TASKS }${Y}${B}⏳ $NBLOCK${X}"
out="${BCOL}${B}${BEACON}${X}"
[ -n "${VERSION:-}" ] && out="$out ${D}v$VERSION${X}"
[ -n "$FEAT" ] && out="$out $DIVC$FEAT"   # features section only when something's active
[ -n "$TASKS" ] && out="$out${DIV}${TASKS}"   # omit the divider too when the queue is quiet
# account usage sits next to the session's own consumption — both bars, or the section is omitted
RL="$(rlbar "${RL5:-}" 5h "${RL5R:-}")$(rlbar "${RL7:-}" 7d "${RL7R:-}")"
[ -n "$RL" ] && out="$out $DIVC$RL"
out="$out${DIV}${C}${MODEL}${X}"
[ "${ITOK:-0}" -gt 0 ] 2>/dev/null && out="$out ${D}⇡$(hum "$ITOK") ⇣$(hum "$OTOK")$X"
[ -n "$PROJ" ] && out="$out${DIV}$PROJ"
if [ -n "$BRANCH" ]; then
  out="$out ${C}${B}⎇ $BRANCH${X}"
  [ "$DIRTY"  -gt 0 ] && out="$out ${Y}${B}*$DIRTY${X}"
  [ "$AHEAD"  -gt 0 ] && out="$out ${C}${B}↑$AHEAD${X}"
  [ "$BEHIND" -gt 0 ] && out="$out ${C}${B}↓$BEHIND${X}"
fi
printf '%s\n' "$out"
