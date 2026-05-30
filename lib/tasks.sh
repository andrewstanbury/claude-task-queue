#!/usr/bin/env bash
# claude-task-queue core (v0.2): a READ-ONLY view over Claude Code's native
# task store.
#
# Claude Code already persists every task the model creates (TaskCreate /
# TaskUpdate) as a JSON file under ~/.claude/tasks/<session-id>/<n>.json:
#
#   { "id", "subject", "description", "activeForm",
#     "status": "pending" | "in_progress" | "completed",
#     "blocks": [...], "blockedBy": [...] }
#
# status maps exactly to: pending = to-do, in_progress = doing, completed = done.
#
# Because the model writes these as a normal part of working, this plugin spends
# ZERO model tokens: it only reads the files and renders them. There is no second
# source of truth, no decomposition call, no hooks that enter model context.
#
# A task folder is keyed by session id. We map a session back to its project by
# finding the transcript ~/.claude/projects/<encoded-cwd>/<session-id>.jsonl and
# reading its cwd. That mapping is immutable per session, so we cache it.

set -euo pipefail

# ---- locations (all overridable for tests) ---------------------------------

tq_tasks_dir()    { printf '%s' "${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}"; }
tq_projects_dir() { printf '%s' "${CLAUDE_TQ_PROJECTS_DIR:-$HOME/.claude/projects}"; }
tq_state_dir()    { printf '%s' "${CLAUDE_TQ_STATE_DIR:-$HOME/.claude/state/task-queue}"; }
tq_cache_file()   { printf '%s/project-cache.tsv' "$(tq_state_dir)"; }

# ---- helpers ----------------------------------------------------------------

# Portable mtime (seconds). GNU stat then BSD/macOS stat then 0.
tq_mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf '0'
}

# A cwd -> project label: the git repo ROOT's basename. Falls back to the cwd's
# own basename when the session didn't run inside a repo (or the path is gone).
tq_label_for_cwd() {
  local cwd="$1" top dir
  # Ask git directly when the directory still exists on disk.
  top="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [ -n "$top" ]; then basename "$top"; return 0; fi
  # git unavailable or dir gone: walk up looking for a .git entry on disk.
  dir="$cwd"
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    [ -e "$dir/.git" ] && { basename "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  # Not in a repo: the cwd's own basename.
  basename "$cwd"
}

# session id -> short project label (the cwd's basename). Cached, since a
# session's cwd never changes. Unresolved sessions return "?" and are NOT
# cached (their transcript may appear later).
tq_project_label() {
  local sid="$1" cache label transcript cwd pdir f
  cache="$(tq_cache_file)"

  if [ -f "$cache" ]; then
    label="$(awk -F'\t' -v s="$sid" '$1==s {print $2; exit}' "$cache" 2>/dev/null || true)"
    [ -n "$label" ] && { printf '%s' "$label"; return 0; }
  fi

  pdir="$(tq_projects_dir)"
  transcript=""
  for f in "$pdir"/*/"$sid.jsonl"; do
    [ -f "$f" ] && { transcript="$f"; break; }
  done

  if [ -n "$transcript" ]; then
    # cwd appears on early transcript lines; scan the first few and take one.
    cwd="$(head -n 40 "$transcript" 2>/dev/null | jq -r 'select(.cwd != null) | .cwd' 2>/dev/null | head -n1 || true)"
    if [ -n "$cwd" ]; then
      label="$(tq_label_for_cwd "$cwd")"
    else
      label="$(basename "$(dirname "$transcript")")"
    fi
  else
    label="?"
  fi

  if [ "$label" != "?" ] && [ -n "$label" ]; then
    mkdir -p "$(tq_state_dir)" 2>/dev/null || true
    printf '%s\t%s\n' "$sid" "$label" >> "$cache" 2>/dev/null || true
  fi
  printf '%s' "${label:-?}"
}

# Emit one TSV row per native task across ALL sessions/projects:
#   label <TAB> status <TAB> mtime <TAB> subject
# (jq's @tsv escapes any embedded tab/newline, so each task stays on one line.)
tq_tasks_tsv() {
  local tdir sdir sid f row status subject mtime label
  tdir="$(tq_tasks_dir)"
  [ -d "$tdir" ] || return 0

  for sdir in "$tdir"/*/; do
    [ -d "$sdir" ] || continue
    # Skip session dirs with no task files at all (cheap pre-check).
    local has=0
    for f in "$sdir"*.json; do [ -f "$f" ] && { has=1; break; }; done
    [ "$has" -eq 1 ] || continue

    sid="$(basename "$sdir")"
    label="$(tq_project_label "$sid")"

    for f in "$sdir"*.json; do
      [ -f "$f" ] || continue
      row="$(jq -r '[(.status // "pending"), (.subject // "")] | @tsv' "$f" 2>/dev/null || true)"
      [ -z "$row" ] && continue
      status="${row%%$'\t'*}"
      subject="${row#*$'\t'}"
      mtime="$(tq_mtime "$f")"
      printf '%s\t%s\t%s\t%s\n' "$label" "$status" "$mtime" "$subject"
    done
  done
}

# ---- renderers --------------------------------------------------------------

# One-line status: open work across all projects + the most-recent doing task.
# Done is intentionally omitted (lifetime-cumulative = noise). Prints nothing
# when there is no open work anywhere, so the status line stays clean.
#   ⚑ 3 proj · 7 todo · 2 doing — ▶ "Wire engine" [task-queue]
tq_status_line() {
  tq_tasks_tsv | awk -F'\t' '
    {
      label=$1; status=$2; mtime=$3+0; subject=$4
      if (status=="pending")      { todo++;  openproj[label]=1 }
      else if (status=="in_progress") {
        doing++; openproj[label]=1
        if (mtime >= bestm) { bestm=mtime; bestsubj=subject; bestlabel=label }
      }
    }
    END {
      if (todo+doing == 0) exit 0
      np=0; for (k in openproj) np++
      line = "⚑ " np " proj · " todo " todo"
      if (doing > 0) line = line " · " doing " doing"
      if (bestsubj != "") {
        s=bestsubj
        if (length(s) > 30) s=substr(s,1,29) "…"
        line = line " — ▶ \"" s "\" [" bestlabel "]"
      }
      print line
    }
  '
}

# Full grouped table for a terminal (zero-token). One block per project with
# open work: a counts header (incl. done as a number) then the open tasks,
# doing-first. Completed tasks are counted but not listed (keeps it bounded).
tq_list_table() {
  local any
  any="$(tq_tasks_tsv | awk -F'\t' -v OFS='\t' '
            { pr=($2=="in_progress"?0:($2=="pending"?1:2)); print $1,pr,$2,$4 }' \
        | LC_ALL=C sort -t"$(printf '\t')" -k1,1 -k2,2n \
        | awk -F'\t' '
            function flush() {
              if (cur=="") return
              printf "%s  ·  %d todo · %d doing · %d done\n", cur, tt, dd, cc
              for (i=0; i<olen; i++) print "  " openline[i]
            }
            {
              if ($1 != cur) { flush(); cur=$1; tt=0; dd=0; cc=0; olen=0 }
              if ($3=="pending")          { tt++; openline[olen++]="▢ " $4 }
              else if ($3=="in_progress") { dd++; openline[olen++]="▶ " $4 }
              else                        { cc++ }
            }
            END { flush() }
          ')"

  if [ -z "$any" ]; then
    printf 'No tasks found. (Claude populates these via its native task tools as it works.)\n'
    return 0
  fi
  printf '%s\n' "$any"
}
