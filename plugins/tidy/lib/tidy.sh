#!/usr/bin/env bash
# tidy — support lib for the tidy-as-you-touch plugin.
#
# When you edit a file, the PostToolUse hook formats it (auto-applying only
# behavior-preserving fixes) and surfaces linter findings for the model to
# address — so an actively-worked project converges toward clean code, scoped
# to the files you touch. This lib holds the language dispatch and the Go
# handler; the bin/ entrypoints stay thin.
#
# It WRITES to your working tree (formatting), unlike a read-only plugin — so
# every operation is best-effort, behavior-preserving, scoped to the one edited
# file, and must never break the edit that triggered it.

set -uo pipefail

# ---- locations (overridable for tests) -------------------------------------

tidy_log_dir()  { printf '%s' "${CLAUDE_TIDY_LOG_DIR:-$HOME/.claude/state/tidy}"; }
tidy_log_file() { printf '%s/activity.log' "$(tidy_log_dir)"; }

# ---- helpers ---------------------------------------------------------------

tidy_have() { command -v "$1" >/dev/null 2>&1; }

# Append one best-effort log line; never fails the caller. CLAUDE_TIDY_LOG_DISABLED=1 to mute.
tidy_log() {
  [ -n "${CLAUDE_TIDY_LOG_DISABLED:-}" ] && return 0
  local event="$1" detail="${2:-}" ts dir
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '?')"
  dir="$(tidy_log_dir)"
  { mkdir -p "$dir" 2>/dev/null && printf '%s\t%s\t%s\n' "$ts" "$event" "$detail" >> "$(tidy_log_file)"; } 2>/dev/null || true
  return 0
}

# Map a path to a supported language tag, or "" (→ the hook no-ops).
tidy_lang_for_file() {
  case "$1" in
    *.go) printf 'go' ;;
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte|*.css|*.scss|*.sass|*.less)
          printf 'web' ;;
    *)    printf '' ;;
  esac
}

# A Go file we must not touch: generated code carries a well-known marker.
tidy_is_generated_go() {
  head -n 10 "$1" 2>/dev/null | grep -qE '^// Code generated .* DO NOT EDIT\.$'
}

# Content fingerprint, to tell whether a formatter actually changed the file.
tidy_hash() { cksum "$1" 2>/dev/null | awk '{print $1"-"$2}'; }

# ---- Go handler ------------------------------------------------------------

# Format the touched Go file in place (behavior-preserving) and collect any
# golangci-lint findings FOR THAT FILE. Prints a tab-separated summary line:
#   "<formatted:0|1>\t<lintfindings-or-empty>"
# Prints nothing (and returns 0) when there's nothing worth saying.
tidy_handle_go() {
  local file="$1"
  [ -f "$file" ] || return 0
  if tidy_is_generated_go "$file"; then tidy_log skip "generated: $file"; return 0; fi

  local before after tool="" changed=0
  before="$(tidy_hash "$file")"
  if   tidy_have goimports; then tool=goimports; goimports -w "$file" 2>/dev/null || true
  elif tidy_have gofumpt;   then tool=gofumpt;   gofumpt   -w "$file" 2>/dev/null || true
  elif tidy_have gofmt;     then tool=gofmt;     gofmt     -w "$file" 2>/dev/null || true
  fi
  after="$(tidy_hash "$file")"
  [ -n "$tool" ] && [ "$before" != "$after" ] && changed=1

  # Lint the file's package, then keep only findings that name this file, so the
  # surfaced issues stay scoped to what was just touched. Best-effort + bounded.
  local lint="" dir base
  dir="$(dirname "$file")"; base="$(basename "$file")"
  if tidy_have golangci-lint; then
    lint="$(
      cd "$dir" 2>/dev/null || exit 0
      golangci-lint run 2>/dev/null | grep -F "$base" | head -n 20
    )"
  fi

  [ "$changed" -eq 0 ] && [ -z "$lint" ] && return 0
  tidy_log go "file=$file fmt=$tool changed=$changed lint=$( [ -n "$lint" ] && echo yes || echo no )"
  printf '%s\t%s' "$changed" "$lint"
}

# ---- web handler (shift the Lighthouse audit left) -------------------------

# Resolve a node CLI for the touched file: prefer the project-local
# node_modules/.bin/<tool> (walking up from the file), else PATH. Prints the
# path, or nothing.
tidy_node_bin() {
  local file="$1" tool="$2" dir
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -x "$dir/node_modules/.bin/$tool" ] && { printf '%s' "$dir/node_modules/.bin/$tool"; return 0; }
    dir="$(dirname "$dir")"
  done
  command -v "$tool" 2>/dev/null
}

