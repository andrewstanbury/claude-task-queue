#!/usr/bin/env bash
# tidy — blast-radius library: surface what depends on a touched file so a
# change's affected surface gets test coverage. Lightweight git grep, not static
# analysis. Kept in its own unit so lib/tidy.sh stays focused. Sourced by
# bin/tidy-touch.sh (alongside lib/tidy.sh, which provides tidy_log/tidy_log_dir).

set -uo pipefail

# A touched Go file's package import path = the module (from the nearest go.mod)
# plus the file's directory relative to it. This is what OTHER packages import, so
# it's a far more precise blast-radius key than the basename. Prints it or nothing
# (no go.mod / no module line). No `go` toolchain needed.
tidy_go_import_path() {
  local file="$1" dir d gomod mod moddir reldir
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 0
  d="$dir"; gomod=""
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/go.mod" ] && { gomod="$d/go.mod"; break; }
    d="$(dirname "$d")"
  done
  [ -n "$gomod" ] || return 0
  mod="$(awk '/^module / {print $2; exit}' "$gomod" 2>/dev/null)"
  [ -n "$mod" ] || return 0
  moddir="$(dirname "$gomod")"
  if [ "$dir" = "$moddir" ]; then printf '%s' "$mod"
  else reldir="${dir#"$moddir"/}"; printf '%s/%s' "$mod" "$reldir"; fi
}

# Exact Go importers via `go list` — the toolchain's own import graph, so it
# beats grepping for the quoted path (no false hits in comments/strings, catches
# aliased/dot imports). The full-module scan is potentially slow, so it's bounded
# by `timeout` and CACHED per module per session (run at most once). Prints
# "<n>\t<sample-packages>" of packages importing IMPORTPATH, or empty when go
# succeeded but nothing imports it. Returns non-zero (→ caller falls back to grep)
# when go is absent, disabled (CLAUDE_TIDY_BLAST_GOLIST=0), or the scan failed.
tidy_go_importers() {
  local file="$1" importpath="$2" sid="${3:-}" dir d moddir cache list importers n sample
  [ "${CLAUDE_TIDY_BLAST_GOLIST:-1}" = "0" ] && return 1
  tidy_have go || return 1
  [ -n "$importpath" ] || return 1
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 1
  d="$dir"; moddir=""
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -f "$d/go.mod" ] && { moddir="$d"; break; }
    d="$(dirname "$d")"
  done
  [ -n "$moddir" ] || return 1

  cache="$(tidy_log_dir)/golist/$(printf '%s' "${sid:0:8}-$moddir" | sed 's:/:-:g')"
  if [ ! -f "$cache" ]; then
    mkdir -p "$(dirname "$cache")" 2>/dev/null || true
    local out rc tmpl='{{.ImportPath}}{{range .Imports}} {{.}}{{end}}{{range .TestImports}} {{.}}{{end}}'
    if tidy_have timeout; then
      out="$(cd "$moddir" && timeout "${CLAUDE_TIDY_BLAST_GOLIST_TIMEOUT:-8}" go list -e -f "$tmpl" ./... 2>/dev/null)"; rc=$?
    else
      out="$(cd "$moddir" && go list -e -f "$tmpl" ./... 2>/dev/null)"; rc=$?
    fi
    if [ "$rc" -ne 0 ] || [ -z "$out" ]; then
      printf 'FAILED\n' > "$cache" 2>/dev/null || true     # sentinel: don't retry this session
      return 1
    fi
    printf '%s\n' "$out" > "$cache" 2>/dev/null || true
  fi
  list="$(cat "$cache" 2>/dev/null || true)"
  [ "$list" = "FAILED" ] && return 1

  # A package imports the target iff the target path appears in its import fields
  # (2..N); print the importing package path (field 1), excluding the target's own.
  importers="$(printf '%s\n' "$list" | awk -v t="$importpath" '
    { for (i=2;i<=NF;i++) if ($i==t) { if ($1!=t) print $1; break } }' | sort -u)"
  [ -n "$importers" ] || return 0                          # go ran, nothing imports it
  n="$(printf '%s\n' "$importers" | grep -c .)"
  sample="$(printf '%s\n' "$importers" | head -n 3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  printf '%d\t%s' "$n" "$sample"
}

