#!/usr/bin/env bash
# PostToolUse(Edit|Write) hook — tidy the file that was just edited.
#
# Detects the edited file's language, auto-applies behavior-preserving
# formatting, and surfaces linter findings for the model to address before it
# moves on. Scoped to the single touched file; silent for unsupported types or
# when the tools aren't installed. Must NEVER break the edit, so everything is
# best-effort and it always exits 0.

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
# shellcheck source=../lib/tidy.sh
. "$PLUGIN_DIR/lib/tidy.sh"

# PostToolUse hands us { tool_name, tool_input: { file_path, ... }, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
[ -n "$file" ] && [ -f "$file" ] || exit 0

lang="$(tidy_lang_for_file "$file")"
[ -n "$lang" ] || exit 0                       # unsupported type → silent

case "$lang" in
  go) result="$(tidy_handle_go "$file" 2>/dev/null || true)" ;;
  *)  result="" ;;
esac
[ -n "$result" ] || exit 0                     # nothing changed, nothing flagged

changed="${result%%$'\t'*}"
lint="${result#*$'\t'}"
[ "$lint" = "$result" ] && lint=""             # no tab → no lint section

ctx="[tidy] ${file}"
[ "$changed" = "1" ] && ctx="$ctx was auto-formatted — re-read it before further edits (formatting may have shifted line content)."
if [ -n "$lint" ]; then
  ctx="$ctx"$'\n'"Linter findings to address in this file before moving on:"$'\n'"$lint"
fi

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
