#!/usr/bin/env bash
# charter — support lib: know the project. It maintains the project's "Claude
# manual" and gates substantive work on documented quality attributes.
#
# Self-contained (install boundary — see AGENTS.md): it resolves the repo root
# itself rather than depending on another plugin. Read-only: it inspects the
# project, it never writes to it.

set -uo pipefail

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
# "missing". Accepts a dedicated file or a QA section in a manual doc. (ADRs are
# NOT counted here — they're *decisions*, a separate dimension; see
# charter_decisions_status.) Override the file via CLAUDE_CHARTER_QA_FILE.
charter_qa_status() {
  local root="$1" f
  [ -n "$root" ] || { printf 'missing'; return 0; }
  if [ -n "${CLAUDE_CHARTER_QA_FILE:-}" ] && [ -f "$root/$CLAUDE_CHARTER_QA_FILE" ]; then
    printf 'documented'; return 0
  fi
  for f in QUALITY.md docs/QUALITY.md QUALITY.adoc docs/quality-attributes.md; do
    [ -f "$root/$f" ] && { printf 'documented'; return 0; }
  done
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md README.md; do
    [ -f "$root/$f" ] && grep -qiE 'quality attribute|non-functional|\bnfrs?\b' "$root/$f" 2>/dev/null \
      && { printf 'documented'; return 0; }
  done
  printf 'missing'
}

# Does the project record its decisions (ADRs / DECISIONS.md)? Prints the
# relative path/dir if so, else nothing. Decisions are distinct from quality
# attributes: re-litigating or contradicting a past choice is an expensive
# AI-maintainer failure mode, so they get their own dimension. Override via
# CLAUDE_CHARTER_DECISIONS_FILE.
charter_decisions_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_CHARTER_DECISIONS_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_CHARTER_DECISIONS_FILE" ] && printf '%s' "$CLAUDE_CHARTER_DECISIONS_FILE"
    return 0
  fi
  for f in DECISIONS.md docs/DECISIONS.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
  local g rel
  for g in "$root"/docs/adr/*.md "$root"/docs/adrs/*.md "$root"/docs/decisions/*.md; do
    if [ -f "$g" ]; then
      rel="${g#"$root"/}"            # e.g. docs/adr/0001-foo.md
      printf '%s/' "${rel%/*}"       # → docs/adr/
      return 0
    fi
  done
}

charter_decisions_status() {
  [ -n "$(charter_decisions_path "${1:-}")" ] && printf 'present' || printf 'missing'
}

# Has the project baked the companion's standing policy into its own Claude
# manual (the "claude-companion" marker)? If so, charter drops its recurring
# "honor/consult" reminders (the manual is always loaded) and emits only the
# drift nudges for genuinely-missing docs. Shared token convention; self-contained.
charter_policy_documented() {
  local root="$1" f
  [ -n "$root" ] || return 1
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md; do
    [ -f "$root/$f" ] && grep -q 'claude-companion' "$root/$f" 2>/dev/null && return 0
  done
  return 1
}

# Recent non-merge commit subjects (default 5), newest first — the raw material
# for reconciling the roadmap against what actually landed. Empty outside a git
# repo. Used to make "reconcile the roadmap" concrete rather than abstract.
charter_recent_commits() {
  local root="$1" n="${2:-5}"
  [ -n "$root" ] || return 0
  # `|| true` so a repo with no commits (git log exits 128) never fails callers.
  git -C "$root" log --no-merges --format='%s' -n "$n" 2>/dev/null || true
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

# Does the project document its tech stack — languages, frameworks, key deps and
# versions? Distinct from the file-map (structure) and the QA gate (targets): the
# stack is the durable context that modernization/currency judgments lean on.
# Prints the relative path / matched doc, else nothing. Override via
# CLAUDE_CHARTER_STACK_FILE.
charter_stack_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
  if [ -n "${CLAUDE_CHARTER_STACK_FILE:-}" ]; then
    [ -f "$root/$CLAUDE_CHARTER_STACK_FILE" ] && printf '%s' "$CLAUDE_CHARTER_STACK_FILE"
    return 0
  fi
  for f in STACK.md docs/STACK.md docs/stack.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md README.md; do
    [ -f "$root/$f" ] && grep -qiE '^#+[[:space:]]*(tech[[:space:]-]*stack|stack)[[:space:]]*$' "$root/$f" 2>/dev/null \
      && { printf '%s' "$f"; return 0; }
  done
}

charter_stack_status() {
  [ -n "$(charter_stack_path "${1:-}")" ] && printf 'present' || printf 'missing'
}

# Is this a web project? Lets charter seed Lighthouse-aligned quality-attribute
# defaults (CWV, a11y, print CSS, progressive enhancement, components-by-default)
# so web best practices are designed-in, not audited after. Prints "web" or "no".
# CLAUDE_CHARTER_WEB=1|0 overrides; else infer from a web framework dep in
# package.json, an index.html, or a known web config file.
charter_is_web() {
  local root="$1" f
  case "${CLAUDE_CHARTER_WEB:-}" in
    1) printf 'web'; return 0 ;;
    0) printf 'no';  return 0 ;;
  esac
  [ -n "$root" ] || { printf 'no'; return 0; }
  [ -f "$root/index.html" ] && { printf 'web'; return 0; }
  for f in next.config.js next.config.mjs next.config.ts nuxt.config.js nuxt.config.ts \
           vite.config.js vite.config.ts astro.config.mjs svelte.config.js angular.json \
           gatsby-config.js remix.config.js; do
    [ -f "$root/$f" ] && { printf 'web'; return 0; }
  done
  if [ -f "$root/package.json" ]; then
    grep -qiE '"(react|react-dom|vue|svelte|preact|solid-js|astro|next|nuxt|gatsby|lit|vite|@angular/core|@remix-run/react)"[[:space:]]*:' \
      "$root/package.json" 2>/dev/null && { printf 'web'; return 0; }
  fi
  printf 'no'
}

# Conventions detection (charter_conventions / charter_conventions_status) lives
# in a sibling lib so this file stays focused and under the size guard; source it
# so every consumer of charter.sh gets it transitively (no bin sources it directly).
# shellcheck source=./conventions.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/conventions.sh"