# Surface what references the touched file. For Go, the toolchain's exact
# importers via `go list` (falling back to grepping the precise import path); for
# other files, the basename in import context (guarded against noise). Deduped
# once per file per session. Empty when no dependents, not a git repo, or
# disabled (CLAUDE_TIDY_BLAST=0).
tidy_blast_radius() {
  local file="$1" sid="${2:-}" label root rel hits n sample mdir mark
  [ "${CLAUDE_TIDY_BLAST:-1}" = "0" ] && return 0
  [ -f "$file" ] || return 0
  root="$(git -C "$(dirname "$file")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$root" ] || return 0
  rel="${file#"$root"/}"

  case "$file" in
    *.go)
      label="$(tidy_go_import_path "$file" 2>/dev/null || true)"
      [ -n "$label" ] || return 0 ;;
    *)
      label="$(basename "$file")"; label="${label%.*}"
      # A short or generic basename grep-matches too much prose/config to be
      # signal (e.g. "tidy", "blast"); skip it. Min length raised to 5.
      [ "${#label}" -ge 5 ] || return 0
      case "$label" in
        index|main|app|mod|utils|util|types|type|config|helpers|helper|test|tests|\
        lib|setup|init|README|index.d|model|models|view|views|store|stores|client|\
        server|service|services|handler|handlers|route|routes|component|components|\
        constants|common|core|base|data|schema|schemas|page|pages|layout|style|\
        styles|theme|hooks|api) return 0 ;;
      esac ;;
  esac

  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/blast-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true

  # Go: prefer the toolchain's exact importer set. On success ($? = 0) that's the
  # precise answer (importing PACKAGES); a non-zero return means go is absent/
  # disabled/failed, so fall through to the grep heuristic below.
  if [ "${file##*.}" = "go" ]; then
    local gi
    if gi="$(tidy_go_importers "$file" "$label" "$sid")"; then
      [ -n "$gi" ] || return 0                              # go ran, nothing imports it
      n="${gi%%$'\t'*}"; sample="${gi#*$'\t'}"
      tidy_log blast "file=$file n=$n via=golist"
      printf 'blast-radius (~%d package(s) import %s): cover these with tests as part of this change; e.g. %s' "$n" "$label" "$sample"
      return 0
    fi
  fi

  case "$file" in
    *.go) hits="$(git -C "$root" grep -lF "\"$label\"" -- '*.go' 2>/dev/null | grep -vF "$rel" || true)" ;;
    *)
      # Require the basename to sit right after a quote/slash/dot — i.e. look like
      # a module specifier (`'./foo'`, `"foo"`, `pkg.foo`) rather than the bare word
      # in prose — and skip doc/data files, which carry the word without importing
      # it. Cuts the false positives the looser heuristic produced.
      hits="$(git -C "$root" grep -lE "(import|require|from|use|include).*['\"/.]${label}\b" \
                -- . ':!*.md' ':!*.json' ':!*.txt' ':!*.lock' ':!*.yaml' ':!*.yml' \
                   ':!*.toml' ':!*.cfg' ':!*.ini' ':!*.csv' 2>/dev/null \
              | grep -vF "$rel" || true)" ;;
  esac
  [ -n "$hits" ] || return 0

  n="$(printf '%s\n' "$hits" | grep -c .)"
  sample="$(printf '%s\n' "$hits" | head -n 3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  tidy_log blast "file=$file n=$n via=grep"
  printf 'blast-radius (~%d files reference %s): cover these with tests as part of this change; e.g. %s' "$n" "$label" "$sample"
}
