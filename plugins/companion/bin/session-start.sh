#!/usr/bin/env bash
# SessionStart — the two things a document can't do itself:
#   1. Put STEERING.md (the working agreement) in context once per session, so it governs
#      the whole session (cached; not re-injected per prompt).
#   2. Re-surface THIS repo's still-open tasks from an earlier session — the native task
#      list starts empty each session, so this is the cross-session resume bridge.
# Read-only, best-effort: any failure degrades to "inject nothing", never breaks startup.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
STEERING="$PLUGIN_DIR/STEERING.md"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"

store="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/tasks}"
projects="${CLAUDE_COMPANION_PROJECTS_DIR:-$HOME/.claude/projects}"

# session id -> repo root, via the session transcript's recorded cwd. Only tasks whose
# session maps to THIS root are surfaced (no cross-project bleed).
session_root() {
  local sid="$1" f c
  for f in "$projects"/*/"$sid.jsonl"; do
    [ -f "$f" ] || continue
    c="$(head -n 40 "$f" 2>/dev/null | jq -r 'select(.cwd!=null)|.cwd' 2>/dev/null | head -n1 || true)"
    [ -n "$c" ] && { git -C "$c" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$c"; return 0; }
  done
  return 1
}

carry=""
if [ -d "$store" ]; then
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    sid="$(basename "$d")"
    [ "$(session_root "$sid" 2>/dev/null || true)" = "$root" ] || continue   # scope to this repo
    for f in "$d"*.json; do
      [ -f "$f" ] || continue
      line="$(jq -r 'select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "")' "$f" 2>/dev/null || true)"
      [ -n "$line" ] && carry="$carry$line"$'\n'
    done
  done
fi

msg="Read the working agreement below — it governs how you queue, decide, and keep this repo clean for the whole session."$'\n\n'
[ -f "$STEERING" ] && msg="$msg$(cat "$STEERING")"
[ -n "$carry" ] && msg="$msg"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
