#!/usr/bin/env bash
# flow.sh — the workflow diagram in its hand-drawn visual format, but filled
# DYNAMICALLY from the repo so it never drifts: lifecycle wiring from each
# plugin's hooks.json, the review-loop steps parsed from tq-capture's own
# instruction, versions from plugin.json, and the live permission state from
# settings.json. Stable per-script role blurbs are curated (with a header-comment
# fallback) to keep the layout readable; everything structural is derived.
#
# The ONE sanctioned human-facing artifact in this otherwise artifact-free repo
# (owner-requested). Run: ./flow.sh or make flow. Colour auto-disables when stdout
# isn't a terminal (piped/captured) or under NO_COLOR / TERM=dumb.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || [ ! -t 1 ]; then
  C=''; G=''; Y=''; B=''; M=''; D=''; W=''; X=''
else
  C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'
  M=$'\e[35m'; D=$'\e[2m'; W=$'\e[1m'; X=$'\e[0m'
fi
line() { printf '%s\n' "$1"; }
pcolor() { case "$1" in task-queue) printf '%s' "$C" ;; tidy) printf '%s' "$G" ;;
                        charter) printf '%s' "$Y" ;; hud) printf '%s' "$B" ;; *) printf '%s' "$W" ;; esac; }

# header-comment purpose (line 2, after the em-dash) — fallback for un-curated scripts.
purpose() { local p; p="$(sed -n '2p' "$1" 2>/dev/null | sed 's/^# *//')"; case "$p" in *"— "*) p="${p#*— }" ;; esac; printf '%s' "$p"; }

# curated one-line role blurb by basename; falls back to the header purpose.
blurb() {
  case "$(basename "$1")" in
    charter-standard.sh)  printf 'gate docs · decisions anchor · owner loop · scar tissue' ;;
    charter-align-gate.sh) printf 'align change vs recorded decisions · block on a reversal' ;;
    tidy-standard.sh)     printf 'clean-as-you-go standard' ;;
    tq-resume.sh)         printf 'queue policy · resume bridge · hydrate backlog' ;;
    tq-capture.sh)        printf 'the interpret→present→approve review loop' ;;
    tq-verify.sh)         printf 'intent→outcome check (built ≟ what was asked)' ;;
    tidy-touch.sh)        printf 'format · lint · blast-radius · size' ;;
    tidy-verify.sh)       printf 'tests green · regression gate (untested hotspots) · prune' ;;
    *)                   purpose "$1" ;;
  esac
}

