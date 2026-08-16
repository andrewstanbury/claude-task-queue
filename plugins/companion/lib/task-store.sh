#!/usr/bin/env bash
# task-store.sh — WHERE THE QUEUE LIVES and HOW IT IS SCOPED TO A REPO. Split out of companion.sh
# 2026-08-16 (audit), when that file sat at exactly 300/300 and three separate comment-trims had
# been spent staying under the cap — the cheapest way to pass a line limit is to delete rationale,
# which is the opposite of what the limit is for.
#
# THE SEAM IS COHESION, not line count (the same rule tq/tq-output.sh was split on): everything here
# answers "which task files belong to this repo, and how do they render". companion.sh keeps state
# paths, flag encoding, repo identity and the mode flags. The one place the two meet is repo
# IDENTITY, which this file consumes and does not define.
#
# SOURCED BY companion.sh, deliberately, rather than by each caller: seven scripts source
# companion.sh today and every one of them needs at least part of this. Making them all source a
# second file would be a rename dressed as a refactor, and would break any out-of-tree caller.
# `bin/tq` still sources NEITHER — it is standalone by design and mirrors this logic on purpose.
set -uo pipefail

# The companion's own task store (not native tasks).
# THE QUEUE IS REPO STATE (R96 stage 2). The queue IS the product, so a cloud agent that starts
# with an empty one has nothing to drain — the same machine-bound problem the mode flags had.
# An explicit CLAUDE_COMPANION_TASKS_DIR still wins ABSOLUTELY: it is how every test isolates, and
# how anyone with a custom location keeps it. Otherwise the repo store is used.
companion_tasks_dir() {  # $1 repo root (optional)
  if [ -n "${CLAUDE_COMPANION_TASKS_DIR:-}" ]; then printf '%s' "$CLAUDE_COMPANION_TASKS_DIR"; return 0; fi
  if [ -n "${1:-}" ] && [ -d "${1:-}" ]; then printf '%s/.companion/tasks' "$1"; return 0; fi
  printf '%s' "$HOME/.claude/companion/tasks"
}
# The repo store is FLAT — one id space per repo, no session subdirectory (owner-decided
# 2026-08-04). Session partitioning made sense when the store was GLOBAL and shared across every
# project; inside a repo it partitions something that is conceptually one queue, and it was the
# reason a clone could carry tasks that its own drain could not see: report and stopfields read one
# session directory, and a fresh container always has a new session id.
#
# An explicit CLAUDE_COMPANION_TASKS_DIR keeps its session subdirectory: that is a GLOBAL store by
# definition, so it still needs partitioning, and it is how the suite isolates.
# A session already living in the legacy home store keeps working there — upgrading must never
# orphan an in-flight queue.
companion_session_dir() {  # $1 repo root · $2 session id
  local store legacy
  store="$(companion_tasks_dir "${1:-}")"
  legacy="$HOME/.claude/companion/tasks/${2:-}"
  if [ -n "${CLAUDE_COMPANION_TASKS_DIR:-}" ]; then printf '%s/%s' "$store" "${2:-}"; return 0; fi
  # A session ALREADY LIVING in the legacy store never migrates mid-flight — otherwise its queue
  # would SPLIT, with old tasks in one store and new ones in another. New sessions use the repo.
  if [ -d "$legacy" ]; then printf '%s' "$legacy"; return 0; fi
  if [ -n "${1:-}" ] && [ -d "${1:-}" ]; then printf '%s' "$store"; return 0; fi
  printf '%s' "$legacy"
}

# Open (pending/in_progress) task subjects for a repo, across every session dir whose `.root`
# stamp matches — the cross-session resume signal. One "  ◻ <subject>" line each; empty when
# none. Shared by the SessionStart hook (auto-resume) and `bin/resume.sh` (manual).
# The one render program, shared by the batched pass and its per-file fallback so the two can
# never drift into printing different things for the same task.
# `▸` in_progress vs `◻` pending — NOT decoration: these rendered identically, so a task a crashed
# session left MID-FLIGHT returned looking exactly like one never started. `tq`'s own delta glyphs.
_COMPANION_TASK_RENDER='select(.status=="pending" or .status=="in_progress") | (if .status=="in_progress" then "  ▸ " else "  ◻ " end) + (.subject // "") + (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end) + (if (.context//"")!="" then "\n       └ context: " + .context else "" end) + (if ((.notes//[])|length)>0 then "\n       └ note: " + ((.notes[-1].text)//"") elif (.description//"")!="" then "\n       └ note: " + .description else "" end)'

