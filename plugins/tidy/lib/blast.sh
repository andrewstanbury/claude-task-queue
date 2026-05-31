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

# Surface what references the touched file. For Go, search the package's import
# path (precise); for other files, the basename in import context (guarded
# against noise). Deduped once per file per session. Empty when no dependents,
# not a git repo, or disabled (CLAUDE_TIDY_BLAST=0).
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
      [ "${#label}" -ge 4 ] || return 0
      case "$label" in
        index|main|app|mod|utils|util|types|type|config|helpers|helper|test|tests|lib|setup|init|README|index.d) return 0 ;;
      esac ;;
  esac

  mdir="$(tidy_log_dir)/nudged"
  mark="$mdir/blast-$(printf '%s' "${sid:0:8}-$file" | sed 's:/:-:g')"
  [ -f "$mark" ] && return 0
  { mkdir -p "$mdir" 2>/dev/null && : > "$mark"; } 2>/dev/null || true

  case "$file" in
    *.go) hits="$(git -C "$root" grep -lF "\"$label\"" -- '*.go' 2>/dev/null | grep -vF "$rel" || true)" ;;
    *)    hits="$(git -C "$root" grep -lE "(import|require|from|use|include).*${label}" -- . 2>/dev/null | grep -vF "$rel" || true)" ;;
  esac
  [ -n "$hits" ] || return 0

  n="$(printf '%s\n' "$hits" | grep -c .)"
  sample="$(printf '%s\n' "$hits" | head -n 3 | tr '\n' ',' | sed 's/,$//; s/,/, /g')"
  tidy_log blast "file=$file n=$n"
  printf 'blast-radius (~%d files reference %s): cover the affected surface; e.g. %s' "$n" "$label" "$sample"
}
