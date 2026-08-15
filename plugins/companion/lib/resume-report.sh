#!/usr/bin/env bash
# The session-context content builders — the single source of truth for what "resume" prints,
# shared by resume.sh (manual pull, R100/Pass 2) and session-start.sh (automatic push, R100/Pass 6
# reinstated — the owner asked for guaranteed context delivery back, having watched a model ignore
# instructions it never actually had in context). Extracted rather than duplicated: two copies of
# this content generator would drift on what "the resume content" means the moment either changed.
#
# Split in two because a fresh session start and a post-compaction re-anchor want different
# amounts of the STEERING core (full core vs a short re-anchor, R30·d2 — the doc's rationale is
# preserved through the summarizer, re-pasting it every compaction is the token cost this split
# avoids) but IDENTICAL everything else: carried tasks, the version-lag warning, LESSONS, R93's
# out-of-band changes, and R94's rework are all cheap (zero-cost when empty) and equally relevant
# after a compaction as at a fresh start — a compaction IS the state clear R93 exists to survive.

# companion_resume_steering ROOT PLUGIN_DIR WAS_ARMED -> the STEERING core (unless steering=off),
# with the mode prose appended when WAS_ARMED=1. Empty string when steering is off or absent.
companion_resume_steering() {
  local root="$1" PLUGIN_DIR="$2" was_armed="${3:-0}" out=""
  if ! companion_feature_off steering "$root"; then
    if [ -f "$PLUGIN_DIR/STEERING.md" ]; then
      out="── Working agreement — governs how you queue, decide, and keep this repo clean for the session ──"$'\n'"$(awk '/injection stops here/{exit} {print}' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || cat "$PLUGIN_DIR/STEERING.md")"
      if [ "$was_armed" -eq 1 ]; then
        out="$out"$'\n'"$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || true)"
      fi
    fi
  fi
  printf '%s' "$out"
}

# companion_any_in_progress ROOT -> 0 when some task for this repo is mid-flight. Reads the SAME
# scoped file list as the renderer (companion_task_files) rather than re-deriving it, so the two can
# never disagree about which tasks are this repo's.
companion_any_in_progress() {
  local root="$1" f out; local -a files=()
  while IFS= read -r -d '' f; do [ -n "$f" ] && files+=("$f"); done < <(companion_task_files "$root")
  [ "${#files[@]}" -gt 0 ] || return 1
  # Batch first, per-file only when the batch FAILED — the same trap the renderer documents: jq
  # aborts at the first unparseable file. Testing the exit status alone would send every clean
  # session down the per-file path (one spawn per task, the 265-spawn regression), so branch on
  # whether jq produced a COUNT, not on whether it said "false".
  if out="$(jq -s '[.[]|select(.status=="in_progress")]|length' "${files[@]}" 2>/dev/null)"; then
    case "$out" in ''|*[!0-9]*) return 1 ;; esac
    [ "$out" -gt 0 ] && return 0
    return 1
  fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    [ "$(jq -r '.status // ""' "$f" 2>/dev/null)" = "in_progress" ] && return 0
  done
  return 1
}

# companion_unreconciled ROOT -> the UNRECONCILED-WORK warning, or nothing.
#
# Dirty tree + NO task in_progress means an earlier session stopped mid-work without leaving the
# breadcrumb `tq doing`/`tq note` exists to leave — a crashed terminal, a killed process, a `/clear`.
# The edits themselves survive (git keeps them), but nothing says which task they belong to or how
# far they got, so the next session cannot tell 10%-done from 90%-done: it either redoes the work or
# builds on a half-applied change. That is the one crash case the durable queue does NOT already
# cover, and it is why this is DETECTION rather than prevention. R99 is right that no hook can force
# a good breadcrumb — but NOTICING the state a missing breadcrumb leaves behind is an inject, which
# R28 does allow, and unlike the retired R58·a capture hook this has a reader by construction: the
# thing that consumes it is the next session, in the same breath as the carried queue.
#
# Silent when the tree is clean, when a task IS in_progress (the breadcrumb did its job — the
# carried-task list already shows it, marked ▸), and when this is not a git repo at all.
#
# COST (R81): one `git status --porcelain`, which walks the worktree — ~6ms here, ~43ms on a
# 17k-file repo (measured for statusline.sh, which caches it only because it re-renders constantly).
# This fires ONCE per session, so it is deliberately NOT cached: a stale answer, on the one path
# whose whole job is telling you the truth about the tree, is worse than 43ms. dev/hook-budget.sh
# scales the fixture REPO as well as the store so this call is measured, never asserted.
companion_unreconciled() {
  local root="$1" out n list more=""
  [ -n "$root" ] || return 0
  command -v git >/dev/null 2>&1 || return 0
  # Cheapest discriminator first: a mid-flight task means no warning regardless of the tree, so the
  # common autopiloted case never pays for the worktree walk at all.
  companion_any_in_progress "$root" && return 0
  # Capped read (R81): a repo with 50k dirty paths must not build a 50k-line string on a hook path.
  # 201 lines, so 201 can be reported honestly as "200+" instead of silently as "200".
  # `.companion/` is EXCLUDED: the queue store lives there and is untracked in most projects, so
  # counting it would make this warn about its own bookkeeping on every session — a false positive
  # in the one place a false positive is fatal, since a warning that always fires gets ignored. This
  # is not an ecosystem guess (R9 forbids those); it is the plugin's own state directory.
  out="$(git -C "$root" status --porcelain -- ':(exclude).companion' 2>/dev/null | head -n 201)" || return 0
  [ -n "$out" ] || return 0
  n="$(printf '%s\n' "$out" | grep -c . 2>/dev/null || printf '0')"
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  [ "$n" -gt 200 ] && { n=200; more=" (at least)"; }
  list="$(printf '%s\n' "$out" | head -n 10 | sed 's/^/       /')"
  [ "$n" -gt 10 ] && list="$list"$'\n'"       … and $((n - 10)) more"
  printf '%s' $'\n\n'"── ⚠️  UNRECONCILED WORK — ${n}${more} uncommitted change(s), and NO task is in_progress ──"$'\n'"An earlier session may have stopped mid-task (crashed terminal, killed process, /clear). These edits survive on disk, but NOTHING in the queue claims them or records how far they got. Reconcile BEFORE starting new work: read the diff, then either claim it (\`tq doing <id>\` + \`tq note <id> \"<where it actually stands>\"\`), finish and commit it, or revert it. Do not build on top of it blind."$'\n'"$list"
}

