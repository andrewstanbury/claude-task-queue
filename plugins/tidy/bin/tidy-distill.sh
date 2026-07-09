#!/usr/bin/env bash
# tidy-distill — read-only whole-project "weight report".
#
# The subtractive prune force's whole-project half (the per-touch half is the
# clean-as-you-go standard). It measures where a project is heavy so the model
# can run the judgment pass — dead code, duplication, doc↔code drift — and
# propose subtractive changes. The script only surfaces *measurable* facts; the
# judgment is the model's job (a script can't reliably know "this is dead code").
#
# Invoked automatically by the SessionStart hook when the debt threshold is
# crossed (no manual command); it never writes the project and never hard-fails
# the caller. Language-agnostic — it uses git to enumerate tracked +
# new-but-not-ignored files, falling back to find.
#
# Tunable: CLAUDE_TIDY_SIZE_BUDGET (lines/file, default 300). Lists the 10 heaviest.

set -uo pipefail

budget="${CLAUDE_TIDY_SIZE_BUDGET:-300}"
topn=10

# Resolve the project root from the first arg (or cwd), preferring the git top.
root="${1:-}"
if [ -z "$root" ] || [ ! -d "$root" ]; then root="$PWD"; fi
top="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$top" ] && root="$top"

is_git=0
git -C "$root" rev-parse >/dev/null 2>&1 && is_git=1

# Enumerate candidate files (relative paths). Tracked + untracked-not-ignored in
# a git repo; otherwise a plain find that skips the VCS dir.
list_files() {
  if [ "$is_git" -eq 1 ]; then
    git -C "$root" ls-files --cached --others --exclude-standard 2>/dev/null
  else
    ( cd "$root" && find . -type f -not -path '*/.git/*' 2>/dev/null | sed 's|^\./||' )
  fi
}

# Walk the files once: total counts, per-file line counts (text only), junk list.
total_files=0
total_lines=0
sizes=""        # "<lines>\t<path>\n" for text files
junk=""         # newline list of junk-looking paths
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ -f "$root/$f" ] || continue
  case "$f" in
    *.bak|*.old|*.orig|*.tmp|*.swp|*~) junk="$junk$f"$'\n' ;;
  esac
  # Skip binaries for the line tally (grep -I => no match on binary).
  LC_ALL=C grep -Iq . "$root/$f" 2>/dev/null || continue
  n="$(wc -l < "$root/$f" 2>/dev/null || printf 0)"
  n="${n//[^0-9]/}"; [ -n "$n" ] || n=0
  total_files=$((total_files + 1))
  total_lines=$((total_lines + n))
  sizes="$sizes$n"$'\t'"$f"$'\n'
done < <(list_files)

# Cruft markers (tracked files; fast via git grep when available).
markers=0
marker_files=0
if [ "$is_git" -eq 1 ]; then
  markers="$(git -C "$root" grep -hIE 'TODO|FIXME|HACK|XXX' -- . 2>/dev/null | awk 'END{print NR}')"
  marker_files="$(git -C "$root" grep -lIE 'TODO|FIXME|HACK|XXX' -- . 2>/dev/null | awk 'END{print NR}')"
else
  markers="$(grep -rhIE 'TODO|FIXME|HACK|XXX' "$root" 2>/dev/null | awk 'END{print NR}')"
fi
[ -n "$markers" ] || markers=0
[ -n "$marker_files" ] || marker_files=0

over="$(printf '%s' "$sizes" | awk -F'\t' -v b="$budget" 'NF==2 && $1+0 > b' | sort -rn -k1,1)"
over_n="$(printf '%s' "$over" | grep -c . || true)"

# ---- report ----------------------------------------------------------------
printf 'tidy-distill — whole-project weight report\n  root: %s\n\n' "$root"

printf 'Inventory\n'
printf '  %s text files, %s total lines  (budget: %s lines/file)\n\n' \
  "$total_files" "$total_lines" "$budget"

