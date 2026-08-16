#!/usr/bin/env bash
# candidates.sh — what burn-down is allowed to build, in strict priority order.
#
# THE WHOLE POINT: this never invents work while any recorded signal remains. Every candidate is
# something the owner already wrote down and then didn't get to — a deferred decision, a roadmap
# line, a TODO, a declared coverage gap. That keeps authorship of "what is worth doing" with the
# owner even when the building happens while they are asleep, which is the one property that makes
# unattended generation defensible at all.
#
# Ranked, highest signal first:
#   1 parked   a ❓ park carrying `rec:` — the owner deferred THIS work and a recommendation is
#              already written. Strongest signal in the repo: chosen, reasoned, not yet done.
#              EXCLUDES `decision:` parks (written by the ask-guard from an intercepted question —
#              a decision by construction, the owner's to ANSWER, never work to build) and
#              `decompose:` parks (R65 — they exist because context is MISSING). Both exclusions
#              close recorded R82 soft spots: rank 1 stopped offering decisions as buildable work,
#              and auto-parks can no longer crowd ranks 2-4 out of the candidate list entirely.
#   2 roadmap  an unchecked `- [ ]` item in a ROADMAP — stated intent, explicitly not yet built.
#   3 todo     a TODO/FIXME/XXX in tracked source — a note-to-self left at the point of pain.
#   4 gap      a contract page documenting behaviour with NO automated test referenced.
#   5 rework   a component the rework ledger flags as repeatedly FAILING (R94) — the largest
#              recorded-signal work, so it ranks after every cleanup and before invention.
#   6 invent   NOTHING recorded remains. Emitted only when 1-5 are empty, and marked so the build
#              step can treat it with the suspicion it deserves.
#
# Output: one candidate per line, `<rank>|<source>|<text>`. Empty output means nothing to do,
# which is a perfectly good answer and the common one.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${BURNDOWN_ROOT:-$PWD}")"
# The tool's own tree as a git pathspec, ONLY when it actually sits inside the project being
# scanned (see rank 3). Empty otherwise, which is the normal install: nothing to exclude.
#
# BOTH SIDES RESOLVED (`pwd -P`), and this is not defensive padding — it is the trap companion.sh
# already documents one function over: bash's `pwd` is LOGICAL, so a path reached through a symlink
# stays symlinked while git reports the physical one, and comparing them silently matches NOTHING.
# That is precisely macOS's /var -> /private/var, which is why this shipped green on Linux and RED
# on the macOS lane: the exclusion quietly did nothing there, so the tool fed on its own source
# again. Reproduced on Linux through a deliberate symlink before fixing.
SELFTREE=""
_selfdir="$(cd "$PLUGIN_DIR" 2>/dev/null && pwd -P)" || _selfdir="$PLUGIN_DIR"
[ -n "$_selfdir" ] || _selfdir="$PLUGIN_DIR"
_scanroot="$(cd "$root" 2>/dev/null && pwd -P)" || _scanroot="$root"
[ -n "$_scanroot" ] || _scanroot="$root"
case "$_selfdir/" in
  "$_scanroot"/*) SELFTREE=":!${_selfdir#"$_scanroot"/}" ;;
esac
# VENDORED-TREE NOISE, and why this is NOT the R9 violation it looks like (settled by measurement
# 2026-08-16). R9 forbids hardcoded ecosystem ALLOWLISTS used for RECOGNITION — deciding what a
# project IS, which the model must do instead. This is the opposite shape: a denylist of directories
# whose contents are somebody else's code, used to suppress noise in a mechanical ranker that has no
# model in the loop to delegate to.
#
# Measured both ways rather than argued: when vendored dirs are UNTRACKED (the normal case, and this
# repo's own) the filter is redundant, because `git grep` never sees them. When a project COMMITS
# them — a real and common choice — it is load-bearing: a fixture with tracked node_modules/ and
# vendor/ went from 3 candidates to 1, i.e. two thirds of rank 3 would have been other people's
# TODOs. Redundant in the common case and decisive in the other is exactly when a cheap filter earns
# its place, so it stays.
#
# Overridable so the two defaults are a starting point rather than our guess about your layout.
VENDOR_RE="${CANDIDATES_VENDOR_RE:-(^|/)(dev/tests|node_modules|vendor)/}"
LIMIT="${CANDIDATES_LIMIT:-5}"          # bounded: a long list is not more useful than a short one
found=0

emit() {  # $1 rank · $2 source · $3 text
  [ "$found" -lt "$LIMIT" ] || return 0
  # One line, framing characters stripped: this feeds a branch name and a commit message later.
  printf '%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\n\r|' '   ' | cut -c1-200)"
  found=$((found+1))
}

# 1 — PARKED DECISIONS THE OWNER HAS ACTUALLY SEEN, carrying a recommendation.
#
# THE SELF-DEALING GUARD (owner-decided 2026-08-15). This rank's whole justification is that "the
# owner deferred THIS work and a recommendation is already written" — chosen, reasoned, not yet
# done. That sentence is FALSE for a park the MODEL wrote and the owner has never laid eyes on,
# and the difference is not cosmetic: caught live, rank 1 was a park authored minutes earlier
# recommending that the model be granted more autonomy. Building it would have been the generator
# implementing its own unreviewed advice — the same mirror as feeding on its own documentation
# (see rank 3), one level up and with far more at stake.
#
# The evidence is a DEFERRAL NOTE, which `/companion:review` writes when the owner walks the pile
# and chooses to defer rather than decide (a decided park is closed and leaves this queue by
# construction, so an OPEN park is either deferred-after-seeing or never-seen). Authorship cannot
# serve here — `tq` does not record it — and neither can age: a park can sit unseen for weeks.
#
# FAILS TO THE SAFE SIDE, deliberately: a store whose parks predate this carries no deferral notes,
# so rank 1 is simply empty and generation falls through to ranks 2-5, which are owner-authored by
# construction (a ROADMAP line, a TODO, an untested flow). Losing a tier is the right cost for
# never auto-building something the owner has not seen.
_rank1_prog='select(.status=="pending")
  | select(((.subject//"")|startswith("❓")) and ((.subject//"")|contains("rec:")))
  | select((((.subject//"")|contains("decision:")) or ((.subject//"")|contains("decompose:")))|not)
  | select([(.notes//[])[] | (.text//"") | ascii_downcase | startswith("deferred")] | any)
  | ((.subject//"")|gsub("[\n\r|]";" "))'
_rank1() {
  local f g; local -a files=()
  while IFS= read -r -d '' f; do [ -n "$f" ] && files+=("$f"); done \
    < <(companion_task_files "$root" 2>/dev/null)
  [ "${#files[@]}" -gt 0 ] || return 0
  # Batch, then per-file only if the batch failed — jq aborts at the first unparseable file, and one
  # torn write must not silently empty the highest-signal rank (the lesson companion_open_tasks
  # already paid for).
  jq -r "$_rank1_prog" "${files[@]}" 2>/dev/null && return 0
  for g in "${files[@]}"; do [ -f "$g" ] && jq -r "$_rank1_prog" "$g" 2>/dev/null; done
  return 0
}
while IFS= read -r line; do
  [ -n "$line" ] || continue
  emit 1 parked "${line###* }"
done < <(_rank1 | head -"$LIMIT")

# 2 — ROADMAP intent. Generic: any ROADMAP-ish markdown, unchecked task-list items only.
if [ "$found" -lt "$LIMIT" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    emit 2 roadmap "$line"
  done < <(find "$root" -maxdepth 2 -iname 'ROADMAP*.md' -type f 2>/dev/null \
           | head -3 | xargs -r grep -h '^[[:space:]]*[-*] \[ \]' 2>/dev/null \
           | sed -e 's/^[[:space:]]*[-*] \[ \][[:space:]]*//' | head -"$LIMIT")
