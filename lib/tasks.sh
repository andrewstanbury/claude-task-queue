#!/usr/bin/env bash
# claude-task-queue (v0.4): support lib for the SessionStart "resume bridge".
#
# Claude Code's native task list is per-session working memory — a fresh session
# starts empty and can't see tasks an earlier session left unfinished. This lib
# backs bin/tq-resume.sh, which reads Claude Code's native task store and
# surfaces a repo's still-open tasks from earlier sessions so the model can
# re-adopt them.
#
# Claude Code persists every task the model creates (TaskCreate / TaskUpdate) as
# a JSON file under ~/.claude/tasks/<session-id>/<n>.json:
#   { "id", "subject", "description", "activeForm",
#     "status": "pending" | "in_progress" | "completed", "blocks", "blockedBy" }
#
# Read-only by principle: this never writes the native store. The model owns
# those tasks; we only read them. A task folder is keyed by session id; we map a
# session to its repo by reading the cwd from its transcript
# ~/.claude/projects/<enc-cwd>/<sid>.jsonl (immutable per session, so cached).

set -euo pipefail

# ---- locations (all overridable for tests) ---------------------------------

tq_tasks_dir()       { printf '%s' "${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}"; }
tq_projects_dir()    { printf '%s' "${CLAUDE_TQ_PROJECTS_DIR:-$HOME/.claude/projects}"; }
tq_state_dir()       { printf '%s' "${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"; }
tq_root_cache_file() { printf '%s/root-cache.tsv' "$(tq_state_dir)"; }

# ---- helpers ----------------------------------------------------------------

# Portable mtime (seconds). GNU stat then BSD/macOS stat then 0.
tq_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

# A cwd -> absolute project ROOT: the git repo toplevel. Falls back to the cwd
# itself when the session didn't run inside a repo (or the path is gone).
tq_root_for_cwd() {
  local cwd="$1" top dir
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then printf '%s' "$top"; return 0; fi
  dir="$cwd"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/.git" ] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  printf '%s' "$cwd"
}

# session id -> absolute repo root. Cached (a session's cwd never changes).
# Returns non-zero and prints nothing when the transcript or its cwd can't be
# resolved (e.g. the session's transcript hasn't been written yet).
tq_session_root() {
  local sid="$1" cache root transcript cwd pdir f
  cache="$(tq_root_cache_file)"

  if [ -f "$cache" ]; then
    root="$(awk -F'\t' -v s="$sid" '$1==s {print $2; exit}' "$cache" 2>/dev/null || true)"
    [ -n "$root" ] && { printf '%s' "$root"; return 0; }
  fi

  pdir="$(tq_projects_dir)"
  transcript=""
  for f in "$pdir"/*/"$sid.jsonl"; do
    [ -f "$f" ] && { transcript="$f"; break; }
  done
  [ -n "$transcript" ] || return 1

  cwd="$(head -n 40 "$transcript" 2>/dev/null | jq -r 'select(.cwd != null) | .cwd' 2>/dev/null | head -n1 || true)"
  [ -n "$cwd" ] || return 1
  root="$(tq_root_for_cwd "$cwd")"
  [ -n "$root" ] || return 1

  mkdir -p "$(tq_state_dir)" 2>/dev/null || true
  printf '%s\t%s\n' "$sid" "$root" >> "$cache" 2>/dev/null || true
  printf '%s' "$root"
}

# ---- resume bridge ----------------------------------------------------------

# Build the SessionStart "resume" note for a repo: OPEN (pending / in_progress)
# tasks from OTHER sessions rooted at the same repo as cur_root — work a previous
# session left unfinished — so a fresh session can re-adopt the relevant ones
# into its (otherwise empty) native task list.
#
# Kept short on purpose (it enters model context): all in_progress tasks, plus
# the most-recently-touched todos up to a cap, with a "…and N more" tail. Whole
# sessions untouched for longer than the age cutoff are skipped so abandoned
# backlogs stop resurrecting. De-duplicated by subject (newest mtime wins).
# Prints nothing when there is no qualifying carried-over work.
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
        jq -r --arg m "$m" 'select(.status=="pending" or .status=="in_progress")
               | [.status, $m, (.subject // "")] | @tsv' "$f" 2>/dev/null || true
      done
    done
  )"
  [ -n "$rows" ] || return 0

  # Dedup by subject (newest mtime wins), doing first, todos ranked by recency
  # and capped. One bullet per task; a tail counts whatever was trimmed.
  printf '%s\n' "$rows" | awk -F'\t' -v max="$max" '
    NF >= 3 {
      s=$3; mt=$2+0
      if (!(s in mtime) || mt > mtime[s]) mtime[s]=mt
      if ($1=="in_progress") doing[s]=1
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
      printf "%d open task%s carry over from earlier Claude Code sessions in this project (your native task list starts empty each session). If the user is continuing this work, recreate the relevant ones with TaskCreate (set any that were in progress back to in_progress); otherwise ignore this note.\n", n, (n==1?"":"s")
      for (i=0;i<dn;i++)    printf "  • [doing] %s\n", dsub[i]
      for (i=0;i<shown;i++) printf "  • [todo]  %s\n", tsub[i]
      if (more > 0) printf "  …and %d more todo%s.\n", more, (more==1?"":"s")
    }'
}
