#!/usr/bin/env bash
# SessionStart hook — gate substantive work on documented quality attributes.
#
# If the project hasn't documented its quality attributes (perf, security, a11y,
# reliability, maintainability…), nudge the model to capture them FIRST — so
# changes can honor them. If they're documented, a brief honor-reminder on a
# fresh context, silent thereafter. Source-aware + read-only (never writes the
# project). The "gate" is a strong nudge, not a hard block (hooks can't block).

set -euo pipefail

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

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; src=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"
root="$(charter_root_for_cwd "$cwd")"
status="$(charter_qa_status "$root" 2>/dev/null || printf 'missing')"

case "$src" in compact|resume) lean=1 ;; *) lean=0 ;; esac

if [ "$status" = "missing" ]; then
  if [ "$lean" -eq 1 ]; then
    ctx="[charter] (reminder) document this project's quality attributes (perf, security, a11y, reliability, maintainability) before substantive changes."
  else
    ctx="[charter] This project has no documented quality attributes. Before substantive changes, capture them — performance, security, accessibility, reliability, maintainability targets — in QUALITY.md (or a \"Quality Attributes\" section of CLAUDE.md). Changes should then honor them."
  fi
  charter_log "session-start" "qa=missing src=${src:-?}"
else
  # Documented: a brief honor-reminder on a fresh context; silent on compact/resume
  # (the model already oriented, and can read the doc directly).
  [ "$lean" -eq 1 ] && exit 0
  ctx="[charter] This project documents its quality attributes — honor them when changing code, and surface the relevant one when you touch related areas."
  charter_log "session-start" "qa=documented src=${src:-?}"
fi

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
