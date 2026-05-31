#!/usr/bin/env bash
# SessionStart hook — gate substantive work on documented quality attributes.
#
# If the project hasn't documented its quality attributes (perf, security, a11y,
# reliability, maintainability…), nudge the model to capture them FIRST — so
# changes can honor them. If they're documented, a brief honor-reminder on a
# fresh context, silent thereafter. Source-aware + read-only (never writes the
# project). The "gate" is a strong nudge, not a hard block (hooks can't block).

set -euo pipefail

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

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; src=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"
root="$(charter_root_for_cwd "$cwd")"
status="$(charter_qa_status "$root" 2>/dev/null || printf 'missing')"

case "$src" in compact|resume) lean=1 ;; *) lean=0 ;; esac

emit() { jq -cn --arg c "$1" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'; }

# Lean mode (compact/resume): a single QA re-anchor when missing, else silent.
# Token-light — the roadmap + orientation nudges are full-context only, since the
# model already oriented this session and can read those docs directly.
if [ "$lean" -eq 1 ]; then
  if [ "$status" = "missing" ]; then
    charter_log "session-start" "qa=missing src=${src:-?} mode=lean"
    emit "[charter] (reminder) document this project's quality attributes (perf, security, a11y, reliability, maintainability) before substantive changes."
  else
    charter_log "session-start" "qa=documented src=${src:-?} mode=lean"
  fi
  exit 0
fi

# Full context (startup/clear/unknown): QA gate + roadmap awareness + orientation.
if [ "$status" = "missing" ]; then
  qa="[charter] This project has no documented quality attributes. Before substantive changes, capture them — performance, security, accessibility, reliability, maintainability targets — in QUALITY.md (or a \"Quality Attributes\" section of CLAUDE.md). Changes should then honor them."
else
  qa="[charter] This project documents its quality attributes — honor them when changing code, and surface the relevant one when you touch related areas."
fi

# The roadmap/backlog file is the project's cross-session, cross-engineer record
# of what's next. Missing → instruct the model to generate it from the project
# (the hook stays read-only; the model authors the file). Present → consult +
# reconcile it against git history so it never drifts.
rstatus="$(charter_roadmap_status "$root" 2>/dev/null || printf 'missing')"
if [ "$rstatus" = "missing" ]; then
  roadmap="[charter] No committed roadmap/backlog file. Generate docs/ROADMAP.md as a Claude-facing backlog — a terse Now/Next/Later list plus a dated changelog — inferred from git history and the codebase (flag any assumptions for review), then commit it. It is how work is picked up, resumed, and coordinated across engineers on separate machines; git history is the shared audit trail."
else
  rpath="$(charter_roadmap_path "$root")"
  roadmap="[charter] $rpath is this project's backlog — read it for what's next, and reconcile it against recent git history before substantive changes (mark merged items done, append a dated changelog entry, flag drift). Keep it committed so other engineers resume from the same state."
fi

# Orientation = the project map (charter owns know-the-project). The map is the
# durable structural record, so the orientation line points at it rather than at
# a generic "record learnings" nudge — keeping SessionStart from growing. Missing
# → instruct the model to generate it from the codebase (hook detects, model
# authors). Present → consult it instead of re-scanning the tree, and keep it
# current. Full-context only; the lean path above stays silent on this.
mstatus="$(charter_map_status "$root" 2>/dev/null || printf 'missing')"
if [ "$mstatus" = "missing" ]; then
  orient="[charter] No project map. Generate docs/MAP.md — a compact file→responsibility index plus the key entry points — from the codebase, so future sessions (and other engineers) orient from the map instead of re-scanning the tree. Keep durable structure recorded there as you learn it."
else
  mpath="$(charter_map_path "$root")"
  orient="[charter] Consult $mpath to orient instead of re-scanning the tree, and keep it current as structure changes — it's how a session loads the project cheaply."
fi

charter_log "session-start" "qa=$status roadmap=$rstatus map=$mstatus src=${src:-?} mode=full"
emit "$qa"$'\n\n'"$roadmap"$'\n\n'"$orient"
