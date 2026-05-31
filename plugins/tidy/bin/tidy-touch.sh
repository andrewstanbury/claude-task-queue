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
if [ -z "$file" ]; then
  # A payload arrived but had no tool_input.file_path — the shape we read may
  # have changed. Note it (drift canary), then stay silent.
  tidy_log drift "PostToolUse payload had no tool_input.file_path"
  exit 0
fi
[ -f "$file" ] || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"

# The size-vs-complexity check is language-agnostic — it runs for any text file,
# independent of the language dispatch below, so size is flagged automatically on
# every edit (no manual trigger).
size="$(tidy_size_nudge "$file" "$sid" 2>/dev/null || true)"

# Currency/modernization: surface the nearest manifest's pinned versions once per
# session so the model can judge what's deprecated/behind latest. Stack-level, so
# deduped per manifest per session (not per edit).
currency="$(tidy_currency_nudge "$file" "$sid" 2>/dev/null || true)"

lang="$(tidy_lang_for_file "$file")"
result=""
tdd=""
case "$lang" in
  go)
    result="$(tidy_handle_go "$file" 2>/dev/null || true)"   # format + lint findings
    tdd="$(tidy_tdd_nudge "$file" "$sid" 2>/dev/null || true)"
    ;;
  web)
    result="$(tidy_handle_web "$file" 2>/dev/null || true)"  # eslint/stylelint findings
    ;;
esac
[ -n "$result" ] || [ -n "$tdd" ] || [ -n "$size" ] || [ -n "$currency" ] || exit 0   # nothing to say

changed=""
lint=""
if [ -n "$result" ]; then
  changed="${result%%$'\t'*}"
  lint="${result#*$'\t'}"
  [ "$lint" = "$result" ] && lint=""           # no tab → no lint section
fi

ctx="[tidy] ${file}:"
[ "$changed" = "1" ] && ctx="$ctx"$'\n'"• auto-formatted — re-read before further edits (line content may have shifted)."
[ -n "$lint" ] && ctx="$ctx"$'\n'"• linter findings to fix in this file (leave unrelated pre-existing issues alone):"$'\n'"$lint"
[ -n "$tdd" ] && ctx="$ctx"$'\n'"• $tdd"
[ -n "$size" ] && ctx="$ctx"$'\n'"• $size"
[ -n "$currency" ] && ctx="$ctx"$'\n'"• $currency"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
