#!/usr/bin/env bash
# tq-status — on-demand readout of task-queue's per-repo CONTROL plane.
#
# Backs the bare `/tq` menu. Reports the mode switches (solo/checkpoint/agent) and a
# repo-wide count of still-open work — deliberately NOT a re-listing of the native
# task list (Claude Code renders that itself; duplicating it is the anti-pattern hud
# already avoids). This answers "what modes am I in, and how much is still open
# here", which nothing else shows in one place.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"
# shellcheck source=../lib/checkpoint.sh
. "$PLUGIN_DIR/lib/checkpoint.sh"

root="$(tq_root_for_cwd "$PWD")"

# ---- mode states ------------------------------------------------------------
# solo = the merged autonomous mode (was away + pause): run without the owner, skip
# the approval checkpoint, PARK anything needing them.
if tq_is_away "$root"; then
  since="$(tq_away_since "$root")"; now="$(date +%s 2>/dev/null || echo 0)"
  if [ "$since" -gt 0 ] && [ "$now" -gt 0 ]; then solo="ON (~$(( (now - since) / 3600 ))h)"; else solo="ON"; fi
else
  solo="off"
fi

if tq_ckpt_enabled "$root"; then
  if tq_ckpt_exists "$root"; then ckpt="ARMED (snapshot ready — restore: $(tq_ckpt_restore_cmd))"; else ckpt="ARMED (no snapshot yet)"; fi
else
  ckpt="off"
fi

if tq_is_agent_mode "$root"; then agent="ON (parallel subagents)"; else agent="off"; fi

# ---- repo-wide open work (count only; not a re-listing) ----------------------
open=0; qsubs=""
tdir="$(tq_tasks_dir)"
if [ -d "$tdir" ]; then
  for sdir in "$tdir"/*/; do
    [ -d "$sdir" ] || continue
    [ "$(tq_session_root "$(basename "$sdir")" 2>/dev/null || true)" = "$root" ] || continue
    for f in "$sdir"*.json; do
      [ -f "$f" ] || continue
      line="$(jq -r 'select(.status=="pending" or .status=="in_progress") | (.subject // "")' "$f" 2>/dev/null || true)"
      [ -n "$line" ] || continue
      open=$((open + 1))
      case "$line" in '❓'*) qsubs="$qsubs$line"$'\n' ;; esac
    done
  done
fi
q="$(printf '%s' "$qsubs" | awk 'NF && !seen[$0]++' | grep -c . || true)"

# ---- render -----------------------------------------------------------------
printf 'task-queue · %s\n\n' "$root"
printf 'modes\n'
printf '  solo          %s\n' "$solo"
printf '  checkpoint    %s\n' "$ckpt"
printf '  agent-mode    %s\n\n' "$agent"
printf 'open work in this repo\n'
printf '  %s task(s) still open across sessions · %s ❓ awaiting you\n\n' "$open" "$q"
printf 'change it: /tq solo · checkpoint · agent (on|off) · /tq undo · bare /tq = this menu\n'
