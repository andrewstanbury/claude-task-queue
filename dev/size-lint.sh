#!/usr/bin/env bash
# size-lint.sh — the FILE SIZE gate (files <= 300 lines), extracted from check.sh 2026-08-16 for the
# reason doc-lint.sh / command-lint.sh / hook-budget.sh were: inline in check.sh the SUITE cannot
# reach it (check.sh runs bats, so a test invoking it recurses), and a gate the suite cannot run is
# a gate whose own behaviour is never verified. Extracting it also took check.sh back under its own
# warning threshold, which is the gate applying to itself rather than being exempt from itself.
#
#   size-lint.sh [file...]     no args = the shipped scripts + check.sh
#
# TWO THRESHOLDS, and only one of them fails.
#   > 300  FAIL — the decomposition trigger. Unchanged; it is the actual rule.
#   >= 270 WARN — saturation, added after the 2026-08-16 audit. A single hard cliff is gameable in
#          the wrong direction: at exactly 300/300 the cheapest way to pass is to delete a COMMENT,
#          so the file stays the same size and loses its rationale instead. Measured, not supposed —
#          three separate comment-trims went into lib/companion.sh in one session while it sat at
#          the cap, and nobody noticed until the audit counted lines. A warning makes saturation
#          visible to whoever touches the file NEXT, which is when the information is worth having.
#          It must never fail the build: blocking otherwise-fine work on "this file is largish" is
#          how a gate gets switched off, and a disabled gate protects nothing.
set -uo pipefail
CAP="${CHECK_SIZE_CAP:-300}"
WARN_AT="${CHECK_SIZE_WARN:-270}"
rc=0

if [ "$#" -gt 0 ]; then files=("$@")
else files=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh plugins/*/bin/tq); fi

for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  n=$(wc -l < "$f" | tr -d ' ')
  case "$n" in ''|*[!0-9]*) continue ;; esac
  if [ "$n" -gt "$CAP" ]; then echo "  FAIL $f: $n > $CAP"; rc=1
  elif [ "$n" -ge "$WARN_AT" ]; then echo "  WARN $f: $n/$CAP — decompose before adding here"; fi
done
exit "$rc"
