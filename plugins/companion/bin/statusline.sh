#!/usr/bin/env bash
# statusline — a minimal read-only status line: the companion's one glance surface.
# Shows, in R34 section order: animated health beacon · v<version> · active features (🛡✗ only
# when the gate is off · ✈️ autopilot · 📦 ship-mode) · the queue (📋 open · ❓ parked · ⏳ blocked) ·
# 5h/7d ACCOUNT rate-limit bars (R76 — absent unless the payload carries them) · model · ⇡ input
# ⇣ output tokens · project · branch (+ *N changes, ↑ahead ↓behind). No hooks, no writes,
# no model cost — it only reads the JSON Claude Code pipes on stdin plus the companion's own task
# store and git. The beacon frame is a wall-clock function (one position per second); the bar
# repaints on its timer, so wire it with refreshInterval:10 (which /companion:setup sets; R32·5
# widened by R81 — at 3s this cost ~212 CPU-s/hour/window, fork/exec-dominated):
#   { "statusLine": { "type": "command", "command": "bash <THIS>", "refreshInterval": 10 } }
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
# shellcheck source=../lib/ratelimit.sh
. "$PLUGIN_DIR/lib/ratelimit.sh"
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
# ONE `date` for the whole run — the beacon frame and the git-cache TTL both need wall-clock, and
# a second spawn here is 1/13th of this script's cost (R81: the status line is not a hook, but it
# runs ~1200x/hour per window, so spawn count is the budget that matters).
NOW="$(date +%s 2>/dev/null || echo 0)"
case "$NOW" in ''|*[!0-9]*) NOW=0 ;; esac

# humanize a token count: <1000 as-is, else N.Nk / N.NM (integer math, no bc).
hum() { local n="${1%%.*}"; case "$n" in ''|*[!0-9]*) printf '0'; return;; esac
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"; elif [ "$n" -lt 1000000 ]; then printf '%s.%sk' "$((n/1000))" "$(((n%1000)/100))";
  else printf '%s.%sM' "$((n/1000000))" "$(((n%1000000)/100000))"; fi; }

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
#
# CACHED (R81 follow-up): `git status` walks the whole worktree — 6ms here, 43ms on a 17k-file
# repo — and this runs every refresh whether or not anything changed. A short TTL cache turns most
# refreshes into one file read. The staleness is DELIBERATE and owner-accepted: the dirty count
# and branch may lag up to the TTL. Set CLAUDE_COMPANION_SL_CACHE_TTL=0 to always read live git
# (the bats setup does this, so the render tests measure real state, not a cache).
# Cache-miss is the safe direction: any unreadable/garbled/undated line falls through to live git.
BRANCH=""; DIRTY=0; AB=""; AHEAD=0; BEHIND=0
ttl="${CLAUDE_COMPANION_SL_CACHE_TTL:-10}"
case "$ttl" in ''|*[!0-9]*) ttl=10 ;; esac
cf="$(companion_state_dir)/slcache/$(companion_enc "$CWD")"
hit=0
if [ "$ttl" -gt 0 ] && [ "$NOW" -gt 0 ] && [ -f "$cf" ]; then
  # One line: <ts> <dirty> <ahead> <behind> <branch…>. Branch is LAST because it can contain
  # spaces (a slash-y or oddly-named ref) — everything before it is fixed-width-by-position.
  IFS=' ' read -r cts cdirty cahead cbehind cbranch < "$cf" 2>/dev/null || true
  # Every numeric field must be present AND numeric. Concatenating them first let a TRUNCATED
  # line (just "<ts>", a torn write) pass the digit check with the rest empty — a cache "hit" that
  # silently blanked branch, dirty count and ahead/behind for the whole TTL.
  case "${cts:-x}" in *[!0-9]*) cts="" ;; esac
  case "${cdirty:-x}" in *[!0-9]*) cdirty="" ;; esac
  case "${cahead:-x}" in *[!0-9]*) cahead="" ;; esac
  case "${cbehind:-x}" in *[!0-9]*) cbehind="" ;; esac
  case "${cts}:${cdirty}:${cahead}:${cbehind}" in
    *::*|:*|*:) : ;;
    *) if [ "$((NOW - cts))" -lt "$ttl" ] && [ "$((NOW - cts))" -ge 0 ]; then
         BRANCH="${cbranch:-}"; DIRTY="$cdirty"; AHEAD="$cahead"; BEHIND="$cbehind"; hit=1
       fi ;;
  esac
fi
if [ "$hit" -eq 0 ]; then
  while IFS= read -r l; do case "$l" in
    '# branch.head '*) BRANCH="${l#\# branch.head }";;
    '# branch.ab '*)   AB="${l#\# branch.ab }";;
    '#'*) :;;
    ?*) DIRTY=$((DIRTY+1));;
  esac done < <(git -C "$CWD" status --porcelain=v2 --branch 2>/dev/null)
  if [ -n "$AB" ]; then a="${AB%% *}"; AHEAD="${a#+}"; b="${AB##* }"; BEHIND="${b#-}"; fi
  # Best-effort write (R68): a read-only or missing state dir must never break the status line.
  if [ "$ttl" -gt 0 ] && [ "$NOW" -gt 0 ]; then
    { mkdir -p "${cf%/*}" 2>/dev/null &&
      printf '%s %s %s %s %s\n' "$NOW" "${DIRTY:-0}" "${AHEAD:-0}" "${BEHIND:-0}" "$BRANCH" \
        > "$cf.$$" 2>/dev/null && mv -f "$cf.$$" "$cf" 2>/dev/null; } || rm -f "$cf.$$" 2>/dev/null || true
  fi
fi
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
# refreshInterval:10 (R32·5/R81), so it visibly steps every ~10s. Green normally, yellow on autopilot.
# A no-color/dumb terminal can't spin a colored glyph, so it's always ● there.
# (Note: refreshInterval wakes the command every ~10s — the frame keeps advancing while active;
# dropping refreshInterval entirely is the fully-static, zero-idle-cost option.)
ACTIVE=0; { [ "$APON" = 1 ] || [ "$NDOING" -gt 0 ]; } && ACTIVE=1
BFRAMES=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏); BCOL="$G"; [ "$APON" = 1 ] && BCOL="$Y"
if [ -n "$G" ] && [ "$ACTIVE" = 1 ]; then
  BEACON="${BFRAMES[$(( NOW % ${#BFRAMES[@]} ))]}"
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
# 604800s = the 7d window, from the field's own name — what the pace marker measures against.
RL="$(rlbar "${RL5:-}" 5h "${RL5R:-}")$(rlbar "${RL7:-}" 7d "${RL7R:-}" 604800)"
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