printf 'Heaviest files (top %s)\n' "$topn"
if [ -n "$sizes" ]; then
  printf '%s' "$sizes" | sort -rn -k1,1 | head -n "$topn" \
    | awk -F'\t' -v b="$budget" '{flag=($1+0>b)?"  ⚠ over budget":""; printf "  %6d  %s%s\n", $1, $2, flag}'
else
  printf '  (no text files found)\n'
fi
printf '\n'

if [ "$over_n" -gt 0 ]; then
  printf 'Over budget (%s) — first candidates for splitting or pruning:\n' "$over_n"
  printf '%s' "$over" | awk -F'\t' '{printf "  %6d  %s\n", $1, $2}'
  printf '\n'
fi

printf 'Cruft markers: %s TODO/FIXME/HACK/XXX' "$markers"
[ "$marker_files" -gt 0 ] && printf ' across %s files' "$marker_files"
printf '\n'

if [ -n "$junk" ]; then
  printf 'Junk-looking files (%s): tmp/backup artefacts that usually should not be committed\n' \
    "$(printf '%s' "$junk" | grep -c .)"
  printf '%s' "$junk" | sed 's/^/  /'
fi
printf '\n'

# ---- complexity surface ----------------------------------------------------
# Beyond file SIZE, surface architectural WEIGHT — external dependencies and the
# number of top-level areas — because unwarranted complexity is the upstream
# driver of a growing blast radius (each dep/layer adds coupling and reach). A
# rough estimate from root manifests + the file tree, not exact resolution.
deps=0; dep_src=""
if [ -f "$root/package.json" ] && command -v jq >/dev/null 2>&1; then
  d="$(jq -r '((.dependencies//{})|length) + ((.devDependencies//{})|length)' "$root/package.json" 2>/dev/null || printf 0)"
  d="${d//[^0-9]/}"; [ -n "$d" ] && { deps=$((deps + d)); dep_src="$dep_src package.json:$d"; }
fi
if [ -f "$root/go.mod" ]; then
  d="$(grep -cE '^[[:space:]]+[^[:space:]]+ v[0-9]|^require[[:space:]]+[^[:space:]]+ v[0-9]' "$root/go.mod" 2>/dev/null || printf 0)"
  d="${d//[^0-9]/}"; [ -n "$d" ] && [ "$d" -gt 0 ] && { deps=$((deps + d)); dep_src="$dep_src go.mod:$d"; }
fi
if [ -f "$root/requirements.txt" ]; then
  d="$(grep -cvE '^[[:space:]]*(#|$)' "$root/requirements.txt" 2>/dev/null || printf 0)"
  d="${d//[^0-9]/}"; [ -n "$d" ] && [ "$d" -gt 0 ] && { deps=$((deps + d)); dep_src="$dep_src requirements.txt:$d"; }
fi
areas="$(list_files | awk -F/ 'NF>1{print $1}' | sort -u \
  | grep -viE '^(node_modules|vendor|dist|build|target|out|\..*|__pycache__|coverage)$' \
  | grep -c . || true)"
[ -n "$areas" ] || areas=0

if [ "$deps" -gt 0 ] || [ "$areas" -gt 0 ]; then
  printf 'Complexity surface (drivers of blast-radius growth)\n'
  printf '  dependencies: %s%s\n' "$deps" "${dep_src:+ ($dep_src )}"
  printf '  top-level areas: %s\n' "$areas"
  printf '  → each dependency and layer widens coupling and reach. Prune what is not\n'
  printf '    earning its keep, and resist adding complexity without a present\n'
  printf '    requirement (YAGNI — the burden of proof is on the complexity).\n\n'
fi

cat <<'EOF'
Next — the subtractive pass (model judgment; the script can't do this):
  - In the heaviest / over-budget files, hunt for dead code, duplication, and
    "this change made X redundant" — propose deletions and merges (reuse before
    create; prefer the smaller surface).
  - Reconcile docs vs code: README / ROADMAP / MAP referencing moved or removed
    files, stale examples, drifted instructions.
  - Confirm before deleting; keep changes scoped and test-covered. The goal is
    net complexity DOWN, not just reorganised.
EOF
exit 0
