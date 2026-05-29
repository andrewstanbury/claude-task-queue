#!/usr/bin/env bash
# Durable, project-scoped task queue. One jsonl file per project keyed by
# sha1(cwd). Append-only writes for new tasks; status changes rewrite the file
# (small N — well under 100 tasks per project — so the rewrite cost is fine).
#
# Each line is a single task object:
#   { id, subject, status, est, tokenEst, blockedBy, attachedRules,
#     createdAt, updatedAt, recommendedParallel }
#
# Status values: pending | in_progress | completed | cancelled

set -euo pipefail

# Resolve where queue files live. Tests can redirect via CLAUDE_TQ_STATE_DIR.
tq_state_dir() {
  printf '%s' "${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"
}

# Project key — sha1 of the absolute cwd so two checkouts of the same repo at
# different paths get separate queues. Truncate to 12 chars for filename
# readability; collisions across a single user's projects are vanishingly
# unlikely at that length.
tq_project_key() {
  local cwd="${1:-$PWD}"
  printf '%s' "$cwd" | sha1sum | cut -c1-12
}

tq_queue_path() {
  printf '%s/%s.jsonl' "$(tq_state_dir)" "$(tq_project_key "${1:-$PWD}")"
}

tq_pause_path() {
  printf '%s/%s.pause' "$(tq_state_dir)" "$(tq_project_key "${1:-$PWD}")"
}

tq_autopilot_path() {
  printf '%s/%s.autopilot' "$(tq_state_dir)" "$(tq_project_key "${1:-$PWD}")"
}

tq_ensure_state() {
  mkdir -p "$(tq_state_dir)"
  local path
  path="$(tq_queue_path "${1:-$PWD}")"
  [ -f "$path" ] || : > "$path"
}

# Next free integer id. Linear scan, fine for queues under ~1k lines.
tq_next_id() {
  local path
  path="$(tq_queue_path "${1:-$PWD}")"
  [ -s "$path" ] || { printf '1'; return; }
  local max
  max="$(jq -rs 'map(.id | tonumber) | max' "$path" 2>/dev/null || printf 0)"
  printf '%s' "$((max + 1))"
}

# Append a new task. Required: subject. Optional: est, tokenEst, blockedBy
# (comma-separated ids), attachedRules (comma-separated), recommendedParallel.
tq_append() {
  local subject="${1:?subject required}"
  local est="${2:-M}"
  local token_est="${3:-0}"
  local blocked_by="${4:-}"
  local attached="${5:-}"
  local parallel="${6:-false}"

  tq_ensure_state
  local id ts path
  id="$(tq_next_id)"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  path="$(tq_queue_path)"

  jq -cn \
    --arg id "$id" \
    --arg subject "$subject" \
    --arg est "$est" \
    --argjson tokenEst "$token_est" \
    --arg blockedBy "$blocked_by" \
    --arg attached "$attached" \
    --arg parallel "$parallel" \
    --arg ts "$ts" \
    '{
      id: $id,
      subject: $subject,
      status: "pending",
      est: $est,
      tokenEst: $tokenEst,
      blockedBy: ($blockedBy | split(",") | map(select(length > 0))),
      attachedRules: ($attached | split(",") | map(select(length > 0))),
      recommendedParallel: ($parallel == "true"),
      createdAt: $ts,
      updatedAt: $ts
    }' >> "$path"
  printf '%s\n' "$id"
}

tq_list() {
  local path
  path="$(tq_queue_path "${1:-$PWD}")"
  [ -f "$path" ] || return 0
  cat "$path"
}

tq_get() {
  local id="${1:?id required}"
  local path
  path="$(tq_queue_path)"
  [ -f "$path" ] || return 1
  jq -c --arg id "$id" 'select(.id == $id)' "$path"
}

tq_update_status() {
  local id="${1:?id required}"
  local status="${2:?status required}"
  local path tmp ts
  path="$(tq_queue_path)"
  [ -f "$path" ] || return 1
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  tmp="$(mktemp)"
  jq -c --arg id "$id" --arg status "$status" --arg ts "$ts" \
    'if .id == $id then .status = $status | .updatedAt = $ts else . end' \
    "$path" > "$tmp"
  mv "$tmp" "$path"
}

tq_cancel() {
  tq_update_status "$1" cancelled
}

tq_clear() {
  local path
  path="$(tq_queue_path)"
  rm -f "$path" "$(tq_pause_path)" "$(tq_autopilot_path)"
}

# Pending tasks whose blockedBy list contains only completed/cancelled ids
# (or is empty). Used by tq next / status to pick what's actionable.
tq_next() {
  local path
  path="$(tq_queue_path)"
  [ -f "$path" ] || return 0
  jq -sc '
    . as $all
    | ($all | map(select(.status == "completed" or .status == "cancelled") | .id)) as $done
    | $all
    | map(select(.status == "pending"))
    | map(select((.blockedBy // []) - $done | length == 0))
    | first // empty
  ' "$path"
}

tq_in_progress() {
  local path
  path="$(tq_queue_path)"
  [ -f "$path" ] || return 0
  jq -c 'select(.status == "in_progress")' "$path"
}

# Format a single task object (passed as $1) into a compact one-line label that
# carries the metadata Haiku already attached — so the injected reminder
# actually delivers it to the assistant instead of discarding it:
#   "5: Wire engine (M)"                              (no metadata)
#   "4: Add auth (M) [blocked-by: 3] [rules: OWASP]"  (blockers + rules)
#   "5: Wire engine (M) [parallel-ok]"                (recommendedParallel)
# Empty / null input → empty output (so callers can guard on a blank result).
tq_fmt_task_line() {
  local json="${1:-}"
  [ -z "$json" ] && return 0
  printf '%s' "$json" | jq -r '
    if . == null then "" else
      (.id) + ": " + (.subject) + " (" + (.est // "M") + ")"
      + (if ((.blockedBy // [])    | length) > 0 then " [blocked-by: " + ((.blockedBy)    | join(",")) + "]" else "" end)
      + (if ((.attachedRules // []) | length) > 0 then " [rules: "      + ((.attachedRules) | join(",")) + "]" else "" end)
      + (if (.recommendedParallel // false)        then " [parallel-ok]" else "" end)
    end'
}

tq_counts() {
  local path
  path="$(tq_queue_path)"
  [ -f "$path" ] || { printf '0/0'; return; }
  jq -rs '
    {
      done: map(select(.status == "completed")) | length,
      total: length
    }
    | "\(.done)/\(.total)"
  ' "$path"
}

tq_is_paused() {
  [ -f "$(tq_pause_path)" ]
}

tq_is_autopilot() {
  [ -f "$(tq_autopilot_path)" ]
}
