#!/usr/bin/env bash
# PreToolUse hook entry point. Decide whether the tool call about to run
# should:
#   - silently pass (low-risk reads, allowlisted bash)
#   - inject a soft nudge (writes when paused / not in autopilot)
#   - block hard (destructive/irreversible — always, regardless of autopilot)
#
# "Destructive" is the line where autopilot must always pause. Mirrors the
# rules in ~/.claude/CLAUDE.md (deletes, force-push, dropping tables, etc.).
#
# Output uses Claude Code's PreToolUse decision contract:
#   { decision: "allow" | "block", reason: "..." }
# A missing decision (or empty stdout) = default allow.

set -euo pipefail

[ "${CLAUDE_TQ_PRETOOL_DISABLED:-0}" = "1" ] && exit 0

THIS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/queue.sh
. "$PLUGIN_DIR/lib/queue.sh"
# shellcheck source=../lib/log.sh
. "$PLUGIN_DIR/lib/log.sh"

payload="$(cat)"
tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // empty')"
tool_input="$(printf '%s' "$payload" | jq -c '.tool_input // {}')"

# No tool name → nothing to gate.
[ -z "$tool_name" ] && exit 0

# --- Classify the call -------------------------------------------------------

low_risk=0
write_op=0
destructive=0
reason=""

case "$tool_name" in
  Read|TaskList|TaskGet|TaskCreate|TaskUpdate)
    low_risk=1
    ;;
  Edit|Write|NotebookEdit)
    write_op=1
    ;;
  Bash)
    cmd="$(printf '%s' "$tool_input" | jq -r '.command // empty')"
    lower="$(printf '%s' "$cmd" | tr '[:upper:]' '[:lower:]')"

    # Destructive matchers — irreversible state changes. Anchored at clause
    # boundaries (start-of-string, or after &&/;/|) so substrings inside
    # quoted args don't trigger false positives. The v0.1.0 release shipped
    # an unanchored pattern that flagged "gh release create" inside a
    # `gh pr create --body "..."` invocation (the destructive verb was in
    # the PR body, not the executed command). See v0.1.1 release notes.
    destructive_prefix='(^|[[:space:]]*[&;|]+[[:space:]]*)'
    destructive_verbs='(rm -rf|git push --force|git push -f|git reset --hard|git checkout --|drop table|drop database|truncate table|kill -9|shutdown|eas update|eas submit|gh pr merge|gh release create|npm publish|aws s3 rm[^|;]*--recursive)'
    if printf '%s' "$lower" | grep -qE "${destructive_prefix}${destructive_verbs}"; then
      destructive=1
      reason="destructive operation detected — autopilot must pause and confirm explicitly. Pattern matched in: $cmd"
    # Low-risk read-only shell.
    elif printf '%s' "$cmd" | grep -qE '^[[:space:]]*(ls|cat|head|tail|wc|grep|find|git status|git log|git diff|git branch|git remote|pwd|which|whoami|date|env|jq|tq|tq-status|node --version|npm --version)\b'; then
      low_risk=1
    else
      write_op=1
    fi
    ;;
  *)
    # Unknown / MCP tools — let them through. The plugin doesn't gate
    # network calls today; that's v0.4 (autosnapshot lane).
    exit 0
    ;;
esac

# --- Apply policy ------------------------------------------------------------

# Destructive: always block. Autopilot does NOT override this.
if [ "$destructive" -eq 1 ]; then
  tq_log pretool --arg tool "$tool_name" --arg decision "block-destructive" --arg reason "$reason"
  jq -nc --arg r "$reason" '{
    decision: "block",
    reason: $r
  }'
  exit 0
fi

# Low-risk: silent pass (the "fewer interruptions" vibe goal).
if [ "$low_risk" -eq 1 ]; then
  tq_log pretool --arg tool "$tool_name" --arg decision "allow-low-risk"
  exit 0
fi

# Write op: if paused, block; if autopilot, allow; else nudge via stderr.
if [ "$write_op" -eq 1 ]; then
  if tq_is_paused; then
    tq_log pretool --arg tool "$tool_name" --arg decision "block-paused"
    jq -nc '{
      decision: "block",
      reason: "claude-task-queue is paused for this project. Run `tq resume` (or `tq autopilot`) before continuing writes."
    }'
    exit 0
  fi
  tq_log pretool --arg tool "$tool_name" --arg decision "allow-write"
  exit 0
fi

tq_log pretool --arg tool "$tool_name" --arg decision "allow-default"
exit 0
