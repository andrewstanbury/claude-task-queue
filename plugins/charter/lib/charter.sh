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

# Outcome memory — "scar tissue": files this project has REPEATEDLY had to FIX,
# derived from git history. NOT raw churn (active development looks identical); the
# rework RATIO — fix/revert commits over total commits touching a file — is what
# flags a debt magnet. Prints "<fixes>\t<changes>\t<path>" per flagged file, most-
# reworked first; empty when there's no rework signal or no git history. Bounded to
# the last 300 commits; read-only. Word-boundaried keywords so "prefix" ≠ "fix".
# Only files that STILL EXIST are reported — a scar on a deleted file isn't actionable.
charter_hotspots() {
  local root="$1" max="${2:-5}"
  [ -d "$root" ] || return 0
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  git -C "$root" log -n 300 --no-merges --pretty=format:':C:%s' --name-only 2>/dev/null \
    | awk '
        /^:C:/ { rw = (tolower($0) ~ /(^|[^a-z])(fix|bugfix|hotfix|bug|revert|undo|rollback|regression|rework)([^a-z]|$)/) ? 1 : 0; next }
        NF     { c[$0]++; if (rw) r[$0]++ }
        END    { for (f in r) if (r[f] >= 2 && r[f] / c[f] >= 0.34) printf "%d\t%d\t%s\n", r[f], c[f], f }
      ' 2>/dev/null \
    | sort -rn -k1,1 \
    | while IFS=$'\t' read -r rf cf pf; do [ -f "$root/$pf" ] && printf '%s\t%s\t%s\n' "$rf" "$cf" "$pf"; done \
    | head -n "$max"
}

# Does the project document its quality attributes? Prints "documented" or
# "missing". Accepts a dedicated file or a QA section in a manual doc. (ADRs are
# NOT counted here — they're *decisions*, a separate dimension; see
# charter_decisions_status.)
charter_qa_status() {
  local root="$1" f
  [ -n "$root" ] || { printf 'missing'; return 0; }
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
# AI-maintainer failure mode, so they get their own dimension.
charter_decisions_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
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
# trail). Prints the relative path if one exists, else nothing.
charter_roadmap_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
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
# relative path if found, else nothing.
charter_map_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
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
# Prints the relative path / matched doc, else nothing.
charter_stack_path() {
  local root="$1" f
  [ -n "$root" ] || return 0
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

# Is this a React Native project? RN is NOT web — no DOM, so web-only gates like
# Lighthouse/CWV and DOM a11y don't apply — even if its scaffolding happens to leave
# an HTML shell around, so charter_is_web excludes it before structural detection.
# Detect it via a strong native signal: a Metro bundler config, a react-native/expo
# dep, or an Expo app manifest. Returns 0 yes / 1 no. (Reused by the conventions
# detector, which is why the native-signal names live here, not in charter_is_web.)
charter_is_react_native() {
  local root="$1"
  [ -n "$root" ] || return 1
  { [ -f "$root/metro.config.js" ] || [ -f "$root/metro.config.ts" ]; } && return 0
  if [ -f "$root/package.json" ]; then
    grep -qiE '"(react-native|expo)"[[:space:]]*:' "$root/package.json" 2>/dev/null && return 0
  fi
  [ -f "$root/app.json" ] && grep -q '"expo"' "$root/app.json" 2>/dev/null && return 0
  return 1
}

# Is this a web project? Lets charter seed Lighthouse-aligned quality-attribute
# defaults (CWV, a11y, print CSS, progressive enhancement, components-by-default)
# so web best practices are designed-in, not audited after. Prints "web" or "no".
# CLAUDE_CHARTER_WEB=1|0 overrides. Detection is purely STRUCTURAL (invariant: no
# framework/language allowlist) — a web app is one that ships a browser entry point:
# a committed HTML page at the root or a conventional web root, or a web app
# manifest. React Native is excluded first (native, no DOM). Honest limitation: a
# meta-framework that GENERATES its HTML at build time (nothing committed) won't
# match — accepted, since this only gates a minor web-QA nudge and the invariant
# forbids enumerating those frameworks by name (use CLAUDE_CHARTER_WEB=1 to force it).
charter_is_web() {
  local root="$1" f
  case "${CLAUDE_CHARTER_WEB:-}" in
    1) printf 'web'; return 0 ;;
    0) printf 'no';  return 0 ;;
  esac
  [ -n "$root" ] || { printf 'no'; return 0; }
  charter_is_react_native "$root" && { printf 'no'; return 0; }
  # A committed HTML entry point at the root or a conventional web root.
  for f in index.html public/index.html src/index.html app/index.html static/index.html; do
    [ -f "$root/$f" ] && { printf 'web'; return 0; }
  done
  # A web app manifest — .webmanifest is web by definition; a bare manifest.json
  # counts only with a web-app-manifest shape (display mode or start_url), since
  # unrelated tools also write manifest.json.
  for f in manifest.webmanifest public/manifest.webmanifest src/manifest.webmanifest \
           static/manifest.webmanifest; do
    [ -f "$root/$f" ] && { printf 'web'; return 0; }
  done
  for f in manifest.json public/manifest.json src/manifest.json static/manifest.json; do
    [ -f "$root/$f" ] && grep -qE '"(display|start_url)"[[:space:]]*:' "$root/$f" 2>/dev/null \
      && { printf 'web'; return 0; }
  done
  printf 'no'
}

# Conventions detection (charter_conventions / charter_conventions_status) and the
# alignment-floor helpers (charter_log_dir / charter_tree_hash /
# charter_decisions_excerpt / charter_change_touches_decisions) live in sibling
# libs so this file stays focused and under the size guard; source them so every
# consumer of charter.sh gets them transitively (no bin sources them directly).
# shellcheck source=./conventions.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/conventions.sh"
# shellcheck source=./align.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/align.sh"
