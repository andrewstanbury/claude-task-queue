#!/usr/bin/env bash
# rework.sh — the REWORK LEDGER (R94). Records work that had to be done twice, and surfaces the
# count so it cannot be narrated away.
#
# The owner's complaint that produced this: "Claude seems to be making more and more obvious
# mistakes requiring rework then telling me about how it caught the mistakes." Reporting a caught
# mistake as an apparatus win reframes a defect rate as a success. A number cannot be spun.
#
# It counts FAILURE events, never touch counts — measured, not assumed: a file-churn metric on this
# repo ranked version manifests, the queue and LESSONS at the top, i.e. pure ceremony. The event
# that matters most is `owner-supplied`: the owner having to identify the fix is the most expensive
# defect this product has, because it is exactly what they are paying not to do.
#
#   rework.sh record <label> [file...]   append an event (labels: owner-supplied · gate-fail ·
#                                        ci-red · hole — free text, so a project can add its own)
#   rework.sh record rebuilt <path>      the rebuild HAPPENED — zeroes that path's prior failures
#   rework.sh report [days]              counts by label, and any file at the rebuild threshold
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

root="$(companion_root "${REWORK_ROOT:-$PWD}")"
f="$(companion_rework_file "$root")"
THRESH="${COMPANION_REBUILD_THRESHOLD:-3}"

# IS THIS A DATA DOCUMENT? (#115, owner-decided 2026-08-16.) `/companion:redesign` performs a
# CONTRACT-PRESERVING REBUILD, which is a meaningful thing to do to code or to prose and a
# meaningless — or actively wrong — thing to do to structured data. The ledger was recommending a
# rebuild of `marketplace.json` and `plugin.json` (version manifests: there is nothing to redesign)
# and of `docs/requirements.yaml`, which is THE CONTRACT and therefore the thing a rebuild must
# PRESERVE. They climb the list purely by being touched during every ship.
#
# DETECTED STRUCTURALLY, never by an extension allowlist (R9): jq settles JSON exactly, and for
# YAML-shaped documents the test is the proportion of substantive lines that are `key:` or `- `
# rows. MEASURED on this repo rather than guessed — requirements.yaml 59%, needs.yaml 50%,
# marketplace.json 58%, against STEERING.md 8%, mcp-server/index.js 8% and every shell file 0%.
# A 35% cut sits in the middle of a very wide gap.
#
# NOTE what stays a candidate: STEERING.md is prose, not data, and rebuilding it is a real option
# the ledger has recommended before (R55). The rule is "not structured data", not "not prose".
# Cost is bounded: one grep per file already over the threshold, and this list is short by
# construction — it does not grow with the store (R81).
_rw_is_data() {  # $1 path -> 0 when the file is a structured-data document
  [ -f "$1" ] || return 1
  jq empty "$1" >/dev/null 2>&1 && return 0
  local tot rows
  tot="$(grep -cvE '^[[:space:]]*(#|$)' "$1" 2>/dev/null || printf 0)"
  case "$tot" in ''|*[!0-9]*) return 1 ;; esac
  [ "$tot" -gt 0 ] || return 1
  rows="$(grep -cE '^[[:space:]]*(-[[:space:]]|[A-Za-z0-9_."'"'"'-]+:([[:space:]]|$))' "$1" 2>/dev/null || printf 0)"
  case "$rows" in ''|*[!0-9]*) return 1 ;; esac
  [ "$(( rows * 100 / tot ))" -ge "${COMPANION_DATA_DOC_PCT:-35}" ]
}

