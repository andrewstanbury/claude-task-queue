#!/usr/bin/env bash
# flow.sh — render the companion-plugins workflow as a CLI flow diagram.
#
# The ONE sanctioned human-facing artifact in this otherwise artifact-free repo
# (owner-requested, 2026-06-16): an at-a-glance map of where each feature fires in
# the Claude Code lifecycle. Run it with `./flow.sh` or `make flow`. Keep it in
# sync if the lifecycle changes; it is intentional — do NOT prune it as stray.
#
# Colour is auto-disabled when stdout isn't a terminal (piped/captured) or under
# NO_COLOR / TERM=dumb, so it stays readable everywhere.

set -euo pipefail

if [ -n "${NO_COLOR:-}" ] || [ "${TERM:-}" = "dumb" ] || [ ! -t 1 ]; then
  C=''; G=''; Y=''; B=''; M=''; D=''; W=''; X=''
else
  C=$'\e[36m'; G=$'\e[32m'; Y=$'\e[33m'; B=$'\e[34m'; M=$'\e[35m'
  D=$'\e[2m'; W=$'\e[1m'; X=$'\e[0m'
fi
p() { printf '%b\n' "$1"; }

p ""
p "  ${W}COMPANION WORKFLOW${X}  ${D}— where each feature fires in the lifecycle${X}"
p "  ${D}────────────────────────────────────────────────────────────${X}"
p ""
p "  ${M}▐▌ ALWAYS-ON${X}  ${M}native permissions${X} ${D}(auto · deny rm-rf · ask force-push)${X}"
p "  ${D}             ${X}${B}hud statusLine${X} ${D}●health ✓tests ⏸paused 🤖agent ctx%${X}"
p ""
p "  ${G}●${X} ${W}SessionStart${X} ${D}· once ·${X}"
p "  ${D}┊${X}   ${Y}charter${X}     gate work on docs · decisions anchor · owner loop"
p "  ${D}┊${X}   ${G}tidy${X}        clean-as-you-go standard"
p "  ${D}┊${X}   ${C}task-queue${X}  queue policy · ${W}${C}resume bridge${X} · hydrate backlog"
p "  ${D}▼${X}"
p "  ${C}◆${X} ${W}you type a prompt${X}  ${D}→ UserPromptSubmit →${X} ${C}tq-capture${X}"
p "  ${D}┊${X}"
p "  ${D}┊  trivial or paused → runs straight in auto (silent)${X}"
p "  ${D}▼${X}  ${D}substantive (multi-step / consequential)${X}"
p "  ${C}┏━ INTERPRET → PRESENT → APPROVE${X} ${D}· the review loop ·${X}"
p "  ${C}┃${X}  1 ${W}interpret${X}  one-line read of what you want"
p "  ${C}┃${X}  2 ${W}decompose${X}  tasks in dep order, smallest blast first"
p "  ${C}┃${X}  3 ${W}judge${X}      parallel-vs-inline ${D}·${X} candid ${M}SKIP${X} recs"
p "  ${C}┃${X}  4 ${W}present${X}    brief inline ${D}(small)${X} ${D}·${X} AskUserQuestion ${D}(large)${X}"
p "  ${C}┃${X}  5 ${W}approve${X}    TaskCreate ${W}only what you ok${X} → run"
p "  ${C}┗━${X}"
p "  ${D}▼${X}"
p "  ${W}⚙ Claude works the queue${X} ${D}· native task list ·${X}"
p "  ${D}┊${X}"
p "  ${D}┊${X} ${D}on each edit →${X} ${G}tidy-touch${X}  ${D}format · lint · blast-radius · size${X}"
p "  ${D}┊${X} ${D}             ${X} ${D}(0 model tokens unless it has something to say)${X}"
p "  ${D}┊${X} ${D}on finish    →${X} ${G}tidy-verify${X}  ${W}tests: block until green${X}"
p "  ${D}┊${X} ${D}             ${X} ${D}+ debt/prune nudge — throttled, after a clean verify${X}"
p "  ${D}▼${X}"
p "  ${G}✓${X} ${W}done${X}  ${D}→${X} ${B}hud${X} ${D}flips to${X} ${G}✓ tests${X}"
p ""
p "  ${D}on demand:${X}  ${Y}/charter:align${X} ${D}vs decisions${X}   ${C}tq-pause${X} ${D}mute loop${X}   ${C}tq-agent${X} ${D}fan-out (opt-in)${X}"
p ""
p "  ${C}■${X} task-queue ${D}orchestrate${X}   ${G}■${X} tidy ${D}change${X}   ${Y}■${X} charter ${D}know${X}   ${B}■${X} hud ${D}show${X}"
p ""
