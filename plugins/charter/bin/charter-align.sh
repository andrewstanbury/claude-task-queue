#!/usr/bin/env bash
# charter-align — deterministic facts for the /charter:align alignment check.
#
# The on-demand counterpart to alignment-aware capture (task-queue 0.16.0): it
# surfaces the project's recorded DIRECTION — decisions/ADRs + roadmap/backlog —
# plus what recently landed, so the model can reconcile open/proposed work
# against them and flag drift or decision-contradictions BEFORE the work is done.
#
# Read-only, like the rest of charter: it prints what it finds; the model judges.
# The slash command (commands/align.md) runs this, then does the reconciliation.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/charter.sh
. "$PLUGIN_DIR/lib/charter.sh"

root="$(charter_root_for_cwd "$PWD")"
dpath="$(charter_decisions_path "$root" 2>/dev/null || true)"
rpath="$(charter_roadmap_path "$root" 2>/dev/null || true)"

printf '[charter:align] alignment anchors for: %s\n\n' "$root"

if [ -n "$dpath" ]; then
  printf 'Decisions / ADRs (the alignment anchor — do not reverse or contradict without consulting):\n  %s\n\n' "$dpath"
else
  printf 'Decisions / ADRs: none recorded (no DECISIONS.md or docs/adr/). Nothing to check work against — capturing the evident decisions would close this gap.\n\n'
fi

if [ -n "$rpath" ]; then
  printf 'Roadmap / backlog (the recorded direction — open work should advance it, not drift):\n  %s\n\n' "$rpath"
else
  printf 'Roadmap / backlog: none recorded (no docs/ROADMAP.md). No documented Now/Next to weigh work against.\n\n'
fi

recent="$(charter_recent_commits "$root" 8 2>/dev/null || true)"
if [ -n "$recent" ]; then
  printf 'Recently landed (newest first — reconcile: which of these the docs should now mark done):\n'
  printf '%s\n' "$recent" | while IFS= read -r line; do
    [ -n "$line" ] && printf '  • %s\n' "$line"
  done
  printf '\n'
fi

if [ -z "$dpath" ] && [ -z "$rpath" ]; then
  printf 'No recorded direction to align against. charter nudges to generate these docs at SessionStart;\nuntil they exist, alignment can only be judged against the conversation and the code.\n'
fi
