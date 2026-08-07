#!/usr/bin/env bash
# stale.sh — WHICH REQUIREMENTS HAS THE WORK MOVED OUT FROM UNDER? Advisory input to
# `/companion:advise` and `/companion:redesign`; never a gate, never a hook. Always exits 0.
#
# THREE TIERS, EACH ON THE ONLY AXIS IT ACTUALLY HAS (R97):
#
#   LEVEL 0 — needs.yaml            NEVER expires. Not read here, has no `affirmed:`. Seven needs,
#                                   capped at ten by their own header, are the definition of
#                                   "useful"; an agent that re-opens them has no falsifiable
#                                   standard left.
#   LEVEL 1, test-verified          CONTACT, not calendar. Drift = commits that touched this
#                                   requirement's OWN verifying test blocks since it was last
#                                   affirmed. Stale at `drift >= threshold`.
#   LEVEL 1, `judgment:`-shaped     CALENDAR, because there is nothing else. These name no test by
#                                   construction, so there is no contact to measure — age is the
#                                   only signal available. Stale at `age >= ttl`.
#
# Why contact rather than a TTL wherever contact CAN be measured: a requirement does not go stale
# because time passed, it goes stale because the system underneath it moved while nobody re-asked
# whether it is still wanted. R6 ("self-contained") could sit untouched for a year and still be
# exactly true; R96 went stale in DAYS because a state move broke it. A pure TTL nags about the
# first and is silent about the second — wrong in both directions.
#
# BACKOFF (owner, 2026-08-05). Surviving a challenge is evidence. Each re-affirmation multiplies
# the threshold, so a requirement that keeps being confirmed goes quiet instead of asking forever,
# and one that keeps being reversed stays loud. The multiplier is the tier's, not a global: x2 for
# drift (cheap to re-check — the tests are right there), x3 for calendar (re-litigating a
# judgement call is expensive and its answer is stable). Exponent is capped so nothing becomes
# permanently unchallengeable.
#
# It RANKS; it does not judge, and it never edits the contract. Which stale requirements matter to
# the work in hand is recognition, and recognition is the model's job (R9) — this reports, the
# consumer picks. Stale means EARNS A FRESH LOOK, never "reverse it".
#
# GENERIC (R1/R9). This ships, so it runs on other people's projects: it knows nothing about bats,
# and has no allowlist of test directories, filenames or extensions. A requirement's `verified_by`
# names a test by its TITLE, and a test's title is a literal string in whatever file defines it —
# so the file is found by searching the repo for that literal, which is true in every language.
# Recognition stays the model's job; this only detects structure.
#
#   stale.sh [repo]          full report: stale first, then steady
#   stale.sh [repo] --quiet  only what is stale
#
# Reads the same contract the rest of the companion enforces (R86): `docs/requirements.yaml`.
set -uo pipefail
# BYTE-WISE. Every comparison below is an identity test between a test title in requirements.yaml
# and one in a .bats file — the same reason trace.sh pins this. A UTF-8 collation that judges two
# byte-distinct titles equal would silently bill one requirement's drift to another.
export LC_ALL=C

# ── TUNABLES ───────────────────────────────────────────────────────────────────────────────────
# Chosen, not measured — there is no history of challenge outcomes to fit them to yet, and saying
# so is cheaper than a fake derivation. They are here, named, so the first time the report is
# plainly too loud or too quiet the fix is one number.
DRIFT_BASE=3          # commits to a requirement's own test blocks before it earns a fresh look
DRIFT_MULT=2          # doubled per re-affirmation
DRIFT_CAP=5           # ...up to x32; past that it is effectively settled, but still reportable
TTL_BASE=180          # days before a judgement-shaped requirement earns a fresh look
TTL_MULT=3            # tripled per re-affirmation
TTL_CAP=2             # ...up to ~4.4 years

quiet=0; repo=
for a in "$@"; do
  case "$a" in
    --quiet) quiet=1 ;;
    -h|--help) sed -n '2,40p' "$0"; exit 0 ;;
    -*) echo "stale.sh: unknown option: $a" >&2; exit 2 ;;
    *) repo="$a" ;;
  esac
done
cd "${repo:-.}" 2>/dev/null || { echo "  stale: cannot enter ${repo:-.}"; exit 0; }
cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)" || exit 0

REQ=docs/requirements.yaml
[ -r "$REQ" ] || { echo "  stale: $REQ unreadable — nothing to report"; exit 0; }
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "  stale: not a git repository — drift is measured from history, so there is nothing to measure"
  exit 0
fi
tmp=$(mktemp -d) || exit 0
trap 'rm -rf "$tmp"' EXIT INT TERM
today=$(date +%Y-%m-%d)

