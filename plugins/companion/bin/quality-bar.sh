#!/usr/bin/env bash
# quality-bar.sh — does every stated quality attribute say HOW it will be checked? (R118)
#
#   quality-bar.sh [check]          report; exit 0 always (advisory, see below)
#   quality-bar.sh check --strict   exit 1 when there are findings (for a project that wants teeth)
#
# THE GAP. This project already had the strong half: `docs/flows/_quality-bar.md` is where quality
# attributes live, `requirements.yaml` pairs every BEHAVIOUR with the tests that verify it, and
# `dev/trace.sh` gates both directions. What nothing did was ASK — so a repo can run for months
# with an empty bar, or with attributes that sound rigorous and name no check at all, and nothing
# notices until a publish is the thing that surfaces it. That is the "find out way too late"
# scenario stated as the reason for this feature.
#
# WHAT IT LOOKS FOR. An attribute line under `floor` must name its validation with `→ validated by:`.
# The check is that the pairing EXISTS, not that it is true — a floor, not a proof, the same honesty
# `command-lint.sh`'s portability check states about itself. That distinction is the whole design:
# most quality attributes in a real project are checked by JUDGMENT, not by a gate, and a tool that
# demanded a mechanical check for each would produce fake gates rather than honest ones. So
# `→ validated by: reviewed at ship — <the question asked>` is a first-class, valid answer.
#
# WHY IT WARNS RATHER THAN REFUSES, stated plainly because the owner picked "refuse-or-warn".
# A hard refusal would fire in every repo that has no bar — i.e. every project that installs this
# plugin and has not yet been asked — turning a quality feature into a broken ship on day one
# (R68: never break the action that triggered you). So: NO FILE means silent, because the plugin is
# not managing a bar there and inventing one is not its call. A file that EXISTS is a repo that opted
# in, and there the findings are loud and specific at the ship boundary. `--strict` is the opt-in
# for a project that wants the ship to actually stop.
set -uo pipefail
SELF="$0"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${QUALITY_BAR_ROOT:-$PWD}")"
strict=0
case "${1:-check}" in check|"") shift 2>/dev/null || true ;; *) : ;; esac
for a in "$@"; do case "$a" in --strict) strict=1 ;; esac; done

bar="$root/docs/flows/_quality-bar.md"
# NO FILE = NOT OPTED IN = SILENT. Deliberately not "missing bar is a finding": that would make
# every stranger's repo fail from the moment the plugin lands, which is the opposite of useful.
[ -f "$bar" ] || exit 0

findings=0
# Attribute lines are the `- ` bullets in the floor block. Structural, not a keyword list (R9):
# anything between the `floor` heading and the next blank-line-delimited non-bullet section.
attrs="$(awk '
  /^floor/            { inblock=1; next }
  inblock && /^- /    { print; next }
  inblock && /^[a-zA-Z]/ && !/^- / { inblock=0 }
' "$bar")"

if [ -z "$attrs" ]; then
  printf 'quality-bar: the bar at %s names NO attributes.\n' "${bar#"$root"/}"
  printf '  Nothing states what would force a redesign if found late — accessibility, security,\n'
  printf '  performance, data handling. That is the gap this check exists for; run /companion:setup\n'
  printf '  to be asked, or write them in by hand.\n'
  findings=1
else
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case "$line" in
      *"validated by:"*) : ;;
      *) if [ "$findings" -eq 0 ]; then
           printf 'quality-bar: attribute(s) state a standard but name no way to check it:\n'
         fi
         # Show the head of the line only — these are long, and the ID is what identifies it.
         printf '  ✗ %.78s\n' "${line#- }"
         findings=$((findings + 1)) ;;
    esac
  done <<< "$attrs"
  if [ "$findings" -gt 0 ]; then
    # shellcheck disable=SC2016  # backticks are literal here — they quote the marker in the prose
    printf '  Pair each with `→ validated by: <gate, test, or the review question asked>`.\n'
    printf '  "reviewed at ship — <question>" is a VALID answer: most quality attributes are\n'
    printf '  judgment, and a fake mechanical gate is worse than an honest human one.\n'
  fi
fi

[ "$findings" -eq 0 ] && exit 0
[ "$strict" -eq 1 ] && exit 1
exit 0
