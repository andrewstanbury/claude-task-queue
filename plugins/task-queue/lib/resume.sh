#!/usr/bin/env bash
# claude-task-queue: support lib — the SessionStart "resume bridge".
#
# Split out of lib/tasks.sh so that file stays at/under the size budget and the
# per-prompt hot path (the three PreToolUse guards + tq-capture) doesn't parse the
# resume-only builder they never call. This is the ONE consumer path — bin/tq-resume.sh
# (SessionStart) and bin/tq-restore.sh (the /task-queue:resume command) — so it lives
# in its own unit, sourced AFTER lib/tasks.sh (it depends on tq_tasks_dir / tq_mtime /
# tq_session_root at call time).

set -uo pipefail

# Build the SessionStart "resume" note for a repo: OPEN (pending / in_progress)
# tasks from OTHER sessions rooted at the same repo as cur_root — work a previous
# session left unfinished — so a fresh session can re-adopt the relevant ones
# into its (otherwise empty) native task list.
#
# Kept short on purpose (it enters model context, every SessionStart): subjects
# only — all in_progress tasks, plus the most-recently-touched todos up to a cap,
# with a "…and N more" tail — followed by a pointer to the prior session folder
# where the FULL description + blockedBy of every task lives on disk. That pointer
# is how a crash-resume stays high-fidelity without inlining every description on
# every startup (which the token budget forbids); the model reads those files when
# it actually restores. Whole sessions untouched for longer than the age cutoff are
# skipped so abandoned backlogs stop resurrecting. De-duplicated by subject (newest
# mtime wins). Prints nothing when there is no qualifying carried-over work.
#
#   $1  cur_root  absolute repo root of the starting session
#   $2  cur_sid   the starting session's id (excluded: it has no tasks yet)
#
# Tunables (env): CLAUDE_TQ_RESUME_MAX (todos shown, default 7),
#                 CLAUDE_TQ_RESUME_MAX_AGE_DAYS (session age cutoff, default 14).
tq_resume_context() {
  local cur_root="$1" cur_sid="${2:-}"
  [ -n "$cur_root" ] || return 0
  local tdir sdir sid root f has newest m rows
  local max="${CLAUDE_TQ_RESUME_MAX:-7}"
  local days="${CLAUDE_TQ_RESUME_MAX_AGE_DAYS:-14}"
  local now cutoff
  now="$(date +%s 2>/dev/null || echo 0)"
  cutoff=$(( now - days * 86400 ))
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || return 0

  # Emit "status<TAB>mtime<TAB>subject" for every open task in a matching,
  # recently-active session.
  rows="$(
    for sdir in "$tdir"/*/; do
      [ -d "$sdir" ] || continue
      sid="$(basename "$sdir")"
      [ "$sid" = "$cur_sid" ] && continue
      has=0; newest=0
      for f in "$sdir"*.json; do
        [ -f "$f" ] || continue
        has=1; m="$(tq_mtime "$f")"; [ "$m" -gt "$newest" ] && newest="$m"
      done
      [ "$has" -eq 1 ] || continue
      [ "$newest" -ge "$cutoff" ] || continue          # skip stale sessions
      root="$(tq_session_root "$sid" 2>/dev/null || true)"
      [ "$root" = "$cur_root" ] || continue
      for f in "$sdir"*.json; do
        [ -f "$f" ] || continue
        m="$(tq_mtime "$f")"
        jq -r --arg m "$m" --arg d "$sdir" 'select(.status=="pending" or .status=="in_progress")
               | [.status, $m, (.subject // ""), $d] | @tsv' "$f" 2>/dev/null || true
      done
    done
  )"
  [ -n "$rows" ] || return 0

  # Dedup by subject (newest mtime wins), doing first, todos ranked by recency
  # and capped. One bullet per task; a tail counts whatever was trimmed.
  printf '%s\n' "$rows" | awk -F'\t' -v max="$max" '
    NF >= 3 {
      s=$3; mt=$2+0; d=$4
      if (!(s in mtime) || mt > mtime[s]) mtime[s]=mt
      if ($1=="in_progress") doing[s]=1
      if (mt > gmax) { gmax=mt; gdir=d }   # newest folder = the crash-resume target
    }
    END {
      dn=0; tn=0
      for (s in mtime) {
        if (s in doing) { dsub[dn++]=s }
        else { tsub[tn]=s; tmt[tn]=mtime[s]; tn++ }
      }
      n=dn+tn
      if (n==0) exit 0
      # sort todos by mtime desc (small n, simple selection sort)
      for (i=0;i<tn;i++) for (j=i+1;j<tn;j++)
        if (tmt[j] > tmt[i]) { x=tmt[i];tmt[i]=tmt[j];tmt[j]=x; y=tsub[i];tsub[i]=tsub[j];tsub[j]=y }
      shown = (tn > max ? max : tn)
      more  = tn - shown
      printf "%d open task%s carry over from an earlier session in this project — your native list starts empty each session, so this is the crash/restart safety net. If the user is continuing this work, REINSTATE them now with TaskCreate as your first action (restore any in-progress ones to in_progress and resume from the progress breadcrumb in each one'"'"'s description) before anything else; if they have clearly moved on, ignore this note.\n", n, (n==1?"":"s")
      for (i=0;i<dn;i++)    printf "  ▸ %s\n", dsub[i]   # ▸ = in progress (matches the hud current-task marker; NOT ⏳, which means owner-blocked)
      for (i=0;i<shown;i++) printf "  ◻ %s\n", tsub[i]
      if (more > 0) printf "  …and %d more todo%s.\n", more, (more==1?"":"s")
      # Subjects only above (the budget caps this block, and it fires every
      # SessionStart, not just crashes). The FULL description + blockedBy for each
      # task lives on disk in the prior session folder — point there so a restore
      # is high-fidelity without inlining every description on every startup.
      if (gdir != "") printf "Full description + blockedBy for each is on disk at %s*.json — read those before recreating so restored tasks keep their detail and dependencies (this is also where the %d above and any not listed all live).\n", gdir, n
    }'
}
