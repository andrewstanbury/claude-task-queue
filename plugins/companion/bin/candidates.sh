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
#   1 parked   a ❓ park carrying `rec:` — the owner deferred THIS decision and a recommendation
#              is already written. Strongest signal in the repo: chosen, reasoned, not yet done.
#   2 roadmap  an unchecked `- [ ]` item in a ROADMAP — stated intent, explicitly not yet built.
#   3 todo     a TODO/FIXME/XXX in tracked source — a note-to-self left at the point of pain.
#   4 gap      a contract page documenting behaviour with NO automated test referenced.
#   5 invent   NOTHING recorded remains. Emitted only when 1-4 are empty, and marked so the build
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
         | sed -n 's/^  ◻ *//p' | grep '^❓' | grep -F 'rec:' | head -"$LIMIT")

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
  done < <(git -C "$root" grep -nIE '(TODO|FIXME|XXX)[: ]' -- . 2>/dev/null \
           | grep -vE '(^|/)(dev/tests|node_modules|vendor)/' \
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

# 5 — NOTHING RECORDED REMAINS. Say so explicitly rather than inventing quietly. A caller that
# treats rank 5 like ranks 1-4 has defeated the entire design, so it is labelled, not disguised.
if [ "$found" -eq 0 ]; then
  emit 5 invent "no recorded signal remains — any work from here is INVENTED and must be treated as a proposal, not a task"
fi
exit 0
