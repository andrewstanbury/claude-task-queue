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
# shellcheck source=../lib/blast.sh
. "$PLUGIN_DIR/lib/blast.sh"
# shellcheck source=../lib/lint.sh
. "$PLUGIN_DIR/lib/lint.sh"
# shellcheck source=../lib/coverage.sh
. "$PLUGIN_DIR/lib/coverage.sh"

# PostToolUse hands us { tool_name, tool_input: { file_path, ... }, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
[ -n "$input" ] || exit 0
file="$(printf '%s' "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null || true)"
if [ -z "$file" ]; then
  # A payload arrived but had no tool_input.file_path — the shape we read may
  # have changed; stay silent.
  exit 0
fi
[ -f "$file" ] || exit 0
sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"

# The size-vs-complexity check is language-agnostic — it runs for any text file,
# independent of the language dispatch below, so size is flagged automatically on
# every edit (no manual trigger).
size="$(tidy_size_nudge "$file" "$sid" 2>/dev/null || true)"

# Coverage ratchet: if a touched source file has no test, ask to characterize it
# before changing — so an under-tested project accrues a spec on the worked
# surface. Language-agnostic (gated inside); deduped per file per session.
cov="$(tidy_coverage_nudge "$file" "$sid" 2>/dev/null || true)"

lang="$(tidy_lang_for_file "$file")"
result=""
case "$lang" in
  go)
    result="$(tidy_handle_go "$file" 2>/dev/null || true)"   # format + lint findings
    ;;
  web)
    result="$(tidy_handle_web "$file" 2>/dev/null || true)"  # eslint/stylelint findings
    ;;
  python)
    result="$(tidy_handle_python "$file" 2>/dev/null || true)"  # ruff findings
    ;;
  shell)
    result="$(tidy_handle_shell "$file" 2>/dev/null || true)"   # findings via shellcheck
    ;;
  gdscript)
    result="$(tidy_handle_gdscript "$file" 2>/dev/null || true)"  # gdformat + gdlint findings
    ;;
esac

# Extract the format-changed flag + lint findings from the handler result.
changed=""
lint=""
if [ -n "$result" ]; then
  changed="${result%%$'\t'*}"
  lint="${result#*$'\t'}"
  [ "$lint" = "$result" ] && lint=""           # no tab → no lint section
fi

# Dedup identical lint findings per file per session: re-surface ONLY when the
# finding set changes (a new issue appeared, or some were fixed). Without this the
# same "leave these pre-existing issues alone" block re-injects on every edit of a
# file carrying legacy/unfixed lint — pure repeat tokens. Content-keyed, so a
# genuinely new finding still surfaces; the mark is cleared when findings go away,
# so a later reintroduction re-surfaces.
if [ -n "$sid" ]; then
  lmark="$(tidy_log_dir)/nudged/lint-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  if [ -z "$lint" ]; then
    rm -f "$lmark" 2>/dev/null || true
  else
    lhash="$(printf '%s' "$lint" | cksum | tr -d ' ')"
    if [ "$(cat "$lmark" 2>/dev/null || true)" = "$lhash" ]; then
      lint=""                                    # unchanged since last surfaced → quiet
    else
      { mkdir -p "$(dirname "$lmark")" 2>/dev/null && printf '%s' "$lhash" > "$lmark"; } 2>/dev/null || true
    fi
  fi
fi

# Blast-radius: only for recognized source files (avoids noise on docs/config).
blast=""
[ -n "$lang" ] && blast="$(tidy_blast_radius "$file" "$sid" 2>/dev/null || true)"

# Nothing to say → silent (re-checked AFTER the lint dedup may have cleared it).
[ "$changed" = "1" ] || [ -n "$lint" ] || [ -n "$cov" ] || [ -n "$size" ] || [ -n "$blast" ] || exit 0

ctx="[tidy] ${file}:"
[ "$changed" = "1" ] && ctx="$ctx"$'\n'"• auto-formatted — re-read before further edits (line content may have shifted)."
[ -n "$lint" ] && ctx="$ctx"$'\n'"• linter findings to fix in this file (leave unrelated pre-existing issues alone):"$'\n'"$lint"
# Blast radius is the first-class signal — surface it high (right after findings),
# with the coverage ratchet next (characterize the surface a change can reach).
[ -n "$blast" ] && ctx="$ctx"$'\n'"• $blast"
[ -n "$cov" ] && ctx="$ctx"$'\n'"• $cov"
[ -n "$size" ] && ctx="$ctx"$'\n'"• $size"

jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}'
