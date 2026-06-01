#!/usr/bin/env bash
# PreToolUse(Bash|Edit|Write) hook — SURFACE consequential/irreversible actions.
#
# The owner is non-technical and can't review code, so a consequential or hard-to-
# undo action (a paid dependency, a destructive filesystem/history command, a
# database drop, a data migration) should be confirmed with them in plain language
# first. This hook detects a SMALL set of such patterns and emits a plain-language
# reminder — it NEVER blocks the action (no permissionDecision; always exit 0). It
# is the active arm of the consent principle (the standing posture lives in
# charter's brief). Silent unless a pattern matches, so it costs nothing per call.
#
# NOT the heavyweight "destructive-action gate" the project decided against — that
# was a hard block a plugin couldn't own reliably. This only surfaces; the model
# (and the owner) decide. See docs/ROADMAP.md "Decided against".

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
# shellcheck source=../lib/charter.sh
. "$PLUGIN_DIR/lib/charter.sh"

[ -n "${CLAUDE_CHARTER_CONSENT_DISABLED:-}" ] && exit 0

# PreToolUse hands us { tool_name, tool_input: { command | file_path, ... }, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"

reason=""
if [ -n "$cmd" ]; then
  if printf '%s' "$cmd" | grep -Eiq '(^|[^[:alnum:]])(yarn[[:space:]]+add|pnpm[[:space:]]+add|bun[[:space:]]+add|cargo[[:space:]]+add|bundle[[:space:]]+add|gem[[:space:]]+install|go[[:space:]]+get|(npm|pnpm)[[:space:]]+(install|i|add)[[:space:]]+[a-z@.]|pip3?[[:space:]]+install[[:space:]]+[a-z])'; then
    reason="adds a dependency (cost / lock-in / supply-chain reach)"
  elif printf '%s' "$cmd" | grep -Eiq '(^|[^[:alnum:]])(rm[[:space:]]+-[a-zA-Z]*[rf]|git[[:space:]]+reset[[:space:]]+--hard|git[[:space:]]+clean[[:space:]]+-[a-z]*f|git[[:space:]]+push[[:space:]].*(--force|-f([[:space:]]|$)))'; then
    reason="a destructive or irreversible filesystem/history change"
  elif printf '%s' "$cmd" | grep -Eiq '(drop[[:space:]]+(table|database|schema)|truncate[[:space:]]|delete[[:space:]]+from)'; then
    reason="a destructive database operation (possible data loss)"
  elif printf '%s' "$cmd" | grep -Eiq '(^|[^[:alnum:]])(migrate|db:migrate|prisma[[:space:]]+migrate|alembic[[:space:]]+(upgrade|downgrade)|knex[[:space:]]+migrate)'; then
    reason="runs a data migration (may be hard to reverse on real data)"
  fi
elif [ -n "$file" ]; then
  case "$file" in
    *migration*|*migrations/*|*schema.prisma|*db/schema.rb)
      reason="edits a schema/migration (can be irreversible for existing data)" ;;
  esac
fi

[ -n "$reason" ] || exit 0   # nothing consequential detected → silent, zero cost

charter_log "consent" "surfaced: $reason (tool=$tool)" 2>/dev/null || true

ctx="⚠️ [charter] This looks consequential and hard to undo — $reason. The owner is non-technical and can't review it, so confirm with them in plain language before proceeding (the line is reversibility + cost + data-safety). This is a reminder, not a block."

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", additionalContext: $c}}'