fi

# 3 — TODO markers in TRACKED source only (never vendored or generated trees, which is why this
# asks git rather than walking the filesystem).
if [ "$found" -lt "$LIMIT" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    emit 3 todo "$line"
  # TWO EXCLUSIONS, both learned the hard way — the first run of this against its own repo
  # returned four candidates that were all PROSE ABOUT TODO MARKERS, including this very comment
  # block. A generator that feeds on its own definition is not grounded, it is a mirror.
  #   · `:!*.md` — markdown is prose and checklists, not code annotations. Genuine intent recorded
  #     in markdown is already rank 2, so nothing is lost by declining to read it as rank 3.
  #   · `:!*.yaml`/`:!*.yml` — the same lesson, found again: this repo's CONTRACT is yaml, and its
  #     prose describing the TODO scanner was offered as a TODO to act on. Excluding markdown alone
  #     was never the rule; the rule is that documentation is not a note-to-self left in code.
  #   · this file — self-exclusion is the general rule, not a special case: a tool must never
  #     propose work sourced from its own explanation of what it looks for.
  #   · the tool's OWN TREE — the rule above was written as "this file", which was too narrow by
  #     exactly one directory: `mcp-server/index.js` describes this ranking in a string literal
  #     ("a TODO/FIXME in tracked source") and duly ranked ABOVE two real signals. Same mirror,
  #     one file over. Scoped to $PLUGIN_DIR at runtime rather than any written-down path, so it
  #     stays generic (R9): in a normal install the plugin is not inside the project at all and
  #     this adds nothing, and where it IS vendored in, excluding it is right for that repo too.
  done < <(git -C "$root" grep -nIE '(TODO|FIXME|XXX)[: ]' -- . ':!*.md' ':!*.markdown' ':!*.yaml' ':!*.yml' ${SELFTREE:+"$SELFTREE"} 2>/dev/null \
           | grep -vE "$VENDOR_RE" \
           | grep -vF "${SELF##*/}" \
           | sed -e 's/[[:space:]]*$//' | head -"$LIMIT")
fi

# 4 — UNTESTED CONTRACT: a flow page that documents behaviour but references NO automated test.
# Deliberately not "lines the project marks as judgment-only" — those are marked precisely because
# someone decided they should not be automated, so proposing tests for them argues with a decision
# already made. A page with no test reference at all is the honest gap.
if [ "$found" -lt "$LIMIT" ]; then
  for f in "$root"/docs/flows/*.md; do
    [ -f "$f" ] || continue
    case "${f##*/}" in _*|README.md|readme.md) continue ;; esac   # indexes are not flows
    grep -q '^\- \[E\]' "$f" 2>/dev/null && continue
    # ...and a page whose tests are ALL judgment-only is NOT a gap either. The comment above has
    # always said so; the code only ever checked for [E], so it could not tell "no tests at all"
    # (an honest gap) from "someone decided these are judgment" (a call already made). Found by
    # reviewing the FIRST branch burn-down ever generated: it proposed writing a test for
    # improve-the-design.md, all four of whose tests are `[S] … judgment 👁`. Building it would have
    # argued with a recorded decision — which is precisely what this rank promises not to do.
    grep -q '^\- \[S\]' "$f" 2>/dev/null && continue
    emit 4 gap "flow '${f##*/}' documents behaviour with no automated test referenced"
    [ "$found" -lt "$LIMIT" ] || break
  done