# days_between YYYY-MM-DD YYYY-MM-DD — whole days, portably. `date -d` is GNU and `date -jf` is
# BSD, so neither can be used: this is the civil-day count both agree on, done in awk.
days_between() { awk -v a="$1" -v b="$2" 'BEGIN{
  split(a, x, "-"); split(b, y, "-")
  print jd(y[1], y[2], y[3]) - jd(x[1], x[2], x[3])
}
function jd(Y, M, D,   A, YY, MM) {          # days since an arbitrary epoch (Fliegel-Van Flandern)
  A = int((14 - M) / 12); YY = Y + 4800 - A; MM = M + 12 * A - 3
  return D + int((153 * MM + 2) / 5) + 365 * YY + int(YY / 4) - int(YY / 100) + int(YY / 400) - 32045
}'; }

# ── 1. THE CONTRACT ────────────────────────────────────────────────────────────────────────────
# One row per (id, affirmed, affirmations, kind, payload). kind=test → payload is a claimed @test
# title; kind=judgment → validated by a human, no case to measure contact against; kind=untested →
# neither (trace.sh fails on that, so it means this ran on a red tree).
#
# A MISSING affirmed: is written "-", never empty, and that is load-bearing. TAB is an IFS
# WHITESPACE character, so bash `read` collapses a RUN of tabs into one delimiter — an empty field
# does not survive the round trip. An unstamped requirement therefore emitted `id\t\t\ttest\t…`,
# which read back with every field shifted left, so `kind` landed on the payload and the entry was
# reported as UNTESTED instead of as the missing date it actually was. Silent, and wrong in the one
# case the field exists to catch.
awk '
  function flush() {
    if (id == "") return
    if (ntests == 0) print id "\t" aff "\t" nn "\t" (isjudg ? "judgment" : "untested") "\t-"
    id = ""; aff = "-"; nn = 0; isjudg = 0; ntests = 0
  }
  BEGIN             { aff = "-"; nn = 0 }
  /^- id: /         { flush(); id = $0; sub(/^- id: /, "", id); sub(/[ \t\r]+$/, "", id); next }
  /^  affirmed: /   { aff = $0; sub(/^  affirmed: /, "", aff); sub(/[ \t\r]+$/, "", aff); next }
  /^  affirmations: / { t = $0; sub(/^  affirmations: /, "", t); nn = t + 0; next }
  /^  judgment:/    { isjudg = 1; next }
  /^[ \t]+- "/ {
    if (id == "") next
    t = $0; sub(/^[^"]*"/, "", t); sub(/"[ \t\r]*$/, "", t)
    print id "\t" aff "\t" nn "\ttest\t" t; ntests++; next
  }
  END { flush() }
' "$REQ" > "$tmp/claims"
[ -s "$tmp/claims" ] || { echo "  stale: no requirements parsed from $REQ"; exit 0; }

# ── 2. WHERE DOES EACH NAMED TEST LIVE? ────────────────────────────────────────────────────────
# One fixed-string search for every claimed title at once. A title is a literal in the file that
# defines it whatever the runner is, so this needs no test-path convention — the contract file
# itself is excluded, or every title would "live" in the contract that names it.
cut -f5 "$tmp/claims" | grep -v '^-$' | sort -u > "$tmp/titles"
if [ -s "$tmp/titles" ]; then
  git grep -n -F -f "$tmp/titles" -- . ":(exclude)$REQ" 2>/dev/null > "$tmp/raw" || : > "$tmp/raw"
else
  : > "$tmp/raw"
fi

# title -> the ONE file that defines it, and the line it starts on. A title can also appear in a
# changelog or an ADR, so the defining file is taken to be the one holding the MOST claimed titles:
# that is the test file in any language, and it needs no allowlist to say so.
awk -F'\n' '
  NR == FNR { titles[++nt] = $0; next }
  {
    p1 = index($0, ":"); if (p1 == 0) next
    f = substr($0, 1, p1 - 1); rest = substr($0, p1 + 1)
    p2 = index(rest, ":"); if (p2 == 0) next
    ln = substr(rest, 1, p2 - 1) + 0; body = substr(rest, p2 + 1)
    if (ln == 0) next
    best = ""                                   # longest containing title wins: one title can be a
    for (i = 1; i <= nt; i++)                   # suffix of another, and the short one must not steal it
      if (index(body, titles[i]) > 0 && length(titles[i]) > length(best)) best = titles[i]
    if (best == "") next
    if (!((best SUBSEP f) in at)) { at[best, f] = ln; hits[f]++ }
    else if (ln < at[best, f]) at[best, f] = ln
  }
  END {
    for (k in at) {
      split(k, part, SUBSEP); t = part[1]; f = part[2]
      if (!(t in bestf) || hits[f] > hits[bestf[t]]) { bestf[t] = f; bestl[t] = at[k] }
    }
    for (t in bestf) print t "\t" bestf[t] "\t" bestl[t]
  }
' "$tmp/titles" "$tmp/raw" > "$tmp/hits"

# A block runs from its title to the line before the NEXT claimed title in the same file, or to the
# end of the file. That is the range `git log -L` follows back through history, and it is what makes
# the signal per-TEST rather than per-file — the whole point, since a suite is usually few files.
cut -f2 "$tmp/hits" | sort -u > "$tmp/files"
: > "$tmp/flen"
while IFS= read -r f; do
  [ -n "$f" ] || continue
  printf '%s\t%s\n' "$f" "$(wc -l < "$f" 2>/dev/null | tr -d " " || echo 0)" >> "$tmp/flen"
done < "$tmp/files"
sort -t"$(printf '\t')" -k2,2 -k3,3n "$tmp/hits" > "$tmp/hits.sorted"
awk -F'\t' '
  NR == FNR { len[$1] = $2 + 0; next }
  { t[NR] = $1; f[NR] = $2; s[NR] = $3 + 0; n = NR }
  END {
    for (i = 1; i <= n; i++) {
      if (i < n && f[i + 1] == f[i]) e = s[i + 1] - 1; else e = len[f[i]]
      if (e < s[i]) e = s[i]
      print t[i] "\t" f[i] "\t" s[i] "\t" e
    }
  }
' "$tmp/flen" "$tmp/hits.sorted" > "$tmp/blocks"

# ── 3. THE CHEAP PRE-FILTER ────────────────────────────────────────────────────────────────────
# `git log -L` costs ~0.14s per block and a real contract has hundreds of claims. One history pass
# first: a file with no commits since the oldest affirmation cannot contribute drift to anything.
oldest=$(cut -f2 "$tmp/claims" | grep -E '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' | sort | head -1)
[ -n "$oldest" ] || oldest=1970-01-01
if [ -s "$tmp/files" ]; then
  # shellcheck disable=SC2046  # deliberate word-splitting: one pathspec per discovered file
  git log --since="$oldest" --name-only --format= -- $(cat "$tmp/files") 2>/dev/null | sort -u > "$tmp/touched"
else
  : > "$tmp/touched"
fi

# ── 4. DRIFT ───────────────────────────────────────────────────────────────────────────────────
# Commits that changed THIS test's lines since the requirement was affirmed. `-s` suppresses the
# diff so each commit is one date line. Full history is walked and dates compared here rather than
# passing --since to git: a date filter on a line-log can truncate the rename/move tracking that
# makes -L worth using in the first place, and the newest date is wanted regardless.
# range_of TITLE -> "-L<start>,<end>:<file>", empty when the test's file has not moved at all.
range_of() {
  local blk file s e
  # EXACT field match, not a substring grep: one test title can be a suffix of another, and a
  # substring hit would silently bill one requirement's drift to a different requirement.
  blk=$(awk -F'\t' -v t="$1" '$1 == t { print; exit }' "$tmp/blocks" 2>/dev/null)
  [ -n "$blk" ] || return 0                             # trace.sh owns "that test does not exist"
  file=$(printf '%s' "$blk" | cut -f2); s=$(printf '%s' "$blk" | cut -f3); e=$(printf '%s' "$blk" | cut -f4)
  grep -qxF "$file" "$tmp/touched" 2>/dev/null || return 0
  printf -- '-L%s,%s:%s' "$s" "$e" "$file"
}

pow() { local b=$1 e=$2 r=1; while [ "$e" -gt 0 ]; do r=$((r * b)); e=$((e - 1)); done; echo "$r"; }
capped() { if [ "$1" -gt "$2" ]; then echo "$2"; else echo "$1"; fi; }

: > "$tmp/rows"
# `nranges` is counted by hand and every expansion of `ranges` is guarded: in bash 3.2 — which is
# what the macOS lane runs — `${#arr[@]}` and `"${arr[@]}"` on an EMPTY array are "unbound
# variable" under `set -u`, so the plain forms would abort the script on the first requirement
# whose tests all sat in unmoved files.
prev_id=; last_seen=-; kind=; aff=; nn=0; ranges=(); nranges=0
emit() {
  [ -n "$prev_id" ] || return 0
  local thr age over sum=0 dates
  # ONE git call per REQUIREMENT, every one of its test blocks passed as its own -L range. Not one
  # call per test: a single commit that touches three of a requirement's tests is ONE change to
  # that requirement, and per-test calls counted it three times. Also ~3x faster.
  if [ "$kind" = test ] && [ "$nranges" -gt 0 ]; then
    dates=$(git log ${ranges[@]+"${ranges[@]}"} -s --format='%ad' --date=short 2>/dev/null)
    if [ -n "$dates" ]; then
      sum=$(printf '%s\n' "$dates" | awk -v a="$aff" '$1 > a' | grep -c .)
      last_seen=$(printf '%s\n' "$dates" | sort -r | head -1)
    fi
  fi
  case "$kind" in
    test)
      thr=$((DRIFT_BASE * $(pow "$DRIFT_MULT" "$(capped "$nn" "$DRIFT_CAP")")))
      if [ "$aff" = "-" ]; then over=NODATE; else over=$([ "$sum" -ge "$thr" ] && echo STALE || echo ok); fi  # sc2015-ok
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$over" "$sum" "$thr" "$prev_id" "$aff" "$nn" "$last_seen" drift >> "$tmp/rows" ;;
    judgment)
      thr=$((TTL_BASE * $(pow "$TTL_MULT" "$(capped "$nn" "$TTL_CAP")")))
      if [ "$aff" = "-" ]; then over=NODATE; age=0; else
        age=$(days_between "$aff" "$today"); case "$age" in ''|*[!0-9]*) age=0 ;; esac
        over=$([ "$age" -ge "$thr" ] && echo STALE || echo ok)                                     # sc2015-ok
      fi
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$over" "$age" "$thr" "$prev_id" "$aff" "$nn" "-" ttl >> "$tmp/rows" ;;
    *)
      printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' UNTESTED 0 0 "$prev_id" "$aff" "$nn" "-" none >> "$tmp/rows" ;;
  esac
}
while IFS="$(printf '\t')" read -r id a n k payload; do
  if [ "$id" != "$prev_id" ]; then emit; prev_id="$id"; last_seen=-; kind="$k"; aff="$a"; nn="${n:-0}"; ranges=(); nranges=0; fi
  [ "$k" = test ] || { kind="$k"; continue; }
  kind="test"
  [ "$a" != "-" ] || continue
  r=$(range_of "$payload")
  [ -z "$r" ] || { ranges+=("$r"); nranges=$((nranges + 1)); }
