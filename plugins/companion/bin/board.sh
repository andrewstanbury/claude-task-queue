#!/usr/bin/env bash
# board.sh — a human-facing visual render of the queue, grouped by the SAME typed lanes tq report
# already tracks (▸/◻/❓/⏳/⛔/✔). Nothing new is invented here: no taxonomy, no score. This exists
# because tq's report/delta are deliberately terse (R69 — they fire on every mutation, so DONE
# collapses to a count and subjects truncate at 72 chars). board is explicitly invoked, never
# injected, so it can afford to spend the tokens report cannot: DONE rendered as a real checked-off
# list, untruncated subjects, and a dependency note per task instead of one global next-pointer.
#
# Also shows, read-only, what candidates.sh (already-existing provenance ranking, R82) would propose
# BEYOND the queue — so the owner can see and correct the plugin's own assessment of what's highest
# signal, without this becoming a second opinion on what autopilot actually drains next (that stays
# queue order + `after #N`, unchanged).
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "board: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${BOARD_ROOT:-$PWD}")"
# The modern store is flat and needs no session id (R96 stage 2); a session id only matters for the
# legacy home-scoped store, so DIR mirrors tq's own resolution via the shared lib function instead
# of a second copy of that logic.
SID="${CLAUDE_COMPANION_SESSION_ID:-${CLAUDE_CODE_SESSION_ID:-}}"
if [ -n "$SID" ]; then DIR="$(companion_session_dir "$root" "$SID")"
else DIR="$(companion_tasks_dir "$root")"; fi

files=(); skipped=0
if [ -d "$DIR" ]; then
  for f in "$DIR"/*.json; do
    [ -f "$f" ] || continue
    # `jq -rs` ABORTS THE WHOLE RENDER on the first unparseable file — companion_open_tasks was
    # already burned by this exact shape (measured: 7 open tasks silently rendered as 0 on one
    # corrupt file). Pre-filter here rather than trusting -s over the raw glob, so one bad file
    # costs only itself, never the board.
    if jq -e . "$f" >/dev/null 2>&1; then files+=("$f"); else skipped=$((skipped+1)); fi
  done
fi

echo "📋 Queue board — ${root##*/}"
echo "   ▸ in progress · ◻ open (pre-cleared) · ❓ your decision · ⏳ owner-only · ⛔ ruled out · ✔ done"
[ "$skipped" -gt 0 ] && echo "   ⚠ $skipped task file(s) unreadable — skipped, not counted"
echo

if [ "${#files[@]}" -eq 0 ]; then
  echo "  (queue empty)"
