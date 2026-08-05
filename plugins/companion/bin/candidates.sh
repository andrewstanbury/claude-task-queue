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
LIMIT="${CANDIDATES_LIMIT:-5}"          # bounded: a long list is not more useful than a short one
found=0

emit() {  # $1 rank · $2 source · $3 text
  [ "$found" -lt "$LIMIT" ] || return 0
  # One line, framing characters stripped: this feeds a branch name and a commit message later.
  printf '%s|%s|%s\n' "$1" "$2" "$(printf '%s' "$3" | tr '\n\r|' '   ' | cut -c1-200)"
  found=$((found+1))
}

# 1 — PARKED DECISIONS carrying a recommendation. Read through the same store the queue owns.
while IFS= read -r line; do
  [ -n "$line" ] || continue
  emit 1 parked "${line###* }"
done < <(companion_open_tasks "$root" 2>/dev/null \
         | sed -n 's/^  ◻ *//p' | grep '^❓' | grep -F 'rec:' \
         | grep -vF 'decision:' | grep -vF 'decompose:' | head -"$LIMIT")

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
  done < <(git -C "$root" grep -nIE '(TODO|FIXME|XXX)[: ]' -- . ':!*.md' ':!*.markdown' ':!*.yaml' ':!*.yml' 2>/dev/null \
           | grep -vE '(^|/)(dev/tests|node_modules|vendor)/' \
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
