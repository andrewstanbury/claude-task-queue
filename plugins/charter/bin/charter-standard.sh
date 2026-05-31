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

# Full context (startup/clear/unknown). For each project-knowledge dimension:
# a MISSING doc → a drift nudge (always shown); a PRESENT doc → a recurring
# "honor/consult" reminder UNLESS the policy is recorded in CLAUDE.md (the
# claude-companion marker), in which case it's dropped (bootstrap-once + quiet).
# When everything is present and marked, charter stays silent.
web="$(charter_is_web "$root" 2>/dev/null || printf 'no')"
documented=0
charter_policy_documented "$root" && documented=1

parts=()

# Quality attributes (web projects get Lighthouse-aligned defaults so best
# practices are designed-in, not audited after).
if [ "$status" = "missing" ]; then
  if [ "$web" = "web" ]; then
    parts+=("[charter] This is a web project with no documented quality attributes. Capture them in QUALITY.md before substantive changes and bake in web best practices so they're designed-in, not audited after: Core Web Vitals budgets (LCP/CLS/INP), accessibility (WCAG AA, semantic HTML, jsx-a11y/stylelint at edit time), SEO/meta, responsive + print styles, progressive enhancement (works without JS, enhance up), and components-by-default (prefer components over raw elements; reuse existing before creating new). Honor them on every change; Lighthouse/CI is a backstop, not the rework loop.")
  else
    parts+=("[charter] This project has no documented quality attributes. Before substantive changes, capture them — performance, security, accessibility, reliability, maintainability targets — in QUALITY.md (or a \"Quality Attributes\" section of CLAUDE.md). Changes should then honor them.")
  fi
elif [ "$documented" -eq 0 ]; then
  parts+=("[charter] This project documents its quality attributes — honor them when changing code, and surface the relevant one when you touch related areas.")
fi

# Roadmap/backlog — the cross-session, cross-engineer record of what's next.
rstatus="$(charter_roadmap_status "$root" 2>/dev/null || printf 'missing')"
if [ "$rstatus" = "missing" ]; then
  parts+=("[charter] No committed roadmap/backlog file. Generate docs/ROADMAP.md as a Claude-facing backlog — a terse Now/Next/Later list plus a dated changelog — inferred from git history and the codebase (apply sensible defaults; note any assumptions plainly for the owner), then commit it. It is how work is picked up, resumed, and coordinated across engineers on separate machines; git history is the shared audit trail.")
elif [ "$documented" -eq 0 ]; then
  roadmap_line="[charter] $(charter_roadmap_path "$root") is this project's backlog — read it for what's next, and reconcile it against recent git history before substantive changes (mark merged items done, append a dated changelog entry, flag drift). Keep it committed so other engineers resume from the same state."
  recent="$(charter_recent_commits "$root" 5 2>/dev/null | awk 'NF{printf "%s%s", sep, $0; sep="; "}')"
  [ -n "$recent" ] && roadmap_line="$roadmap_line"$'\n'"  recently merged (reconcile the roadmap against these — mark done what landed): $recent"
  parts+=("$roadmap_line")
fi

# Decisions/ADRs — so Claude doesn't re-litigate or contradict past choices.
dstatus="$(charter_decisions_status "$root" 2>/dev/null || printf 'missing')"
if [ "$dstatus" = "missing" ]; then
  parts+=("[charter] No decision record. Capture key architectural decisions in DECISIONS.md (or docs/adr/) — infer the major ones already evident in the code and git history, applying sensible defaults and noting assumptions plainly, and add new ones as you decide. This stops Claude re-litigating or contradicting past choices.")
elif [ "$documented" -eq 0 ]; then
  parts+=("[charter] $(charter_decisions_path "$root") records this project's decisions — consult it before substantive changes and honor/extend it; don't reverse a recorded decision without updating the record.")
fi

# Orientation = the project map. Missing → generate it from the codebase; present
# → consult it instead of re-scanning the tree (dropped when marked).
mstatus="$(charter_map_status "$root" 2>/dev/null || printf 'missing')"
if [ "$mstatus" = "missing" ]; then
  parts+=("[charter] No project map. Generate docs/MAP.md — a compact file→responsibility index plus the key entry points — from the codebase, so future sessions (and other engineers) orient from the map instead of re-scanning the tree. Keep durable structure recorded there as you learn it.")
elif [ "$documented" -eq 0 ]; then
  parts+=("[charter] Consult $(charter_map_path "$root") to orient instead of re-scanning the tree, and keep it current as structure changes — it's how a session loads the project cheaply.")
fi

# Stack/architecture notes — the durable record of languages/frameworks/versions
# that modernization & currency judgments lean on. Missing → capture it from the
# manifests; present → consult (dropped when marked).
sstatus="$(charter_stack_status "$root" 2>/dev/null || printf 'missing')"
if [ "$sstatus" = "missing" ]; then
  parts+=("[charter] No stack notes. Capture the tech stack — languages, frameworks, key dependencies and their versions, and build/test tooling — in STACK.md (or a \"## Stack\" section of CLAUDE.md), inferred from the manifests. It's the durable context modernization and dependency judgments rely on.")
elif [ "$documented" -eq 0 ]; then
  parts+=("[charter] $(charter_stack_path "$root") documents the stack — consult it (and keep it current) when adding dependencies or judging what's outdated.")
fi

# Bootstrap tip: if policy isn't marked yet but some docs exist (so there are
# honor-reminders to quiet), point at the marker once.
if [ "$documented" -eq 0 ] && { [ "$status" != "missing" ] || [ "$rstatus" != "missing" ] || [ "$mstatus" != "missing" ] || [ "$dstatus" != "missing" ] || [ "$sstatus" != "missing" ]; }; then
  parts+=("[charter] Tip: once these project docs are summarised in CLAUDE.md, mark it \"claude-companion\" and charter's honor-reminders go silent (the gap nudges stay).")
fi

charter_log "session-start" "qa=$status roadmap=$rstatus decisions=$dstatus map=$mstatus stack=$sstatus web=$web marked=$documented src=${src:-?} mode=full"

# Join non-empty parts; stay silent if there's nothing to say (fully documented + marked).
ctx=""
if [ "${#parts[@]}" -gt 0 ]; then
  for p in "${parts[@]}"; do
    [ -n "$p" ] || continue
    if [ -z "$ctx" ]; then ctx="$p"; else ctx="$ctx"$'\n\n'"$p"; fi
  done
fi
[ -n "$ctx" ] || exit 0
emit "$ctx"
