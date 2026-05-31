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

# Once per session, keep the activity log bounded so it never becomes cruft.
charter_prune_log 2>/dev/null || true

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

# Full context (startup/clear/unknown): a compact, PROPORTIONAL project brief.
# Baseline docs Claude can't infer (map + what's-next) are nudged when missing;
# quality attributes only for web projects; decisions/stack are left to the
# model's judgment (scale up with complexity, don't over-document a small repo).
# PRESENT docs collapse into one "consult" line, dropped when the policy is marked
# in CLAUDE.md. Everything present + marked → silent.
web="$(charter_is_web "$root" 2>/dev/null || printf 'no')"
documented=0
charter_policy_documented "$root" && documented=1

rstatus="$(charter_roadmap_status "$root" 2>/dev/null || printf 'missing')"
dstatus="$(charter_decisions_status "$root" 2>/dev/null || printf 'missing')"
mstatus="$(charter_map_status "$root" 2>/dev/null || printf 'missing')"
sstatus="$(charter_stack_status "$root" 2>/dev/null || printf 'missing')"
charter_log "session-start" "qa=$status roadmap=$rstatus decisions=$dstatus map=$mstatus stack=$sstatus web=$web marked=$documented src=${src:-?} mode=full"

# Baseline gaps (always actionable); QA gap only for web projects.
gaps=()
[ "$mstatus" = "missing" ] && gaps+=("project map (docs/MAP.md) — a file→responsibility index so sessions orient without re-scanning the tree")
[ "$rstatus" = "missing" ] && gaps+=("roadmap/backlog (docs/ROADMAP.md) — a Now/Next/Later list + dated changelog, the cross-session record of what's next")
[ "$status" = "missing" ] && [ "$web" = "web" ] && gaps+=("quality attributes (QUALITY.md) — web project, so Lighthouse-aligned: Core Web Vitals, accessibility (WCAG AA, jsx-a11y/stylelint at edit time), SEO, responsive + print styles, progressive enhancement, components-by-default (reuse existing before creating new)")

# Present docs → one consult list.
present=()
[ "$status" != "missing" ]  && present+=("quality attributes")
[ "$rstatus" != "missing" ] && present+=("backlog → $(charter_roadmap_path "$root")")
[ "$dstatus" != "missing" ] && present+=("decisions → $(charter_decisions_path "$root")")
[ "$mstatus" != "missing" ] && present+=("map → $(charter_map_path "$root")")
[ "$sstatus" != "missing" ] && present+=("stack → $(charter_stack_path "$root")")

parts=()

if [ "${#gaps[@]}" -gt 0 ]; then
  body=""
  for g in "${gaps[@]}"; do body="$body"$'\n'"  • $g"; done
  parts+=("[charter] Generate the missing baseline docs from the codebase/git (apply sensible defaults, note assumptions plainly), then commit — Claude can't infer these:$body"$'\n'"Document proportionally to complexity: capture the evident decisions (DECISIONS.md/ADRs) so they aren't re-litigated, add stack notes (STACK.md), and — for non-web — quality-attribute targets only as the project's size or risk makes them earn their keep. Don't over-document a small project.")
fi

if [ "$documented" -eq 0 ] && [ "${#present[@]}" -gt 0 ]; then
  list=""
  for p in "${present[@]}"; do [ -z "$list" ] && list="$p" || list="$list, $p"; done
  brief="[charter] Project docs — consult as relevant before substantive changes: $list."
  # Decisions are the alignment anchor: clean ≠ correct — a well-made change can
  # still contradict a recorded choice. Restore the explicit "consult before
  # reversing" instruction (genericized away in 0.10.0); this is what
  # alignment-aware capture weighs work against.
  [ "$dstatus" != "missing" ] && brief="$brief"$' '"Recorded decisions are the alignment anchor — don't reverse or contradict one without consulting it first."
  if [ "$rstatus" != "missing" ]; then
    recent="$(charter_recent_commits "$root" 5 2>/dev/null | awk 'NF{printf "%s%s", sep, $0; sep="; "}')"
    [ -n "$recent" ] && brief="$brief"$' '"Reconcile the backlog against recent commits (mark done what landed): $recent."
  fi
  parts+=("$brief")
  parts+=("[charter] Summarise these in CLAUDE.md and mark it \"claude-companion\" to make this brief go silent.")
fi

# Join non-empty parts; silent when there's nothing to say (baseline present + marked).
ctx=""
if [ "${#parts[@]}" -gt 0 ]; then
  for p in "${parts[@]}"; do
    [ -n "$p" ] || continue
    if [ -z "$ctx" ]; then ctx="$p"; else ctx="$ctx"$'\n\n'"$p"; fi
  done
fi
[ -n "$ctx" ] || exit 0
emit "$ctx"
