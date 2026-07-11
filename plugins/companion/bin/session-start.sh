#!/usr/bin/env bash
# SessionStart — the two things a document can't do itself:
#   1. Put STEERING.md (the working agreement) in context once per session, so it governs
#      the whole session.
#   2. Re-surface THIS repo's still-open tasks from an earlier session — a new session's
#      queue starts empty, so this is the cross-session resume bridge.
# The companion owns its task store (it does NOT use Claude Code's native tasks); each session
# dir is stamped with its repo root (`.root` by tq), so scoping needs no native transcript.
# Read-only, best-effort: any failure degrades to "inject nothing", never breaks startup.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
STEERING="$PLUGIN_DIR/STEERING.md"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
store="${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}"

carry=""
if [ -d "$store" ]; then
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    [ "$(cat "$d.root" 2>/dev/null || true)" = "$root" ] || continue   # scope to this repo
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
