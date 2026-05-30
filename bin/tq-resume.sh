#!/usr/bin/env bash
# SessionStart hook — the "resume bridge".
#
# Claude Code's native task list is per-session working memory: a fresh session
# starts empty and can't see tasks an earlier session left unfinished. This hook
# reads the native task store, finds OPEN tasks from prior sessions rooted at the
# SAME repo, and hands them to the model as SessionStart context so it can
# re-adopt the relevant ones into its native list (via TaskCreate).
#
# It only reads files the model already wrote — no parallel store, no second
# source of truth. It spends tokens only on a short resume note, and nothing at
# all when there is no carried-over open work (it prints nothing and exits 0).
#
# Wire it up in ~/.claude/settings.json:
#   "hooks": { "SessionStart": [ { "hooks": [
#     { "type": "command", "command": ".../bin/tq-resume.sh" } ] } ] }

set -euo pipefail

# Resolve symlinks so a relocated/PATH-installed entrypoint still finds lib/.
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

# SessionStart hands us JSON on stdin: { session_id, cwd, source, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"

sid=""
cwd=""
if [ -n "$input" ]; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

root="$(tq_root_for_cwd "$cwd")"
ctx="$(tq_resume_context "$root" "$sid" 2>/dev/null || true)"
[ -n "$ctx" ] || exit 0

# Emit as SessionStart additionalContext (Claude Code adds it to the model's
# context for this session).
jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
