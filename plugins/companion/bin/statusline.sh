#!/usr/bin/env bash
# statusline — a minimal read-only status line: the companion's one glance surface.
# Shows: 🛡 secret gate on (🛡✗ if disabled) · model · ⇡ input ⇣ output tokens · 📋 open
# tasks · project · branch (+ *N changes). No hooks, no writes, no model cost — it only
# reads the JSON Claude Code pipes on stdin plus the companion's own task store and git.
# Wire it in settings.json: { "statusLine": { "type": "command", "command": "bash <THIS>" } }
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

# 📋 open (pending/in_progress) tasks in this session's companion store.
NTASK=0
store="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}/$SID"
if [ -n "${SID:-}" ] && [ -d "$store" ]; then
  files=("$store"/*.json)
  [ -e "${files[0]}" ] && NTASK="$(jq -rs '[.[]|select(.status=="pending" or .status=="in_progress")]|length' "${files[@]}" 2>/dev/null || printf 0)"
fi

# 🛡 secret gate (the one enforced guarantee) — green shield on, red ✗ when disabled.
if [ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ]; then SHIELD="$R$B🛡✗$X"; else SHIELD="$G$B🛡$X"; fi

# git: branch + dirty count in one read.
BRANCH=""; DIRTY=0
while IFS= read -r l; do case "$l" in '# branch.head '*) BRANCH="${l#\# branch.head }";; '#'*) :;; ?*) DIRTY=$((DIRTY+1));; esac
done < <(git -C "$CWD" status --porcelain=v2 --branch 2>/dev/null)
PROJ="$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null)"; PROJ="${PROJ##*/}"; [ -n "$PROJ" ] || PROJ="${CWD##*/}"

# ✈️ autopilot when it's armed for this repo (an attention state).
AP=""; companion_autopilot_on "$(companion_root "$CWD")" && AP=" ${Y}✈️${X}"

# assemble: 🛡 [✈️] · model · ⇡in ⇣out · 📋N · project · ⎇branch *changes
out="$SHIELD$AP ${C}$MODEL$X"
[ "${ITOK:-0}" -gt 0 ] 2>/dev/null && out="$out ${D}⇡$(hum "$ITOK") ⇣$(hum "$OTOK")$X"
out="$out ${C}${B}📋 $NTASK$X"
[ -n "$PROJ" ] && out="$out $PROJ"
[ -n "$BRANCH" ] && { out="$out ${C}${B}⎇ $BRANCH$X"; [ "$DIRTY" -gt 0 ] && out="$out ${Y}${B}*$DIRTY$X"; }
printf '%s\n' "$out"