done < "$tmp/claims"
emit

# ── 5. REPORT ──────────────────────────────────────────────────────────────────────────────────
# The requirement's own one-liner is printed so the reader does not have to open the contract to
# know what is being put up for challenge.
text_of() { awk -v id="$1" '
    /^- id: /{ keep = ($3 == id); next }
    keep && /^  requirement: >/ { getline; sub(/^[ \t]+/, ""); sub(/[ \t\r]+$/, ""); print; exit }
  ' "$REQ"; }

stale=0; total=0; untested=0
while IFS="$(printf '\t')" read -r over score thr id aff n last axis; do
  total=$((total + 1))
  line=
  case "$over/$axis" in
    STALE/drift) stale=$((stale + 1))
      line=$(printf '  %-7s STALE  drift %s/%s  affirmed %s (x%s)  last moved %s  %s' "$id" "$score" "$thr" "$aff" "$n" "$last" "$(text_of "$id")") ;;
    STALE/ttl) stale=$((stale + 1))
      line=$(printf '  %-7s STALE  age %sd/%sd  affirmed %s (x%s)  judgement-shaped  %s' "$id" "$score" "$thr" "$aff" "$n" "$(text_of "$id")") ;;
    NODATE/*) stale=$((stale + 1))
      line=$(printf '  %-7s NO affirmed: DATE  %s' "$id" "$(text_of "$id")") ;;
    UNTESTED/*) untested=$((untested + 1))
      line=$(printf '  %-7s UNTESTED  names no test and is not marked judgment:  %s' "$id" "$(text_of "$id")") ;;
    ok/drift) [ "$quiet" = 1 ] || line=$(printf '  %-7s ok     drift %s/%s  affirmed %s (x%s)' "$id" "$score" "$thr" "$aff" "$n") ;;
    ok/ttl)   [ "$quiet" = 1 ] || line=$(printf '  %-7s ok     age %sd/%sd  affirmed %s (x%s)' "$id" "$score" "$thr" "$aff" "$n") ;;
  esac
  [ -z "$line" ] || printf '%s\n' "$line"
done < <(sort -t"$(printf '\t')" -k1,1 -k2,2nr "$tmp/rows")

echo
printf '  %s of %s requirements are stale' "$stale" "$total"
[ "$untested" = 0 ] || printf '; %s name no test at all' "$untested"
printf '.\n'
echo "  Stale = EARNS A FRESH LOOK, not \"reverse it\". Re-affirm (bump \`affirmed:\`, ++\`affirmations:\`)"
echo "  and the threshold multiplies — x$DRIFT_MULT per affirmation on drift, x$TTL_MULT on calendar — so what keeps"
echo "  surviving challenge goes quiet, and what keeps getting reversed stays loud."
exit 0
