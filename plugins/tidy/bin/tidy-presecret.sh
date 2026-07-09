#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) hook — block a hardcoded secret BEFORE it lands.
#
# Scans the content the tool is about to write for credential-shaped literals and,
# on a confirmed hit, blocks the write (stderr reason + exit 2, Claude Code's block
# convention) so the secret never reaches disk. Everything else passes through
# untouched. This is the ONE deliberate exception to tidy's "never block the edit"
# posture: a leaked key is irreversible, and the match is prefix-anchored to keep
# false-positive blocks near-zero. Disable with CLAUDE_TIDY_SECSCAN=0.
#
# Best-effort like every hook: any error, missing field, or disable -> exit 0
# (allow). It must NEVER block except on a confirmed secret.

set -uo pipefail

[ "${CLAUDE_TIDY_SECSCAN:-1}" = "0" ] && exit 0

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
# shellcheck source=../lib/secscan.sh
. "$PLUGIN_DIR/lib/secscan.sh" || exit 0

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0

file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty' 2>/dev/null || true)"
# Don't scan files where secret-shaped strings are legitimate (docs, fixtures).
[ -n "$file" ] && tidy_secscan_excluded "$file" && exit 0

# The content about to be written, across the tool shapes:
#   Write -> .content ; Edit -> .new_string ; MultiEdit -> .edits[].new_string ;
#   NotebookEdit -> .new_source (also .cell_source / .source across variants).
content="$(printf '%s' "$input" | jq -r '
  [ .tool_input.content, .tool_input.new_string, (.tool_input.edits[]?.new_string),
    .tool_input.new_source, .tool_input.cell_source, .tool_input.source ]
  | map(select(. != null)) | join("\n") // empty' 2>/dev/null || true)"
[ -n "$content" ] || exit 0

reason="$(tidy_secscan_text "$content" "$file" 2>/dev/null || true)"
[ -n "$reason" ] || exit 0

printf 'BLOCKED by tidy secret-scan: %s. Do not commit credentials — use an environment variable or a secret manager and reference it at runtime. If this is a placeholder/test value, rename it so it is not credential-shaped, or set CLAUDE_TIDY_SECSCAN=0 for this session.\n' "$reason" >&2
exit 2