# companion_unreachable ROOT -> a notice about session dirs NO repo can ever resume, or nothing.
#
# WHAT THIS IS NOT, and the distinction is the whole design: a dir stamped for a DIFFERENT repo is
# not unreachable, it is simply not ours, and reporting those would be exactly the cross-project
# bleed the store scoping exists to prevent. Unreachable means no usable stamp AT ALL — no `.repo`
# identity, and either no `.root` or a `.root` naming a path that no longer exists. Such a dir
# matches nothing from any repo, in any session, forever: `tq` only writes stamps on `add`, so once
# the session that owned it is gone, no later `add` ever runs there to heal it. That is real open
# work that silently cannot be handed back — the #91 residual, the half of that decision that
# survived measurement (tq itself can no longer PRODUCE an unstamped dir; older ones still exist).
#
# Only SCOPED stores are examined: the repo's own `.companion/tasks` is reachable by construction
# (everything in it belongs to this repo, no stamp needed), so a missing stamp there means nothing.
#
# COST (R81): a directory walk plus two `[ -f ]` tests per dir — no forks, no jq — and jq runs ONLY
# on dirs that already look unreachable, which is zero in a healthy store. Same shape as the scan
# in companion_task_files, and measured by dev/hook-budget.sh, which scales this store 8x.
companion_unreachable() {
  local root="$1" store d rid rroot n out="" dirs=0; local -a cand=()
  # An explicit CLAUDE_COMPANION_TASKS_DIR is a global store BY DEFINITION and is scoped; without
  # one, only the legacy home store is (the repo store is not, per the note above).
  if [ -n "${CLAUDE_COMPANION_TASKS_DIR:-}" ]; then store="$CLAUDE_COMPANION_TASKS_DIR"
  else store="$HOME/.claude/companion/tasks"; fi
  [ -d "$store" ] || return 0
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    rid=""; rroot=""
    # `read` builtin, not $(cat) — this runs on SessionStart; two forks per dir was 82 spawns on a
    # real store. A newline-less marker makes `read` return 1, so test the VARIABLE, not the status.
    [ -f "$d.repo" ] && { IFS= read -r rid  < "$d.repo"  || true; }
    [ -f "$d.root" ] && { IFS= read -r rroot < "$d.root" || true; }
    # EITHER stamp is enough, and `.root` counts even when the path is not on this disk right now.
    # The first draft required `[ -d "$rroot" ]` — and the test immediately caught it reporting a
    # dir stamped for a repo that simply was not mounted, which is the cross-project bleed this
    # function's whole definition exists to avoid. A stamp naming an absent path is a repo that is
    # elsewhere (another machine, an unmounted volume, a clone not checked out), not a dir nothing
    # can claim. Only the TOTAL ABSENCE of a stamp is unreachable.
    [ -n "$rid" ] && continue
    [ -n "$rroot" ] && continue
    cand+=("$d")
  done
  [ "${#cand[@]}" -gt 0 ] || return 0
  for d in "${cand[@]}"; do
    set -- "$d"*.json
    [ -f "$1" ] || continue
    n="$(jq -s '[.[]|select(.status=="pending" or .status=="in_progress")]|length' "$@" 2>/dev/null)"
    case "${n:-0}" in ''|*[!0-9]*) continue ;; esac
    [ "$n" -gt 0 ] || continue          # a dir of finished tasks is dead weight, not lost work
    dirs=$((dirs + 1))
    [ "$dirs" -le 5 ] && out="$out"$'\n'"       ${n} open · ${d}"
  done
  [ "$dirs" -gt 0 ] || return 0
  [ "$dirs" -gt 5 ] && out="$out"$'\n'"       … and $((dirs - 5)) more"
  local subj="${dirs} task store directories hold"
  [ "$dirs" -eq 1 ] && subj="1 task store directory holds"
  printf '%s' $'\n\n'"── ⚠️  UNREACHABLE QUEUE — ${subj} OPEN work that NO repo can resume ──"$'\n'"These carry no repo stamp at all, so no session in any project will ever surface them — the work in them is invisible rather than lost. \`tq\` stamps on every \`add\` now, so these predate that: they cannot heal themselves, because healing only happens on an \`add\` in the session that owned them. Read them (\`jq -r .subject <dir>/*.json\`) and either re-add what still matters to this repo's queue, or delete the directory to stop this notice."$'\n'"$out"
}

