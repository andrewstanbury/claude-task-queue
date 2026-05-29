#!/usr/bin/env bash
# Observability log. Each hook fire appends a single jsonl line so users can
# tail / share the file when reporting issues. No-op when the state dir
# doesn't exist (hook may fire before install completed).
#
# Lives at ~/.claude/state/task-queue/<sha1-cwd>.log
#
# Each line:
#   { ts, event, latency_ms, ... event-specific fields ... }

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./queue.sh
. "$THIS_DIR/queue.sh"

tq_log_path() {
  printf '%s/%s.log' "$(tq_state_dir)" "$(tq_project_key "${1:-$PWD}")"
}

# Append one event. Args: event_name, extra_jq_filter_args (optional).
# Caller assembles the JSON via jq args. Best-effort: never fails the hook.
#
# Usage:
#   tq_log decompose --argjson length 152 --arg classification non-trivial --arg decision triaged
tq_log() {
  local event="${1:?event required}"
  shift
  local path
  path="$(tq_log_path)"
  mkdir -p "$(dirname "$path")" 2>/dev/null || return 0
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)"
  jq -cn \
    --arg ts "$ts" \
    --arg event "$event" \
    "$@" \
    '{ ts: $ts, event: $event } + ($ENV | with_entries(select(.key | startswith("TQ_LOG_"))) | with_entries(.key |= ltrimstr("TQ_LOG_") | .key |= ascii_downcase))' \
    2>/dev/null >> "$path" || true
}

# Time a command and write a log entry on completion. Stores latency in
# milliseconds. Captures the command's exit code in `exit`. Doesn't fail
# the caller on logging errors.
#
# Usage:
#   tq_log_timed decompose -- some_command arg arg
tq_log_timed() {
  local event="${1:?event required}"
  shift
  local sep="$1"
  shift
  [ "$sep" = "--" ] || { tq_log "$event" --arg error "bad invocation"; return 1; }

  local start_ns end_ns latency_ms rc
  start_ns="$(date +%s%N 2>/dev/null || printf 0)"
  "$@"
  rc=$?
  end_ns="$(date +%s%N 2>/dev/null || printf 0)"
  if [ "$start_ns" -gt 0 ] && [ "$end_ns" -gt 0 ]; then
    latency_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    latency_ms=0
  fi
  tq_log "$event" --argjson latency_ms "$latency_ms" --argjson exit "$rc"
  return "$rc"
}

# Read the last N events. Default 20.
tq_log_tail() {
  local n="${1:-20}"
  local path
  path="$(tq_log_path)"
  [ -f "$path" ] || return 0
  tail -n "$n" "$path"
}
