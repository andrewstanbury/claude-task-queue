#!/usr/bin/env bash
# task-queue — support lib: read the project's own committed docs.
#
# These helpers inspect the repo (read-only) for two Claude-facing files the
# resume bridge keys off: the standing-policy marker in the Claude manual, and
# the committed roadmap/backlog. Kept in their own unit so lib/tasks.sh stays
# focused on the native task store. Detection is duplicated from the charter
# plugin on purpose — the install boundary keeps each plugin self-contained
# (see AGENTS.md). Sourced by bin/tq-resume.sh.

set -uo pipefail

# Has this project baked the companion's standing policy into its own Claude
# manual? If CLAUDE.md/AGENTS.md carries the "claude-companion" marker, the
# always-loaded manual already states the policy, so the SessionStart hook can
# re-anchor in one line instead of re-injecting the full policy every session
# (bootstrap-once + drift-detect — stop being a per-session token tax).
tq_policy_documented() {
  local root="$1" f
  [ -n "$root" ] || return 1
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md; do
    [ -f "$root/$f" ] && grep -q 'claude-companion' "$root/$f" 2>/dev/null && return 0
  done
  return 1
}

# A repo's committed, Claude-facing backlog file (if any) — the cross-session,
# cross-engineer record of what's next. The resume bridge points the model at it
# so the live task list is hydrated from the shared backlog. Prints the relative
# path or nothing. Override via CLAUDE_TQ_ROADMAP_FILE.
tq_roadmap_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_TQ_ROADMAP_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_TQ_ROADMAP_FILE" ] && printf '%s' "$CLAUDE_TQ_ROADMAP_FILE"
    return 0
  fi
  for f in docs/ROADMAP.md ROADMAP.md docs/BACKLOG.md BACKLOG.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
}
