#!/usr/bin/env bash
# flow.sh — render the companion workflow, DERIVED LIVE from the repo so it never
# drifts: the lifecycle wiring from each plugin's hooks.json, the descriptions
# from each script's header, the review-loop steps from tq-capture's own
# instruction, versions from plugin.json, and the live permission state from
# settings.json. Add/remove/rewire a hook and this view follows automatically.
#
# The ONE sanctioned human-facing artifact in this otherwise artifact-free repo
# (owner-requested). Run it with `./flow.sh` or `make flow`; it's intentional —
# do NOT prune it as stray. Colour auto-disables when stdout isn't a terminal
# (piped/captured) or under NO_COLOR / TERM=dumb.

set -uo pipefail
cd "$(dirname "$0")" || exit 1

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || [ ! -t 1 ]; then
  C=''; G=''; Y=''; B=''; M=''; D=''; W=''; X=''
else
  C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'
  M=$'\e[35m'; D=$'\e[2m'; W=$'\e[1m'; X=$'\e[0m'
fi
line() { printf '%s\n' "$1"; }

ver()    { jq -r '.version // "?"' "plugins/$1/.claude-plugin/plugin.json" 2>/dev/null || printf '?'; }
pcolor() { case "$1" in
             task-queue) printf '%s' "$C" ;; tidy) printf '%s' "$G" ;;
             charter)    printf '%s' "$Y" ;; hud)  printf '%s' "$B" ;;
             *)          printf '%s' "$W" ;;
           esac; }

# One-line purpose from a script's header (line 2, the text after the em-dash).
purpose() {
  local p; p="$(sed -n '2p' "$1" 2>/dev/null | sed 's/^# *//')"
  case "$p" in *"— "*) p="${p#*— }" ;; esac
  [ "${#p}" -gt 56 ] && p="${p:0:55}…"
  printf '%s' "$p"
}

# "plugin|script-path" for every hook wired to event $1, across all plugins.
wired() {
  local hooks plug cmd path
  for hooks in plugins/*/hooks/hooks.json; do
    [ -f "$hooks" ] || continue
    plug="$(basename "$(dirname "$(dirname "$hooks")")")"
    while IFS= read -r cmd; do
      path="$(printf '%s' "$cmd" | grep -oE 'bin/[A-Za-z0-9_-]+\.sh' | head -1)"
      [ -n "$path" ] && printf '%s|plugins/%s/%s\n' "$plug" "$plug" "$path"
    done < <(jq -r --arg e "$1" '.hooks[$e][]?.hooks[]?.command // empty' "$hooks" 2>/dev/null)
  done | sort -u
}

# --- always-on -------------------------------------------------------------
S="$HOME/.claude/settings.json"
if [ -f "$S" ]; then
  mode="$(jq -r '.permissions.defaultMode // "default"' "$S" 2>/dev/null)"
  dn="$(jq -r '(.permissions.deny // []) | length' "$S" 2>/dev/null)"
  ak="$(jq -r '(.permissions.ask // []) | length' "$S" 2>/dev/null)"
  am="$(jq -r '.env.CLAUDE_TQ_AGENT_MODE // "off"' "$S" 2>/dev/null)"
  perm="defaultMode=$mode · deny($dn) · ask($ak) · agent-mode=$am"
else
  perm="auto mode + deny/ask (settings.json not found)"
fi
sl=''; for d in plugins/*/; do [ -f "${d}hooks/hooks.json" ] || sl="$(basename "$d")"; done
sha="$(git rev-parse --short HEAD 2>/dev/null || printf '?')"

line ""
line "  ${W}COMPANION WORKFLOW${X}  ${D}— live from the repo @ ${sha}${X}"
line "  ${D}────────────────────────────────────────────────────────────${X}"
line ""
line "  ${M}▐▌ ALWAYS-ON${X}  ${M}native permissions${X} ${D}${perm}${X}"
[ -n "$sl" ] && line "  ${D}             ${X}${B}statusLine →${X} ${B}${sl}${X} ${D}$(ver "$sl") · health ✓tests ⏸paused 🤖agent ctx%${X}"
line ""

# --- lifecycle (events in firing order; empty ones auto-omit) --------------
emit() {                                   # $1 symbol  $2 label  $3 event-key
  local rows plug path; rows="$(wired "$3")"; [ -n "$rows" ] || return 0
  line "  ${W}$1 $2${X}"
  while IFS='|' read -r plug path; do
    [ -n "$plug" ] || continue
    line "  ${D}┊${X}  $(pcolor "$plug")${plug}${X} ${D}$(ver "$plug")${X}  ${D}$(basename "$path") — $(purpose "$path")${X}"
  done <<< "$rows"
  line "  ${D}▼${X}"
}

emit "●" "SessionStart"     "SessionStart"
emit "◆" "UserPromptSubmit" "UserPromptSubmit"
steps="$(grep -oE '\([0-9]\) [A-Za-z]+' plugins/task-queue/bin/tq-capture.sh 2>/dev/null \
         | sed 's/.*) //' | awk '{a=a (NR>1?" → ":"") $0} END{print a}')"
[ -n "$steps" ] && { line "  ${C}┊   the loop:${X} ${steps}"; line "  ${D}▼${X}"; }
emit "⚙" "PreToolUse"       "PreToolUse"
emit "⚙" "PostToolUse"      "PostToolUse"
emit "✓" "Stop"             "Stop"
emit "✦" "Notification"     "Notification"

# --- on-demand (commands + control toggles, derived) -----------------------
cmds=''
for c in plugins/*/commands/*.md; do
  [ -f "$c" ] || continue
  cmds="$cmds /$(basename "$(dirname "$(dirname "$c")")"):$(basename "$c" .md)"
done
wiredset="$(for e in SessionStart UserPromptSubmit PreToolUse PostToolUse Stop Notification; do wired "$e"; done \
            | cut -d'|' -f2 | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done | sort -u)"
toggles=''
for f in plugins/*/bin/*.sh; do
  bn="$(basename "$f")"
  printf '%s\n' "$wiredset" | grep -qx "$bn" && continue
  sed -n '2p' "$f" 2>/dev/null | grep -qiE 'pause|resume|toggle' && toggles="$toggles ${bn%.sh}"
done
od="  ${W}on demand${X}${D}:${X}"
[ -n "$cmds" ]    && od="$od  ${Y}commands${X}${D}${cmds}${X}"
[ -n "$toggles" ] && od="$od   ${C}toggles${X}${D}${toggles}${X}"
line "$od"
line ""
line "  $(pcolor task-queue)■${X} task-queue ${D}orchestrate${X}   $(pcolor tidy)■${X} tidy ${D}change${X}   $(pcolor charter)■${X} charter ${D}know${X}   $(pcolor hud)■${X} hud ${D}show${X}"
line ""
