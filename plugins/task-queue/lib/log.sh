#!/usr/bin/env bash
# task-queue — observability helpers (best-effort logging + log pruning).
#
# Split out of lib/tasks.sh to keep that file focused (and under the size guard).
# tasks.sh sources this, so every consumer that sources tasks.sh gets tq_log /
# tq_prune_log transitively — no bin needs to source it directly.

set -uo pipefail

# The activity log lives at a FIXED home (independent of the hook-only
# CLAUDE_TQ_STATE_DIR=CLAUDE_PLUGIN_DATA override) so that tq-doctor, run by
# hand with no plugin env, reads exactly the file the hooks write.
tq_log_dir()  { printf '%s' "${CLAUDE_TQ_LOG_DIR:-$HOME/.claude/state/task-queue}"; }
tq_log_file() { printf '%s/activity.log' "$(tq_log_dir)"; }

# Append one best-effort diagnostic line: "<iso-ts>\t<event>\t<sid8>\t<detail>".
# Logging must never break a hook, so every failure is swallowed. Disabled
# entirely with CLAUDE_TQ_LOG_DISABLED=1.
#   $1 event   short tag (session-start | advance | …)
#   $2 detail  free text (optional)
#   $3 sid     session id (optional; truncated to 8 chars)
tq_log() {
  [ -n "${CLAUDE_TQ_LOG_DISABLED:-}" ] && return 0
  local event="$1" detail="${2:-}" sid="${3:-}" ts dir
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '?')"
  dir="$(tq_log_dir)"
  {
    mkdir -p "$dir" 2>/dev/null \
      && printf '%s\t%s\t%s\t%s\n' "$ts" "$event" "${sid:0:8}" "$detail" >> "$(tq_log_file)"
  } 2>/dev/null || true
  return 0
}

# Best-effort: keep the append-only log bounded so it never becomes cruft. Trims
# to the last 1000 lines once it passes 2000. Never fails the caller.
tq_prune_log() {
  local log; log="$(tq_log_file)"
  [ -f "$log" ] || return 0
  if [ "$(wc -l < "$log" 2>/dev/null || printf 0)" -gt 2000 ]; then
    { tail -n 1000 "$log" > "$log.tmp" 2>/dev/null && mv "$log.tmp" "$log"; } 2>/dev/null || true
  fi
  return 0
}
