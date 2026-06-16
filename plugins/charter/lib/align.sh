#!/usr/bin/env bash
# charter — support lib: the alignment floor. Helpers for the Stop-time
# decision-alignment gate (bin/charter-align-gate.sh): where charter keeps its
# (cache-only) throttle state, a working-tree fingerprint so the gate never
# re-checks the same change, a bounded model-readable excerpt of the recorded
# decisions, and the cheap deterministic pre-filter that decides whether a change
# plausibly bears on a recorded decision (so the gate stays silent on routine
# edits). Self-contained; sourced transitively via charter.sh.

# Cache-only state dir (NOT the project) — throttle markers for the Stop gate.
# Override via CLAUDE_CHARTER_LOG_DIR. This is the only place charter writes.
charter_log_dir() { printf '%s' "${CLAUDE_CHARTER_LOG_DIR:-$HOME/.claude/state/charter}"; }

# Working-tree fingerprint: tracked diff vs HEAD + untracked content. Same change
# → same hash, so the gate doesn't re-block a tree it already checked. Empty
# outside a git repo. Mirrors tidy's verify throttle (install boundary: no shared lib).
charter_tree_hash() {
  local root="$1" f
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  {
    git -C "$root" diff HEAD 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null \
      | while IFS= read -r f; do cksum "$root/$f" 2>/dev/null; done
  } | cksum | awk '{print $1"-"$2}'
}

# A bounded, model-readable excerpt of the recorded decisions, to put in front of
# the model at the gate. A single file → its first $max lines; an ADR directory →
# the title (first "# " heading, else filename) of each ADR. Empty when none.
charter_decisions_excerpt() {
  local root="$1" max="${2:-60}" path g t
  path="$(charter_decisions_path "$root")"; [ -n "$path" ] || return 0
  case "$path" in
    */)                                       # ADR directory → one line per decision
      for g in "$root/$path"*.md; do
        [ -f "$g" ] || continue
        t="$(grep -m1 '^# ' "$g" 2>/dev/null | sed 's/^# *//')"
        [ -n "$t" ] || t="$(basename "$g")"
        printf '  • %s\n' "$t"
      done ;;
    *) head -n "$max" "$root/$path" 2>/dev/null ;;
  esac
}

# Cheap, deterministic pre-filter: does this change plausibly bear on a recorded
# decision? Decisions get reversed where new tech/approach enters — dependency
# manifests, config, infra, migrations/schema — or when a distinctive token the
# decisions doc fences in `backticks` turns up in the diff (e.g. a `Postgres`
# decision vs. a diff adding a mongo client names the rejected/chosen tech).
# Routine edits inside existing files almost never reverse a recorded decision, so
# they stay silent — keeping the gate token-cheap. Prints "yes" when the change
# should be adjudicated, nothing otherwise.
charter_change_touches_decisions() {
  local root="$1" changed path diff toks tok
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  changed="$(git -C "$root" status --porcelain 2>/dev/null | awk '{print $NF}')"
  [ -n "$changed" ] || return 0
  # 1) decision-bearing surfaces (paths): deps, lockfiles, config, infra, schema.
  if printf '%s\n' "$changed" | grep -qiE \
    '(^|/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|go\.mod|go\.sum|requirements\.txt|pyproject\.toml|Pipfile|Cargo\.toml|Cargo\.lock|Gemfile|pom\.xml|build\.gradle|Dockerfile|docker-compose[^/]*|[^/]*\.tf|[^/]*\.tfvars)$|(^|/)(migrations?|schema)(/|$)|\.sql$|(^|/)[^/]*\.config\.[A-Za-z]+$'; then
    printf 'yes'; return 0
  fi
  # 2) a distinctive `code`-fenced token from the decisions doc appears in the
  # change. Scan the tracked diff AND new-file contents — `git diff HEAD` omits
  # untracked files, and a brand-new file is exactly where new tech enters.
  path="$(charter_decisions_path "$root")"; [ -n "$path" ] || return 0
  local f
  diff="$( { git -C "$root" diff HEAD 2>/dev/null
             git -C "$root" ls-files --others --exclude-standard 2>/dev/null \
               | while IFS= read -r f; do cat "$root/$f" 2>/dev/null; done; } )"
  [ -n "$diff" ] || return 0
  # The backticks below are literal regex chars (matching `fenced` tokens), not a
  # command substitution — SC2016 misreads them.
  # shellcheck disable=SC2016
  case "$path" in
    */) toks="$(grep -rhoE '`[A-Za-z0-9_.@/-]{3,}`' "$root/$path" 2>/dev/null)" ;;
    *)  toks="$(grep -ohE  '`[A-Za-z0-9_.@/-]{3,}`' "$root/$path" 2>/dev/null)" ;;
  esac
  while IFS= read -r tok; do
    tok="${tok//\`/}"; [ -n "$tok" ] || continue
    printf '%s' "$diff" | grep -qiF -- "$tok" && { printf 'yes'; return 0; }
  done <<< "$toks"
  return 0
}