case "${1:-report}" in
  record) shift; [ "$#" -ge 1 ] || { echo "rework.sh: record needs a label" >&2; exit 2; }
    lbl="$1"; shift
    if [ "$#" -eq 0 ]; then companion_rework_record "$root" "$lbl" "-"
    else companion_rework_record "$root" "$lbl" "$@"; fi
    echo "rework: recorded $lbl" ;;
  report)
    # Read the repo ledger AND any legacy one, so events recorded before the move still count.
    leg="$(companion_rework_legacy "$root")"
    if [ ! -f "$f" ] && [ ! -f "$leg" ]; then echo "rework: none recorded"; exit 0; fi
    days="${2:-14}"; case "$days" in ''|*[!0-9]*) days=14 ;; esac
    cut=$(( $(date +%s 2>/dev/null || echo 0) - days*86400 ))
    # tail keeps the work bounded as the ledger grows (R81)
    recent="$(cat "$leg" "$f" 2>/dev/null | tail -n 500 | awk -v c="$cut" '$1 >= c')"
    [ -n "$recent" ] || { echo "rework: none in the last ${days}d"; exit 0; }
    echo "rework in the last ${days}d:"
    # Count EVENTS, not rows. One `record` writes a row per implicated file, so tallying rows
    # reported ONE red CI across eleven files as "11 ci-red" — an inflated defect rate is as
    # dishonest as a hidden one, and this metric exists precisely to be trusted. A single event
    # shares one timestamp+label, so the distinct pairs are the events.
    printf '%s\n' "$recent" | awk '$2 != "rebuilt" {print $1" "$2}' | sort -u | awk '{print $2}' \
      | sort | uniq -c | sort -rn | sed 's/^/  /'
    # A file implicated in repeated FAILURES is a rebuild candidate — a file merely touched often
    # is just work, which is why this counts events and not commits.
    #
    # EXCEPT THIS LEDGER'S OWN STORAGE. `record` writes a row per implicated file, and the ledger
    # file is itself touched by the work being recorded, so it accumulates counts and crossed the
    # threshold — the tool then proposed "a bounded rebuild" OF ITS OWN BOOKKEEPING (found by audit
    # 2026-08-16 at 3 failures). That is the third self-referential defect of the same day, after
    # candidates rank 3 feeding on its own documentation and rank 1 offering the model's own
    # unreviewed park: a tool must never propose work sourced from its own record of the work.
    # Matched on BASENAME, because the ledger is addressed by several paths (repo state, the legacy
    # home store, and REWORK_ROOT in tests) and a path compare would miss all but one.
    _rw_self="$(basename "$f")"
    # A COMPLETED REBUILD RETIRES ITS OWN RECOMMENDATION (#116, owner-decided 2026-08-16). Before
    # this the list counted every failure ever recorded against a path, so it kept proposing a
    # rebuild for work already done — lib/companion.sh and the test monolith were both still listed
    # an hour after being decomposed and split. A recommendation that cannot be satisfied is noise,
    # and this list feeds burn-down rank 5, so the noise can become generated work.
    # Append-only: `rebuilt` is an ordinary row, so history stays auditable and nothing is deleted.
    # Failures recorded AFTER a rebuild count again — a rebuild that did not hold says so itself.
    # Ordering uses the ROW INDEX as a tiebreak, not the timestamp alone. `date +%s` is whole
    # seconds, so a rebuild and the failures that follow it routinely share one — with a strict
    # `ts > rebuilt` test those failures were silently dropped and a rebuild that did NOT hold
    # stayed invisible. The ledger is append-only, so position IS the order.
    printf '%s\n' "$recent" | awk '$3 != "-" {
            if ($2 == "rebuilt") { if ($1 > reb[$3] || ($1 == reb[$3] && NR > rebi[$3]) || !($3 in reb)) { reb[$3] = $1; rebi[$3] = NR } ; next }
            n++; ts[n] = $1; idx[n] = NR; path[n] = $3
          }
          END { for (i = 1; i <= n; i++) {
                  p = path[i]
                  if (!(p in reb) || ts[i] > reb[p] || (ts[i] == reb[p] && idx[i] > rebi[p])) c[p]++
                }
                for (p in c) printf "%d %s\n", c[p], p }' \
      | sort -rn \
      | awk -v t="$THRESH" -v self="$_rw_self" '$1 >= t {
            n=split($2, seg, "/"); if (seg[n] == self) next
            print $1" "$2 }' \
      | while read -r _rw_n _rw_p; do
          _rw_is_data "$root/$_rw_p" && continue
          printf '  ⟳ %s implicated in %d failures — a bounded rebuild (/companion:redesign) beats another patch\n' "$_rw_p" "$_rw_n"
        done
    ;;
  *) echo "usage: rework.sh [record <label|rebuilt> [file...] | report [days]]" >&2; exit 2 ;;
esac