else
  jq -rs '
    def subj: (.subject//"");
    def pk: (subj|sub("^\\s+";"")|startswith("❓"));
    def bl: (subj|sub("^\\s+";"")|startswith("⏳"));
    def rl: (subj|sub("^\\s+";"")|startswith("⛔"));
    def clean: (subj|sub("^\\s*[❓⏳⛔]\\s*";""));
    # Reuses the exact rec: convention tq report renders — a park is required to carry one, and
    # this is the one place anyone reads it back (LESSONS: it was being stored and then hidden).
    def rec: (subj | if test("rec:") then "\n       └ rec: " + (split("rec:")[1]|sub("^\\s+";"")) else "" end);
    # done_when/context (R99) are the two things that survive a compaction or a `/clear` — board
    # is explicitly invoked, so unlike tq report it can afford to always show them, not just carry
    # them silently in the store.
    def dw: (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end);
    def ctx: (if (.context//"")!="" then "\n       └ context: " + .context else "" end);
    def waits: [(subj | match("after #([0-9]+)";"g").captures[0].string)];
    # `$live|index(.)` inside select is a trap, not a filter: `.` there is $live itself (the
    # whole array), not the element being tested, so it matched EVERY id regardless of liveness
    # (verified: returns unrelated ids too). Explicit `as $x` binds the actual element first.
    def dep($live): (waits | map(select(. as $x | $live|index($x)))) as $bl2
      | if ($bl2|length)>0 then "   ⧗ waiting on #" + ($bl2|join(", #")) else "" end;
    def ln($g;$live): "  "+$g+" #"+(.id|tostring)+"  "+clean+dep($live)+dw+ctx;
    def lnr($g): "  "+$g+" #"+(.id|tostring)+"  "+clean+rec+dw+ctx;
    def section($label;$items;f): if ($items|length)>0 then
        "", $label+" ("+($items|length|tostring)+")", ($items[]|f)
      else empty end;

    (map(select(.status=="pending" or .status=="in_progress"))|map(.id|tostring)) as $live
    |(map(select(.status=="in_progress"))|sort_by(.id|tonumber)) as $ip
    |(map(select(.status=="pending" and (pk|not) and (bl|not) and (rl|not)))|sort_by(.id|tonumber)) as $op
    |(map(select(.status=="pending" and pk))|sort_by(.id|tonumber)) as $p
    |(map(select(.status=="pending" and bl))|sort_by(.id|tonumber)) as $b
    |(map(select(.status=="pending" and rl))|sort_by(.id|tonumber)) as $rlist
    |(map(select(.status=="completed"))|sort_by(.id|tonumber)) as $d
    | section("▸ IN PROGRESS";$ip;ln("▸";$live)),
      section("◻ OPEN — pre-cleared, minimal-blast";$op;ln("◻";$live)),
      section("❓ PARKED — decisions for you";$p;lnr("❓")),
      section("⏳ BLOCKED — owner-only manual jobs";$b;lnr("⏳")),
      section("⛔ RULED OUT";$rlist;ln("⛔";$live)),
      section("✔ DONE";$d;"  ✔ #"+(.id|tostring)+"  "+clean)
  ' "${files[@]}" 2>/dev/null | awk 'NR==1 && /^$/{next} {print}'
fi

# Read-only: what burn-down's provenance ranking (candidates.sh, R82) would propose next if there
# were no other queued work. Display only — drain order is unchanged, still queue-order + after #N.
# `cd` into root FIRST (matching stop-autopilot.sh's own call) rather than only exporting
# BURNDOWN_ROOT: candidates.sh's rank-5 rework check shells out to rework.sh, which without an
# explicit REWORK_ROOT falls back to $PWD — board's own caller's cwd, not necessarily this repo.
cand="$(cd "$root" 2>/dev/null && BURNDOWN_ROOT="$root" "$PLUGIN_DIR/bin/candidates.sh" 2>/dev/null)"
if [ -n "$cand" ]; then
  echo
  echo "── beyond the queue — what burn-down would propose next (display only) ──"
  while IFS='|' read -r rank src txt; do
    [ -n "$rank" ] || continue
    printf '  %s. [%s] %s\n' "$rank" "$src" "$txt"
  done <<< "$cand"
fi

# WORK IN FLIGHT, BY CLASS (R116·b). The state lanes above answer "what is queued"; this answers
# "what SHAPE is the change you are building right now" — and specifically whether ship will demand
# a branch for it. Feature-class means a docs/flows page moved alongside implementation, i.e. what
# the user can DO changed (R58), so it lands from a branch and merges on the owner's say-so.
#
# Shown HERE rather than on the status line, deliberately (owner-decided 2026-08-20): the status
# line answers "what needs me NOW" in one always-visible line already carrying ten segments; class
# is a property of a CHANGE, not of a task, and belongs where there is room to explain it.
#
# Read-only and quiet when there is nothing to say — same rule as every other section here.
_bd_changed="$( { git -C "$root" -c core.quotepath=false diff --name-only --no-renames HEAD 2>/dev/null
                  git -C "$root" -c core.quotepath=false ls-files --others --exclude-standard 2>/dev/null; } \
                | sort -u )"
if [ -n "$_bd_changed" ]; then
  echo
  if companion_is_feature_class "$_bd_changed"; then
    echo "── work in flight: FEATURE-CLASS ──"
    echo "  a docs/flows page moved with implementation, so this changes what the user can DO."
    echo "  ship will refuse the default branch: build it on a branch, behind a flag defaulting OFF,"
    echo "  and it merges on your say-so (override: ship.sh land --merge-feature, before --gate)."
  else
    printf '  work in flight: ordinary (%s changed path(s)) — ships straight through\n' \
      "$(printf '%s\n' "$_bd_changed" | grep -c .)"
  fi
fi

# 🚩 FINISHED AND WAITING ON YOU (R117). The lanes above are work that needs DOING or DECIDING; this
# is work already done, sitting on a branch nobody has looked at — a burn-down branch built
# unattended, or a feature-class change ship pushed and deliberately declined to merge. It was
# invisible on every surface, so "done, waiting on you" read exactly like "nothing happening",
# which is the most expensive silence here: the work is already paid for.
#
# One implementation, three surfaces: the status line's 🚩 lane, any MCP client, and this — all call
# awaiting-review.sh rather than each re-deriving "unmerged and handed over" (that second copy is
# what let default_branch drift three ways). Quiet when empty, like every section above.
_ar_rows="$(AWAITING_ROOT="$root" "$PLUGIN_DIR/bin/awaiting-review.sh" list 2>/dev/null || true)"
if [ -n "$_ar_rows" ]; then
  echo
  echo "── 🚩 finished — waiting on YOU ──"
  while IFS="$(printf '\t')" read -r kind br; do
    [ -n "$br" ] || continue
    case "$kind" in
      burndown) printf '  🚩 %s — built unattended; review, then merge or discard\n' "$br"
                # The manifest is the WHY, and it lives outside the branch on purpose (it would
                # vanish on checkout of the default). Point at it rather than reprinting it here.
                printf '      why: burndown-branch.sh show %s\n' "${br#burndown/}" ;;
      *)        printf '  🚩 %s — pushed and unmerged; merge when you are happy with it\n' "$br" ;;
    esac
  done <<< "$_ar_rows"
fi
