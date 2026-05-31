#!/usr/bin/env bash
# charter — support lib: know the project. It maintains the project's "Claude
# manual" and gates substantive work on documented quality attributes.
#
# Self-contained (install boundary — see AGENTS.md): it resolves the repo root
# itself rather than depending on another plugin. Read-only: it inspects the
# project, it never writes to it.

set -uo pipefail

charter_log_dir()  { printf '%s' "${CLAUDE_CHARTER_LOG_DIR:-$HOME/.claude/state/charter}"; }
charter_log_file() { printf '%s/activity.log' "$(charter_log_dir)"; }

# Best-effort log line; never fails the hook. CLAUDE_CHARTER_LOG_DISABLED=1 mutes.
charter_log() {
  [ -n "${CLAUDE_CHARTER_LOG_DISABLED:-}" ] && return 0
  local event="$1" detail="${2:-}" ts dir
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '?')"
  dir="$(charter_log_dir)"
  { mkdir -p "$dir" 2>/dev/null && printf '%s\t%s\t%s\n' "$ts" "$event" "$detail" >> "$(charter_log_file)"; } 2>/dev/null || true
  return 0
}

# cwd -> repo root: git toplevel, else walk for .git, else the cwd itself.
charter_root_for_cwd() {
  local cwd="$1" top dir
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$top" ] && { printf '%s' "$top"; return 0; }
  dir="$cwd"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/.git" ] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  printf '%s' "$cwd"
}

# Does the project document its quality attributes? Prints "documented" or
# "missing". Accepts a dedicated file, ADRs, or a QA section in a manual doc.
# Override the accepted file via CLAUDE_CHARTER_QA_FILE (path relative to root).
charter_qa_status() {
  local root="$1" f
  [ -n "$root" ] || { printf 'missing'; return 0; }
  if [ -n "${CLAUDE_CHARTER_QA_FILE:-}" ] && [ -f "$root/$CLAUDE_CHARTER_QA_FILE" ]; then
    printf 'documented'; return 0
  fi
  for f in QUALITY.md docs/QUALITY.md QUALITY.adoc docs/quality-attributes.md; do
    [ -f "$root/$f" ] && { printf 'documented'; return 0; }
  done
  for f in "$root"/docs/adr/*.md "$root"/docs/adrs/*.md; do
    [ -f "$f" ] && { printf 'documented'; return 0; }
  done
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md README.md; do
    [ -f "$root/$f" ] && grep -qiE 'quality attribute|non-functional|\bnfrs?\b' "$root/$f" 2>/dev/null \
      && { printf 'documented'; return 0; }
  done
  printf 'missing'
}