# NOTE: $1 must be a RESOLVED root (what companion_root returns). The `.root` stamps are written
# resolved, so passing an unresolved path — e.g. $PWD after cd-ing through a symlink, which stays
# logical — compares apples to oranges and silently matches NOTHING. Every shipped caller already
# goes through companion_root; a test that did not spent a while looking like a product bug.
# companion_task_files ROOT -> scoped task-file paths, NUL-separated. Extracted so every reader
# scopes IDENTICALLY — a second hand-rolled scan is how cross-repo bleed gets reintroduced. NUL,
# not newline: the line-based first draft rendered the ENTIRE backlog as zero tasks when a store
# path contained one — the corrupt-file total-loss shape below, on the same crash-resume path.
companion_task_files() {
  local root="$1" store d id rid rroot; local -a files=(); local -a stores=()
  # Two stores now: the repo's own (R96 stage 2 — every session in it belongs to this repo by
  # construction, so no stamp is needed) and the legacy home one, still stamp-matched so an
  # in-flight queue from before the move is not orphaned. Duplicates cannot arise: a session lives
  # in exactly one of them.
  store="$(companion_tasks_dir "$root")"; [ -d "$store" ] && stores+=("$store")
  if [ -z "${CLAUDE_COMPANION_TASKS_DIR:-}" ] && [ -d "$HOME/.claude/companion/tasks" ]; then
    stores+=("$HOME/.claude/companion/tasks")
  fi
  [ "${#stores[@]}" -gt 0 ] || return 0
  id="$(companion_repo_id "$root")"
  local repostore scoped; repostore="$(companion_tasks_dir "$root")"
  for store in "${stores[@]}"; do
  # The repo's own store needs no stamp check — everything in it belongs to this repo. The legacy
  # home store is shared across every project, so it still must be matched.
  # Unscoped ONLY when the store is genuinely repo-derived. With CLAUDE_COMPANION_TASKS_DIR set the
  # same path serves every repo, so skipping the stamp check there let sessions bleed ACROSS repos —
  # caught by the isolation tests, and exactly the cross-project bleed this store is scoped to stop.
  scoped=1
  if [ -z "${CLAUDE_COMPANION_TASKS_DIR:-}" ] && [ "$store" = "$repostore" ]; then scoped=0; fi
  # The repo store is FLAT, so its tasks sit directly in it rather than under a session directory.
  if [ "$scoped" -eq 0 ]; then
    set -- "$store"/*.json
    [ -f "$1" ] && files+=("$@")
    continue
  fi
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    # Marker files are read with the `read` BUILTIN, not `$(cat …)`: this runs on SessionStart and
    # every compaction, and two forks per session directory was 82 spawns on a real store. `read`
    # returns 1 on a final line with no newline, so check the variable, not the status.
    rid=""; rroot=""
    [ -f "$d.repo" ] && { IFS= read -r rid  < "$d.repo"  || true; }
    [ -f "$d.root" ] && { IFS= read -r rroot < "$d.root" || true; }
    # Match on repo IDENTITY (path-stable) first, else the legacy abspath stamp (back-compat).
    if [ "$scoped" -eq 1 ]; then
      { [ "$rid" = "$id" ] || [ "$rroot" = "$root" ]; } || continue
    fi
    set -- "$d"*.json
    [ -f "$1" ] || continue
    files+=("$@")
  done
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  printf '%s\0' "${files[@]}"
}

companion_open_tasks() {
  local root="$1" f out; local -a files=()
  while IFS= read -r -d '' f; do [ -n "$f" ] && files+=("$f"); done < <(companion_task_files "$root")
  [ "${#files[@]}" -gt 0 ] || return 0
  # ONE jq for every matching file across every matching directory. It used to spawn a jq PER FILE:
  # 265 spawns / 818ms on a real store, growing with every session and task, on a hook path. Glob
  # order is preserved so the rendered list is byte-identical to the per-file version.
  #
  # FALLBACK IS LOAD-BEARING, not defensive padding: jq ABORTS at the first unparseable file, so a
  # single corrupt task file would take every task in every LATER file down with it — measured
  # 7 open tasks rendering as 0, silently, exit 0, on the one path whose entire job is to hand the
  # backlog back after a crash. (R44's atomic writes make a half-written file rare, not impossible;
  # The deleted queue-export learned this exact lesson first — "one corrupt file skipped, never
  # zeroes the backlog".) So: try the fast batch, and the moment jq reports failure, redo it
  # per-file so a bad file costs only itself. The slow path runs only when something is already
  # broken, so the hot path keeps its 56x.
  if out="$(jq -r "$_COMPANION_TASK_RENDER" "${files[@]}" 2>/dev/null)"; then
    [ -n "$out" ] && printf '%s\n' "$out"
    return 0
  fi
  for f in "${files[@]}"; do
    [ -f "$f" ] || continue
    jq -r "$_COMPANION_TASK_RENDER" "$f" 2>/dev/null || true
  done
}
