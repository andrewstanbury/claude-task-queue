#!/usr/bin/env bash
# hud — support lib: read-only accessors for the consolidated status line.
#
# Reads ONLY existing on-disk state the other plugins already maintain (never
# their CODE — install boundary) plus the stdin payload. No project scanning.
# Every accessor degrades to empty/0 when its source is absent (e.g. a plugin
# isn't installed), so the matching status-line slot simply collapses.

set -uo pipefail

# Default paths mirror where the sibling plugins write; overridable for tests.
hud_pause_dir()  { printf '%s' "${CLAUDE_HUD_PAUSE_DIR:-$HOME/.claude/state/task-queue/paused}"; }
hud_agent_dir()  { printf '%s' "${CLAUDE_HUD_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}"; }
hud_verify_dir() { printf '%s' "${CLAUDE_HUD_VERIFY_DIR:-$HOME/.claude/state/tidy/verify}"; }
hud_tasks_dir()  { printf '%s' "${CLAUDE_HUD_TASKS_DIR:-${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}}"; }
hud_coupling_dir() { printf '%s' "${CLAUDE_HUD_COUPLING_DIR:-$HOME/.claude/state/tidy/coupling-hud}"; }

# Coupling-density trend direction for this repo — "up" when tidy's last verify saw
# import density climbing past the threshold, else "steady"/"" (empty when never
# computed / too-small repo). A cheap read of the cached marker tidy-verify writes;
# hud never computes density itself (too heavy for a per-render status line).
hud_coupling() {
  local root="$1" f
  [ -n "$root" ] || return 0
  f="$(hud_coupling_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$f" ] && cat "$f" 2>/dev/null
}

# Count of OPEN QUESTIONS the user still owes an answer on this session — native
# tasks whose subject starts with "❓", pending/in_progress, deduped by subject.
# Read-only mirror of task-queue's tq_open_questions (install boundary forbids
# sharing the lib; drift-guard.bats keeps the two in agreement). Prints a number.
hud_open_questions() {
  local sid="$1" tdir f c
  [ -n "$sid" ] || { printf '0'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  [ -d "$tdir" ] || { printf '0'; return 0; }
  c="$(for f in "$tdir"/*.json; do
        [ -f "$f" ] || continue
        jq -r 'select((.status=="pending" or .status=="in_progress")
                      and ((.subject // "") | startswith("❓"))) | (.subject // "")' "$f" 2>/dev/null
      done | awk 'NF && !seen[$0]++' | grep -c .)"
  printf '%s' "${c:-0}"
}

# Is the review loop paused for this repo? prints 1 / 0.
hud_paused() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_pause_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# Is task-queue agent-mode ON for this repo? prints 1 / 0. (Same per-repo flag
# scheme as pause; read-only mirror across the install boundary.)
hud_agent() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_agent_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# The verification floor's last outcome for this session: "pass" | "fail" |
# "timeout" | "" (never run / unknown). Read-only mirror of the marker
# tidy-verify.sh writes — the single highest-value signal for a non-technical
# owner ("are the tests passing?").
hud_verify() {
  local sid="$1" f
  [ -n "$sid" ] || return 0
  f="$(hud_verify_dir)/result-$(printf '%s' "$sid" | sed 's:/:-:g')"
  [ -f "$f" ] && { cat "$f" 2>/dev/null || true; }
}

# How many uncommitted files in the working tree (porcelain count), or "" outside
# a git repo. The branch slot already shells to git, so this is cheap context for
# "you have unsaved work" while vibe-coding.
hud_dirty() {
  local cwd="$1" n
  git -C "$cwd" rev-parse >/dev/null 2>&1 || return 0
  n="$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c .)"
  [ "$n" -gt 0 ] && printf '%s' "$n"
}

# Current git branch for a dir (short SHA when detached), or empty.
hud_branch() {
  local cwd="$1" b
  b="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$b" = "HEAD" ] && b="@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"
  printf '%s' "$b"
}
