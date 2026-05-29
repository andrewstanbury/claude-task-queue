#!/usr/bin/env bash
# Single-line status reader for the project's queue. Written for consumption
# by claude-statusbar's status.sh and by terminal prompts. Always exits 0;
# empty output when there is no queue.
#
# Output examples:
#   ▶ 4/11 · auto · 5: Wire engine (M, ~4k tok)
#   ⏸ 4/11 · paused · 5: Wire engine
#   ▶ 0/3 · next 1: Audit repo (S)
#   (empty if the queue is empty / not initialized)

set -euo pipefail

# Resolve symlinks so a PATH-installed entrypoint (e.g. ~/.local/bin/tq-status)
# finds its libs in the real plugin dir. Portable plain-readlink loop (no
# GNU-only `readlink -f`), so it works on macOS/BSD too.
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
# shellcheck source=../lib/queue.sh
. "$PLUGIN_DIR/lib/queue.sh"

path="$(tq_queue_path)"
[ -f "$path" ] || exit 0
[ -s "$path" ] || exit 0

counts="$(tq_counts)"
glyph="▶"
mode=""
if tq_is_paused; then
  glyph="⏸"
  mode="paused"
elif tq_is_autopilot; then
  mode="auto"
fi

# Prefer the in-progress task; fall back to the next pending one.
current_json="$(tq_in_progress | head -n1 || true)"
[ -z "$current_json" ] && current_json="$(tq_next 2>/dev/null || true)"

label=""
if [ -n "$current_json" ]; then
  id="$(printf '%s' "$current_json" | jq -r '.id')"
  subj="$(printf '%s' "$current_json" | jq -r '.subject')"
  est="$(printf '%s' "$current_json" | jq -r '.est')"
  tok="$(printf '%s' "$current_json" | jq -r '.tokenEst')"
  if [ "${tok:-0}" -gt 0 ]; then
    label="${id}: ${subj} (${est}, ~${tok} tok)"
  else
    label="${id}: ${subj} (${est})"
  fi
fi

# Compose: glyph counts [· mode] [· label]
out="${glyph} ${counts}"
[ -n "$mode" ] && out+=" · ${mode}"
[ -n "$label" ] && out+=" · ${label}"
printf '%s\n' "$out"
