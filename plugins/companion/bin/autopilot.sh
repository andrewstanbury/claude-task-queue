#!/usr/bin/env bash
# Toggle per-repo autopilot. ON = run autonomous, keep draining the queue, park decisions as
# ❓/⏳; OFF = normal review loop. The flag PERSISTS (survives a restart/crash), and is
# ENFORCED: the Stop hook auto-continues the queue while it's on, and the ask-guard blocks
# AskUserQuestion. Run via /companion:autopilot or directly. Best-effort.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

cmd="${1:-status}"
root="$(companion_root "$PWD")"
flag="$(companion_autopilot_flag "$root")"
case "$cmd" in
  on)  mkdir -p "$(dirname "$flag")" 2>/dev/null && : > "$flag" \
       && echo "✈️  autopilot ON for $root — I'll keep draining the queue and PARK decisions (❓) / owner-actions (⏳) until you turn it off." ;;
  off) companion_autopilot_clear "$root"; echo "autopilot OFF for $root — normal review loop resumes; review any parked ❓ items." ;;
  status) companion_autopilot_on "$root" && echo on || echo off ;;
  ship) sub="${2:-status}"; sflag="$(companion_ship_flag "$root")"
    case "$sub" in
      on)  mkdir -p "$(dirname "$sflag")" 2>/dev/null && : > "$sflag" \
           && echo "📦 ship-mode ON for $root — while autopilot is on I'll auto-commit completed work to an autopilot/* branch (never main, never a push), for you to review + /companion:ship-it on return." ;;
      off) rm -f "$sflag" 2>/dev/null; echo "ship-mode OFF for $root — autopilot won't auto-commit." ;;
      status) companion_ship_on "$root" && echo on || echo off ;;
      *) echo "usage: autopilot ship on|off|status" >&2; exit 1 ;;
    esac ;;
  *) echo "usage: autopilot on|off|status | ship on|off|status" >&2; exit 1 ;;
esac