fi

# 5 — A COMPONENT THAT KEEPS FAILING (R94 ledger). Ranked here deliberately: the owner asked for
# small work first, escalating as it is exhausted, and a rebuild is the LARGEST recorded-signal
# work there is — so it sits after every cleanup and before invention. The signal is objective and
# already computed: a file implicated in repeated FAILURES, never a self-assessed "complexity".
# That distinction is the whole reason this is a ladder of PROVENANCE rather than of size — a
# complexity dial was asked for and rejected (contract-guard.sh) because the agent would be scoring
# its own work, unauditably. Cheap by construction: one small append-only file, tail-bounded (R81).
if [ "$found" -lt "$LIMIT" ]; then
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    emit 5 rework "$line has failed repeatedly — a bounded rebuild beats another patch"
    [ "$found" -lt "$LIMIT" ] || break
  done < <("$(dirname "$0")/rework.sh" report 2>/dev/null \
             | sed -n 's/^  ⟳ \([^ ]*\) implicated.*/\1/p')
fi

# 6 — NOTHING RECORDED REMAINS. Say so explicitly rather than inventing quietly. A caller that
# treats rank 6 like ranks 1-5 has defeated the entire design, so it is labelled, not disguised.
if [ "$found" -eq 0 ]; then
  emit 6 invent "no recorded signal remains — any work from here is INVENTED and must be treated as a proposal, not a task"
fi
exit 0
