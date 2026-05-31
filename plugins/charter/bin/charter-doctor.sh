#!/usr/bin/env bash
# charter-doctor — manual, read-only health check for the charter plugin.
#
# Reports whether the current project documents its quality attributes and has a
# Claude manual, and shows the activity-log tail. Run it to see what charter sees.

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
printf 'charter-doctor — project: %s\n\n' "$root"

printf 'Quality attributes\n'
if [ "$(charter_qa_status "$root")" = "documented" ]; then
  printf '  [OK]   quality attributes are documented\n'
else
  printf '  [TODO] not documented — charter will nudge to capture them before substantive changes\n'
  printf '         (QUALITY.md, docs/QUALITY.md, an ADR, or a "Quality Attributes" section of CLAUDE.md)\n'
fi

printf '\nRoadmap / backlog\n'
rpath="$(charter_roadmap_path "$root")"
if [ -n "$rpath" ]; then
  printf '  [OK]   %s — the cross-session, cross-engineer backlog\n' "$rpath"
else
  printf '  [TODO] no roadmap/backlog file — charter will nudge to generate docs/ROADMAP.md\n'
  printf '         from git history + code, so work resumes across sessions and engineers\n'
fi

printf '\nProject map\n'
mpath="$(charter_map_path "$root")"
if [ -n "$mpath" ]; then
  printf '  [OK]   %s — sessions orient from the map instead of re-scanning the tree\n' "$mpath"
else
  printf '  [TODO] no project map — charter will nudge to generate docs/MAP.md\n'
  printf '         (a compact file->responsibility index) so loading the project stays cheap\n'
fi

printf '\nProject manual\n'
if [ -f "$root/CLAUDE.md" ] || [ -f "$root/AGENTS.md" ]; then
  printf '  [OK]   a Claude manual exists (CLAUDE.md / AGENTS.md)\n'
else
  printf '  [TODO] no CLAUDE.md / AGENTS.md — future sessions will re-explore from scratch\n'
fi

printf '\nActivity log\n'
logf="$(charter_log_file)"
if [ -f "$logf" ]; then
  printf '  log: %s\n' "$logf"
  tail -n 15 "$logf" 2>/dev/null | sed 's/^/    /'
else
  printf '  (no log yet at %s)\n' "$logf"
fi
