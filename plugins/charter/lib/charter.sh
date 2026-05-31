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

# The project's committed, Claude-facing backlog: a roadmap/backlog file that
# travels with the repo so work can be picked up, resumed, and coordinated
# across engineers on separate machines (git history = the cross-dev audit
# trail). Prints the relative path if one exists, else nothing. Override the
# accepted path via CLAUDE_CHARTER_ROADMAP_FILE (relative to root).
charter_roadmap_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_CHARTER_ROADMAP_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_CHARTER_ROADMAP_FILE" ] && printf '%s' "$CLAUDE_CHARTER_ROADMAP_FILE"
    return 0
  fi
  for f in docs/ROADMAP.md ROADMAP.md docs/BACKLOG.md BACKLOG.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
}

# "present" if a roadmap/backlog file exists, else "missing".
charter_roadmap_status() {
  [ -n "$(charter_roadmap_path "${1:-}")" ] && printf 'present' || printf 'missing'
}

# The project map — a compact, committed, Claude-facing `file → responsibility`
# index (plus key entry points) so a session orients from the map instead of
# re-scanning the tree (the biggest token lever for an AI maintainer: a map
# grows sublinearly, the tree doesn't). Recognises common existing conventions
# (ARCHITECTURE.md) so we don't nag a project that already keeps one. Prints the
# relative path if found, else nothing. Override via CLAUDE_CHARTER_MAP_FILE.
charter_map_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_CHARTER_MAP_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_CHARTER_MAP_FILE" ] && printf '%s' "$CLAUDE_CHARTER_MAP_FILE"
    return 0
  fi
  for f in docs/MAP.md MAP.md docs/ARCHITECTURE.md ARCHITECTURE.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
}

# "present" if a project map exists, else "missing".
charter_map_status() {
  [ -n "$(charter_map_path "${1:-}")" ] && printf 'present' || printf 'missing'
}