# companion_resume_report ROOT PLUGIN_DIR -> carried tasks + version-lag warning + LESSONS +
# recent out-of-band changes (R93) + recorded rework (R94). Deliberately does NOT include
# STEERING — see companion_resume_steering — so a caller can pair a short message with the full
# report (the compact re-anchor) instead of the full STEERING core with it (a fresh start).
companion_resume_report() {
  local root="$1" PLUGIN_DIR="$2" out=""

  local carry; carry="$(companion_open_tasks "$root")"
  if [ -n "$carry" ]; then
    out="$out"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"
  else
    out="$out"$'\n\n'"No carried-over open tasks for $root."
  fi

  # Immediately after the queue, because it is a statement ABOUT the queue: work exists in the tree
  # that the queue does not account for. Costs nothing when the tree is clean or a task is ▸.
  out="$out$(companion_unreconciled "$root")"
  # Same family: work that exists and the queue cannot account for. Zero-cost in a healthy store.
  out="$out$(companion_unreachable "$root")"

  local _ver_running _ver_name
  _ver_running="$(jq -r '.version // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
  _ver_name="$(jq -r '.name // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
  if [ -n "$_ver_running" ] && [ -n "$_ver_name" ]; then
    local _m _ver_tree
    for _m in "$root"/plugins/*/.claude-plugin/plugin.json; do
      [ -f "$_m" ] || continue
      [ "$(jq -r '.name // empty' "$_m" 2>/dev/null || true)" = "$_ver_name" ] || continue
      _ver_tree="$(jq -r '.version // empty' "$_m" 2>/dev/null || true)"
      if [ -n "$_ver_tree" ] && [ "$_ver_tree" != "$_ver_running" ]; then
        out="$out"$'\n\n'"⚠️  RUNNING v${_ver_running}, BUT THIS WORKING TREE IS v${_ver_tree}. Anything you add here is INERT until the plugin is reinstalled. Do not report a change as working because the repo is green; say which version actually ran."
      fi
      break
    done
  fi

  local lf
  for lf in "$root/docs/LESSONS.md" "$root/LESSONS.md" "$root/.companion/LESSONS.md"; do
    [ -f "$lf" ] || continue
    out="$out"$'\n\n'"── This repo's LESSONS (accumulated gotchas — heed them, and append new ones as you learn them) ──"$'\n'"$(awk '/lessons injection stops here/{exit} {print}' "$lf" 2>/dev/null || cat "$lf")"
    break
  done

  local _win _cut
  _win="${CLAUDE_COMPANION_CHANGE_WINDOW_DAYS:-14}"
  case "$_win" in ''|*[!0-9]*) _win=14 ;; esac
  _cut="$(date -u -d "-${_win} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${_win}"d +%Y-%m-%d 2>/dev/null || true)"
  if [ -n "$_cut" ]; then
    local cf _recent
    for cf in "$root/docs/CHANGES-OUTSIDE-GIT.md" "$root/CHANGES-OUTSIDE-GIT.md" "$root/.companion/CHANGES-OUTSIDE-GIT.md"; do
      [ -f "$cf" ] || continue
      _recent="$(tail -n 200 "$cf" 2>/dev/null | awk -v c="$_cut" '
        /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = ($2 >= c) }
        f' 2>/dev/null | head -c 2000)"
      [ -n "$_recent" ] && out="$out"$'\n\n'"── Changed OUTSIDE this repo in the last ${_win} days — git cannot show these, and they are the first thing to suspect when something breaks ──"$'\n'"$_recent"
      break
    done
  fi

  local _rw _rwout
  _rw="$(companion_rework_file "$root")"
  if [ -f "$_rw" ]; then
    _rwout="$(REWORK_ROOT="$root" "$PLUGIN_DIR/bin/rework.sh" report 2>/dev/null | head -c 800)"
    case "${_rwout:-}" in
      ''|rework:\ none*) : ;;
      *) out="$out"$'\n\n'"── REWORK already recorded here (work that had to be done twice — read it as your own defect rate, not as a list of catches) ──"$'\n'"$_rwout" ;;
    esac
  fi

  printf '%s' "$out"
}
