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
    printf '%s\n' "$recent" | awk '{print $1" "$2}' | sort -u | awk '{print $2}' \
      | sort | uniq -c | sort -rn | sed 's/^/  /'
    # A file implicated in repeated FAILURES is a rebuild candidate — a file merely touched often
    # is just work, which is why this counts events and not commits.
    printf '%s\n' "$recent" | awk '$3 != "-" {print $3}' | sort | uniq -c | sort -rn \
      | awk -v t="$THRESH" '$1 >= t {printf "  ⟳ %s implicated in %d failures — a bounded rebuild (/companion:redesign) beats another patch\n", $2, $1}'
    ;;
  *) echo "usage: rework.sh [record <label> [file...] | report [days]]" >&2; exit 2 ;;
esac