# "plugin|script-path" for every hook wired to event $1, across all plugins.
wired() {
  local h plug cmd path
  for h in plugins/*/hooks/hooks.json; do
    [ -f "$h" ] || continue
    plug="$(basename "$(dirname "$(dirname "$h")")")"
    while IFS= read -r cmd; do
      path="$(printf '%s' "$cmd" | grep -oE 'bin/[A-Za-z0-9_-]+\.sh' | head -1)"
      [ -n "$path" ] && printf '%s|plugins/%s/%s\n' "$plug" "$plug" "$path"
    done < <(jq -r --arg e "$1" '.hooks[$e][]?.hooks[]?.command // empty' "$h" 2>/dev/null)
  done | sort -u
}
first_path() { wired "$1" | head -1 | cut -d'|' -f2; }

# --- derived state ---------------------------------------------------------
S="$HOME/.claude/settings.json"
if [ -f "$S" ]; then
  perm="mode=$(jq -r '.permissions.defaultMode // "default"' "$S" 2>/dev/null)"
  perm="$perm · deny($(jq -r '(.permissions.deny//[])|length' "$S" 2>/dev/null))"
  perm="$perm · ask($(jq -r '(.permissions.ask//[])|length' "$S" 2>/dev/null))"
  perm="$perm · agent-mode=$(jq -r '.env.CLAUDE_TQ_AGENT_MODE // "off"' "$S" 2>/dev/null)"
else
  perm="auto · deny rm-rf · ask force-push"
fi
sl=''; for d in plugins/*/; do [ -f "${d}hooks/hooks.json" ] || sl="$(basename "$d")"; done
sha="$(git rev-parse --short HEAD 2>/dev/null || printf '?')"
LOOPRAW="$(grep -m1 '(1) INTERPRET —' plugins/task-queue/bin/tq-capture.sh 2>/dev/null \
           | awk '{gsub(/\([0-9]\)/,"\n&")}1' | grep -E '^\([0-9]\)')"

# --- render ----------------------------------------------------------------
line ""
line "  ${W}COMPANION WORKFLOW${X}  ${D}— where each feature fires · live @ ${sha}${X}"
line "  ${D}────────────────────────────────────────────────────────────${X}"
line ""
line "  ${M}▐▌ ALWAYS-ON${X}  ${M}native permissions${X} ${D}(${perm})${X}"
[ -n "$sl" ] && line "  ${D}             ${X}${B}${sl} statusLine${X} ${D}●health ✓tests ⏸paused 🤖agent ctx%${X}"
line ""

line "  ${G}●${X} ${W}SessionStart${X} ${D}· once ·${X}"
while IFS='|' read -r plug path; do
  [ -n "$plug" ] || continue
  line "  ${D}┊${X}   $(pcolor "$plug")$(printf '%-11s' "$plug")${X}${D}$(blurb "$path")${X}"
done <<< "$(wired SessionStart)"
line "  ${D}▼${X}"

up="$(first_path UserPromptSubmit)"
line "  ${C}◆${X} ${W}you type a prompt${X}  ${D}→ UserPromptSubmit →${X} ${C}$(basename "${up:-tq-capture.sh}" .sh)${X}"
line "  ${D}┊${X}"
line "  ${D}┊  trivial or paused → runs straight in auto (silent)${X}"
line "  ${D}▼${X}  ${D}substantive (multi-step / consequential)${X}"
if [ -n "$LOOPRAW" ]; then
  title=''
  while IFS= read -r ln; do
    nm="$(printf '%s' "$ln" | sed -E 's/^\([0-9]\) ([A-Za-z]+).*/\1/')"; title="${title:+$title → }$nm"
  done <<< "$LOOPRAW"
  line "  ${C}┏━ ${title}${X} ${D}· the review loop ·${X}"
  while IFS= read -r ln; do
    num="${ln:1:1}"
    nm="$(printf '%s' "$ln" | sed -E 's/^\([0-9]\) ([A-Za-z]+).*/\1/' | tr '[:upper:]' '[:lower:]')"
    desc="$ln"; case "$desc" in *"— "*) desc="${desc#*— }" ;; *) desc="${desc#* }" ;; esac
    desc="$(printf '%s' "$desc" | sed 's/["[:space:];,]*$//')"
    [ "${#desc}" -gt 46 ] && desc="${desc:0:45}…"
    line "  ${C}┃${X}  ${num} ${W}$(printf '%-9s' "$nm")${X} ${D}${desc}${X}"
  done <<< "$LOOPRAW"
  line "  ${C}┗━${X}"
  line "  ${D}▼${X}"
fi

line "  ${W}⚙ Claude works the queue${X} ${D}· native task list ·${X}"
line "  ${D}┊${X}"
while IFS='|' read -r plug path; do
  [ -n "$path" ] || continue
  line "  ${D}┊${X} ${D}on each edit →${X} $(pcolor "$plug")$(basename "$path" .sh)${X}  ${D}$(blurb "$path")${X}"
done <<< "$(wired PostToolUse)"
first=1
while IFS='|' read -r plug path; do
  [ -n "$path" ] || continue
  if [ "$first" = 1 ]; then lbl="on finish    →"; first=0; else lbl="             →"; fi
  line "  ${D}┊${X} ${D}${lbl}${X} $(pcolor "$plug")$(basename "$path" .sh)${X}  ${D}$(blurb "$path")${X}"
done <<< "$(wired Stop)"
line "  ${D}▼${X}"
line "  ${G}✓${X} ${W}done${X}  ${D}→${X} ${B}hud${X} ${D}flips to${X} ${G}✓ tests${X}"
line ""

cmds=''
for c in plugins/*/commands/*.md; do [ -f "$c" ] && cmds="$cmds /$(basename "$(dirname "$(dirname "$c")")"):$(basename "$c" .md)"; done
wiredset="$(for e in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop Notification; do wired "$e"; done \
            | cut -d'|' -f2 | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done | sort -u)"
togs=''
for f in plugins/*/bin/*.sh; do
  bn="$(basename "$f")"; printf '%s\n' "$wiredset" | grep -qx "$bn" && continue
  sed -n '2p' "$f" 2>/dev/null | grep -qiE 'pause|resume|toggle' && togs="$togs ${bn%.sh}"
done
od="  ${D}on demand:${X}"
[ -n "$cmds" ] && od="$od  ${Y}commands${X}${D}${cmds}${X}"
[ -n "$togs" ] && od="$od   ${C}toggles${X}${D}${togs}${X}"
line "$od"
line ""
line "  $(pcolor task-queue)■${X} task-queue ${D}orchestrate${X}   $(pcolor tidy)■${X} tidy ${D}change${X}   $(pcolor charter)■${X} charter ${D}know${X}   $(pcolor hud)■${X} hud ${D}show${X}"
line ""
