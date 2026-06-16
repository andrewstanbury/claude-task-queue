#!/usr/bin/env bash
# shellcheck disable=SC2016  # backticks in printf formats are literal Markdown, not command substitution
# flow.sh — generate FLOW.md, a human-reviewable snapshot of the workflow,
# DERIVED LIVE from the repo so it can't drift: the lifecycle wiring from each
# plugin's hooks.json, one-line purposes from each script's header, the review-
# loop steps from tq-capture's own instruction, versions from plugin.json, and
# the live permission/agent-mode state from settings.json.
#
# Run it to (re)generate the file: `./flow.sh` or `make flow`. There is no cron
# and nothing automatic — refresh it by hand whenever you want a current view.
#
# FLOW.md is the ONE sanctioned human-facing artifact in this otherwise
# artifact-free repo (owner-requested) — it is intentional; do NOT prune it.
# Output path defaults to FLOW.md; pass an alternate as $1.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
OUT="${1:-FLOW.md}"

EVENTS=(SessionStart UserPromptSubmit PreToolUse PostToolUse Stop Notification SubagentStop)
declare -A SYM=([SessionStart]="●" [UserPromptSubmit]="◆" [PreToolUse]="⛬"
                [PostToolUse]="⚙" [Stop]="✓" [Notification]="✦" [SubagentStop]="⤺")

ver() { jq -r '.version // "?"' "plugins/$1/.claude-plugin/plugin.json" 2>/dev/null || printf '?'; }

# One-line purpose from a script's header (line 2, text after the em-dash).
purpose() {
  local p; p="$(sed -n '2p' "$1" 2>/dev/null | sed 's/^# *//; s/|/\//g')"
  case "$p" in *"— "*) p="${p#*— }" ;; esac
  [ "${#p}" -gt 66 ] && p="${p:0:65}…"
  printf '%s' "$p"
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

# " · "-joined script basenames (no .sh) wired to event $1.
names() {
  wired "$1" | cut -d'|' -f2 | while IFS= read -r p; do [ -n "$p" ] && basename "$p" .sh; done \
    | awk '{a=a (NR>1?" · ":"") $0} END{print a}'
}

# --- live state ------------------------------------------------------------
S="$HOME/.claude/settings.json"
if [ -f "$S" ]; then
  perm="defaultMode=$(jq -r '.permissions.defaultMode // "default"' "$S" 2>/dev/null)"
  perm="$perm · deny($(jq -r '(.permissions.deny//[])|length' "$S" 2>/dev/null))"
  perm="$perm · ask($(jq -r '(.permissions.ask//[])|length' "$S" 2>/dev/null))"
  perm="$perm · agent-mode=$(jq -r '.env.CLAUDE_TQ_AGENT_MODE // "off"' "$S" 2>/dev/null)"
else
  perm="auto mode + deny/ask (settings.json not found)"
fi
sl=''; for d in plugins/*/; do [ -f "${d}hooks/hooks.json" ] || sl="$(basename "$d")"; done
sha="$(git rev-parse --short HEAD 2>/dev/null || printf 'unknown')"
steps="$(grep -oE '\([0-9]\) [A-Za-z]+' plugins/task-queue/bin/tq-capture.sh 2>/dev/null \
         | sed 's/.*) //' | awk '{a=a (NR>1?" → ":"") $0} END{print a}')"
ss="$(names SessionStart)"; up="$(names UserPromptSubmit)"
pt="$(names PostToolUse)";  st="$(names Stop)"

# --- generate FLOW.md ------------------------------------------------------
{
  printf '# Companion workflow — current state\n\n'
  printf '_Derived from the repo @ `%s` by `./flow.sh`. Manual refresh: `./flow.sh` (or `make flow`). No cron — pull, not push._\n\n' "$sha"
  printf '**Always-on** — native permissions `%s`' "$perm"
  [ -n "$sl" ] && printf ' · statusLine → `%s` %s' "$sl" "$(ver "$sl")"
  printf '\n\n## The flow\n\n```text\n'
  [ -n "$ss" ]    && printf '  ● SessionStart      → %s\n' "$ss"
  [ -n "$up" ]    && printf '  ◆ UserPromptSubmit  → %s\n' "$up"
  [ -n "$steps" ] && printf '      loop: %s\n' "$steps"
  printf '  ⚙ work the queue      (native task list)\n'
  [ -n "$pt" ]    && printf '  ├ each edit  →        %s\n' "$pt"
  [ -n "$st" ]    && printf '  └ on finish  →        %s   (tests block-until-green + throttled prune)\n' "$st"
  printf '```\n\n## What fires when\n\n'
  for e in "${EVENTS[@]}"; do
    rows="$(wired "$e")"; [ -n "$rows" ] || continue
    printf '### %s %s\n\n| plugin | script | what it does |\n|---|---|---|\n' "${SYM[$e]:-•}" "$e"
    while IFS='|' read -r plug path; do
      [ -n "$plug" ] || continue
      printf '| `%s` %s | `%s` | %s |\n' "$plug" "$(ver "$plug")" "$(basename "$path")" "$(purpose "$path")"
    done <<< "$rows"
    [ "$e" = "UserPromptSubmit" ] && [ -n "$steps" ] && printf '\n**The review loop:** %s\n' "$steps"
    printf '\n'
  done
  cmds=''
  for c in plugins/*/commands/*.md; do
    [ -f "$c" ] || continue
    nm="/$(basename "$(dirname "$(dirname "$c")")"):$(basename "$c" .md)"
    cmds="${cmds:+$cmds, }\`$nm\`"
  done
  wiredset="$(for e in "${EVENTS[@]}"; do wired "$e"; done | cut -d'|' -f2 \
              | while IFS= read -r p; do [ -n "$p" ] && basename "$p"; done | sort -u)"
  togs=''
  for f in plugins/*/bin/*.sh; do
    bn="$(basename "$f")"
    printf '%s\n' "$wiredset" | grep -qx "$bn" && continue
    sed -n '2p' "$f" 2>/dev/null | grep -qiE 'pause|resume|toggle' && togs="${togs:+$togs, }\`${bn%.sh}\`"
  done
  printf '## On demand\n\n'
  [ -n "$cmds" ] && printf '%s\n' "- **commands** — $cmds"
  [ -n "$togs" ] && printf '%s\n' "- **toggles** — $togs"
  printf '\n---\n'
  printf '_`task-queue` %s · `tidy` %s · `charter` %s · `hud` %s_\n' \
    "$(ver task-queue)" "$(ver tidy)" "$(ver charter)" "$(ver hud)"
} > "$OUT"

printf 'wrote %s (@ %s) — refresh anytime with ./flow.sh\n' "$OUT" "$sha"
