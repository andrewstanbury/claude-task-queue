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

# A repo's committed decisions/ADR record (DECISIONS.md or docs/adr|adrs|decisions/),
# if any — the recorded choices that newly-captured work must not silently
# contradict. Lets the capture nudge weigh work against the project's direction
# at capture time (the alignment anchor, mirroring charter). Self-contained
# detection (duplicated from charter on purpose — the install boundary keeps each
# plugin standalone; see AGENTS.md). Prints a relative path/dir or nothing.
# Override via CLAUDE_TQ_DECISIONS_FILE.
tq_decisions_path() {
  local root="$1" f g rel
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_TQ_DECISIONS_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_TQ_DECISIONS_FILE" ] && printf '%s' "$CLAUDE_TQ_DECISIONS_FILE"
    return 0
  fi
  for f in DECISIONS.md docs/DECISIONS.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
  for g in "$root"/docs/adr/*.md "$root"/docs/adrs/*.md "$root"/docs/decisions/*.md; do
    if [ -f "$g" ]; then
      rel="${g#"$root"/}"            # e.g. docs/adr/0001-foo.md
      printf '%s/' "${rel%/*}"       # → docs/adr/
      return 0
    fi
  done
}