# Surface the project's OWN web-linter findings for the touched file — eslint
# (incl. eslint-plugin-jsx-a11y) for JS/TS/JSX/TSX/Vue/Svelte, stylelint for
# CSS/SCSS/Less. This shifts much of Lighthouse's accessibility / best-practices
# audit to edit time. Read-only: no `--fix` (it can change behavior); we only
# report. Acts only when the project actually has the linter; silent otherwise.
# Prints "0\t<findings>" (changed=0, so the touch hook renders it like a lint
# block) or nothing. Exit 1 from the linter = problems found; 0 = clean; 2+ =
# config/crash → treated as no-op.
tidy_handle_web() {
  local file="$1" tool bin out rc
  case "$file" in
    *.js|*.jsx|*.ts|*.tsx|*.mjs|*.cjs|*.vue|*.svelte) tool=eslint ;;
    *.css|*.scss|*.sass|*.less)                       tool=stylelint ;;
    *) return 0 ;;
  esac
  bin="$(tidy_node_bin "$file" "$tool")" || return 0
  [ -n "$bin" ] || return 0
  out="$("$bin" "$file" 2>/dev/null)"; rc=$?
  [ "$rc" -eq 1 ] || return 0
  [ -n "$out" ] || return 0
  tidy_log web "file=$file tool=$tool findings=yes"
  printf '0\t%s' "$(printf '%s\n' "$out" | head -n 25)"
}

# ---- TDD nudge --------------------------------------------------------------

# Encourage a sibling test for a touched Go SOURCE file (test-first). Skips test
# files and generated files, and is deduped per session+file (one nudge each) so
# it stays gentle in a test-poor legacy repo — the ratchet, not a nag. Prints
# the nudge line or nothing.
#   $1 file   the edited file
#   $2 sid    session id (optional; used to dedupe per session)
tidy_tdd_nudge() {
  local file="$1" sid="${2:-}"
  [ "$(tidy_lang_for_file "$file")" = "go" ] || return 0
  case "$file" in *_test.go) return 0 ;; esac
  tidy_is_generated_go "$file" && return 0

  local mdir mark
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0                         # already nudged this file this session
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true

  local sibling; sibling="${file%.go}_test.go"
  if [ -f "$sibling" ]; then
    printf 'TDD: extend %s to cover this change before moving on.' "$(basename "$sibling")"
  else
    printf 'TDD: %s has no test — add %s covering this change (test-first).' \
      "$(basename "$file")" "$(basename "$sibling")"
  fi
}

# ---- size-vs-complexity (the auto, no-trigger size check) -------------------
#
# The line budget over which a file is a decomposition candidate. A nudge, not a
# rule — a long-but-cohesive file can be fine; the model judges size-vs-complexity.
tidy_size_budget() { printf '%s' "${CLAUDE_TIDY_SIZE_BUDGET:-400}"; }

# Per-touch (PostToolUse): if the just-edited file is over budget, return a one-
# line nudge — once per file per session (deduped like the TDD nudge), skipping
# binaries and obvious non-handwritten files. Empty when fine or disabled.
tidy_size_nudge() {
  local file="$1" sid="${2:-}" budget n mdir mark
  [ "${CLAUDE_TIDY_SIZE_CHECK:-1}" = "0" ] && return 0
  [ -f "$file" ] || return 0
  LC_ALL=C grep -Iq . "$file" 2>/dev/null || return 0       # skip binaries
  case "$file" in *.lock|*-lock.json|*.min.*|*.map|*.svg|*.snap) return 0 ;; esac
  tidy_is_generated_go "$file" && return 0
  budget="$(tidy_size_budget)"
  n="$(wc -l < "$file" 2>/dev/null || printf 0)"; n="${n//[^0-9]/}"; [ -n "$n" ] || n=0
  [ "$n" -gt "$budget" ] || return 0
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/size-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true
  printf 'size: %s is %d lines (budget %d) — if it now covers more than one responsibility, extract a focused unit.' \
    "$(basename "$file")" "$n" "$budget"
}

# Whole-project (SessionStart light distill): print "<lines>\t<path>" for each
# text file over budget, heaviest first. One wc -l pass; read-only. Empty when
# nothing is over budget or the check is disabled.
tidy_oversized_files() {
  local root="$1" budget="${2:-$(tidy_size_budget)}" listing
  [ "${CLAUDE_TIDY_SIZE_CHECK:-1}" = "0" ] && return 0
  [ -d "$root" ] || return 0
  if git -C "$root" rev-parse >/dev/null 2>&1; then
    listing="$(cd "$root" && git ls-files -z --cached --others --exclude-standard 2>/dev/null | xargs -0 wc -l 2>/dev/null)"
  else
    listing="$(cd "$root" && find . -type f -not -path '*/.git/*' -print0 2>/dev/null | xargs -0 wc -l 2>/dev/null)"
  fi
  printf '%s\n' "$listing" | awk -v b="$budget" '
    { n=$1+0; $1=""; sub(/^[ \t]+/,""); p=$0 }
    p != "total" && p != "" && n > b { printf "%d\t%s\n", n, p }
  ' | sort -rn -k1,1
}

