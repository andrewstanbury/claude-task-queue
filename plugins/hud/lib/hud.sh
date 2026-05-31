#!/usr/bin/env bash
# hud — support lib: read-only accessors for the consolidated status line.
#
# Reads ONLY existing on-disk state the other plugins already maintain (never
# their CODE — install boundary) plus the stdin payload. No project scanning.
# Every accessor degrades to empty/0 when its source is absent (e.g. a plugin
# isn't installed), so the matching status-line slot simply collapses.

set -uo pipefail

# Default paths mirror where the sibling plugins write; overridable for tests.
hud_tasks_dir() { printf '%s' "${CLAUDE_HUD_TASKS_DIR:-$HOME/.claude/tasks}"; }
hud_pause_dir() { printf '%s' "${CLAUDE_HUD_PAUSE_DIR:-$HOME/.claude/state/task-queue/paused}"; }
hud_tidy_log()  { printf '%s' "${CLAUDE_HUD_TIDY_LOG:-$HOME/.claude/state/tidy/activity.log}"; }

# Open (pending/in_progress) task count + the in-progress subject, for a session.
# Prints "count<TAB>subject".
hud_tasks() {
  local sid="$1" dir f n=0 doing="" st
  dir="$(hud_tasks_dir)/$sid"
  { [ -n "$sid" ] && [ -d "$dir" ]; } || { printf '0\t'; return 0; }
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    st="$(jq -r '.status // ""' "$f" 2>/dev/null || true)"
    case "$st" in pending|in_progress) n=$((n + 1)) ;; esac
    if [ "$st" = "in_progress" ] && [ -z "$doing" ]; then
      doing="$(jq -r '.subject // ""' "$f" 2>/dev/null || true)"
    fi
  done
  printf '%s\t%s' "$n" "$doing"
}

# Is auto-advance paused for this repo? prints 1 / 0.
hud_paused() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_pause_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# Are the project's quality attributes documented? prints 1 / 0. (Read-only
# mirror of charter's check — we can't source charter across the install boundary.)
hud_qa() {
  local root="$1" f
  [ -n "$root" ] || { printf '0'; return 0; }
  for f in QUALITY.md docs/QUALITY.md docs/quality-attributes.md; do
    [ -f "$root/$f" ] && { printf '1'; return 0; }
  done
  for f in "$root"/docs/adr/*.md; do [ -f "$f" ] && { printf '1'; return 0; }; done
  for f in CLAUDE.md AGENTS.md README.md; do
    [ -f "$root/$f" ] && grep -qiE 'quality attribute|non-functional|\bnfrs?\b' "$root/$f" 2>/dev/null \
      && { printf '1'; return 0; }
  done
  printf '0'
}

# Last tidy action from tidy's activity log: a touched filename, else the event
# tag, else empty.
hud_last_tidy() {
  local logf last det; logf="$(hud_tidy_log)"
  [ -f "$logf" ] || return 0
  last="$(tail -n 1 "$logf" 2>/dev/null || true)"
  [ -n "$last" ] || return 0
  det="$(printf '%s' "$last" | cut -f3)"
  if printf '%s' "$det" | grep -q 'file='; then
    printf '%s' "$det" | sed -E 's/.*file=([^ ]*).*/\1/; s#.*/##'
  else
    printf '%s' "$last" | cut -f2
  fi
}

# Current git branch for a dir (short SHA when detached), or empty.
hud_branch() {
  local cwd="$1" b
  b="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$b" = "HEAD" ] && b="@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"
  printf '%s' "$b"
}

# 1234 -> 1.2k, 1200000 -> 1.2M.
hud_fmt_k() {
  awk -v n="$1" 'BEGIN {
    if      (n >= 1000000) printf "%.1fM", n/1000000
    else if (n >= 1000)    printf "%.1fk", n/1000
    else                   printf "%d", n
  }'
}