# ---- currency / modernization ----------------------------------------------

# Surface the nearest dependency manifest's *pinned versions* so the model can
# judge what's deprecated or behind latest stable (that's world knowledge a hook
# can't have). Facts here, judgment for the model — and it NEVER auto-upgrades (a
# dep bump is the highest-blast-radius change there is). Stack-level, so deduped
# once per manifest per session. Prints a one-line nudge or nothing.
tidy_currency_nudge() {
  local file="$1" sid="${2:-}" dir m manifest="" kind="" pins="" mdir mark node reqs
  [ "${CLAUDE_TIDY_CURRENCY:-1}" = "0" ] && return 0
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 0
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for m in package.json go.mod Cargo.toml pyproject.toml requirements.txt Gemfile composer.json pom.xml build.gradle build.gradle.kts; do
      [ -f "$dir/$m" ] && { manifest="$dir/$m"; kind="$m"; break; }
    done
    [ -n "$manifest" ] && break
    dir="$(dirname "$dir")"
  done
  [ -n "$manifest" ] || return 0

  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/currency-$(printf '%s' "${sid:0:8}-$manifest" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true

  case "$kind" in
    package.json)
      pins="$(jq -r '((.dependencies // {}) + (.devDependencies // {})) | to_entries | map("\(.key)@\(.value)") | .[0:12] | join(", ")' "$manifest" 2>/dev/null || true)"
      node="$(jq -r '.engines.node // empty' "$manifest" 2>/dev/null || true)"
      [ -n "$node" ] && pins="node@$node; $pins" ;;
    go.mod)
      pins="$(grep -E '^go [0-9]' "$manifest" 2>/dev/null | head -n1)"
      reqs="$(grep -E '^[[:space:]]+[^ ]+ v[0-9]' "$manifest" 2>/dev/null | sed 's/^[[:space:]]*//' | head -n 8 | tr '\n' ';')"
      [ -n "$reqs" ] && pins="$pins; $reqs" ;;
  esac

  tidy_log currency "manifest=$manifest"
  if [ -n "$pins" ]; then
    printf 'currency: nearest manifest %s pins %s — judge whether any are behind latest stable or deprecated and flag modernization in the touched scope (do not auto-upgrade).' "$kind" "$pins"
  else
    printf 'currency: nearest manifest is %s — check whether its pinned tech is behind latest stable or deprecated and flag modernization in the touched scope (do not auto-upgrade).' "$kind"
  fi
}

# ---- blast-radius ----------------------------------------------------------

# Approximate dependent-surfacing: when you change a file, grep the repo for
# import-context references to its basename so the change's blast radius is
# visible and TDD can cover the affected surface. Lightweight (git grep), not
# static analysis — guarded against noise (min name length, skip generic names,
# import-context only, capped sample) and deduped once per file per session.
# Empty when no dependents, not a git repo, or disabled (CLAUDE_TIDY_BLAST=0).
tidy_blast_radius() {
  local file="$1" sid="${2:-}" base root rel hits n sample mdir mark
  [ "${CLAUDE_TIDY_BLAST:-1}" = "0" ] && return 0
  [ -f "$file" ] || return 0
  base="$(basename "$file")"; base="${base%.*}"
  [ "${#base}" -ge 4 ] || return 0
  case "$base" in
    index|main|app|mod|utils|util|types|type|config|helpers|helper|test|tests|lib|setup|init|README|index.d) return 0 ;;
  esac
  root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || return 0
  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/blast-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true
  rel="${file#"$root"/}"
  hits="$(git -C "$root" grep -lE "(import|require|from|use|include).*${base}" -- . 2>/dev/null | grep -vF "$rel" || true)"
  [ -n "$hits" ] || return 0
  n="$(printf '%s\n' "$hits" | grep -c .)"
  sample="$(printf '%s\n' "$hits" | head -n 3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  tidy_log blast "file=$file n=$n"
  printf 'blast-radius (approx): ~%d file(s) reference %s — your change may affect them; cover the affected surface with tests. e.g. %s' "$n" "$base" "$sample"
}
