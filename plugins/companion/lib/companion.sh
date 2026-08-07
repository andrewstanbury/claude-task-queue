#!/usr/bin/env bash
# Shared helpers for the persisted per-repo autopilot flag + the companion task store — sourced by
# bin/autopilot.sh, the Stop hook, the ask-guard, session-start/resume, and the status line. (One
# plugin, so a shared lib is fine; the encoding MUST be identical across readers — that's why it
# lives here.)

companion_state_dir() { printf '%s' "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}"; }

# Injective encoding of a repo root into one filename component (escape % first, then /),
# so two distinct roots never collide to the same flag file.
companion_enc() { printf '%s' "${1:-}" | sed -e 's:%:%25:g' -e 's:/:%2F:g'; }

# cwd (or a path) -> repo root, git toplevel or the path itself.
companion_root() { git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${1:-$PWD}"; }
# Repo IDENTITY — a per-WORKING-TREE id that survives a MOVE but stays distinct across worktrees,
# clones, and forks. It's a random tag stored inside the working tree's own git dir at
# `git rev-parse --git-path companion-repo-id` — which routes per-worktree (a linked worktree gets
# its own), moves WITH the tree on a rename (so scoping follows a moved repo), and is absent in a
# fresh clone (so clones/forks don't inherit each other's queue). This is deliberately NOT the
# root-commit SHA: that identifies *history*, so worktrees/clones/forks would collide and MERGE
# their queues (R63 — a devil's-advocate catch). Falls back to the abspath for a non-git dir.
# Created on first access (read or write) so every reader and the `tq` writer agree on one id.
companion_repo_id() { local d="${1:-$PWD}" f id
  f="$(git -C "$d" rev-parse --git-path companion-repo-id 2>/dev/null)" || true
  if [ -z "$f" ]; then companion_root "$d"; return; fi
  case "$f" in /*) : ;; *) f="$d/$f" ;; esac                 # --git-path is relative to $d unless linked-worktree (absolute)
  if [ -f "$f" ]; then cat "$f"; return; fi
  id="$(head -c16 /dev/urandom 2>/dev/null | od -An -tx1 2>/dev/null | tr -d ' \n\r')"
  if [ -z "$id" ]; then id="p$$"; fi
  printf '%s' "$id" > "$f" 2>/dev/null || true
  printf '%s' "$id"; }

# REWORK LEDGER (R94). Counts FAILURE events, never touch counts: a file touched three times is
# just work, while a file implicated in three failed gates or red CI runs is genuinely troublesome.
# That distinction was measured, not assumed — a file-churn metric on this repo ranked version
# manifests, the queue and LESSONS at the top, i.e. pure ceremony, and would have fired constantly.
# One append per event: `<epoch> <label> <file>`. Best-effort; a failure to record never blocks.
# The ledger is REPO state (R96 stage 3): a defect rate that resets with the container measures
# nothing. Legacy events stay readable so the count does not silently drop to zero on upgrade.
companion_rework_file() { printf '%s/.companion/rework' "${1:-}"; }
companion_rework_legacy() { printf '%s/rework/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_rework_record() {  # $1 root · $2 label · $3.. files
  local f root="${1:-}" label="${2:-}"; shift 2 2>/dev/null || return 0
  if [ -z "$root" ] || [ -z "$label" ]; then return 0; fi
  f="$(companion_rework_file "$root")"
  mkdir -p "${f%/*}" 2>/dev/null || return 0
  local now; now="$(date +%s 2>/dev/null || echo 0)"
  for p in "$@"; do
    [ -n "$p" ] || continue
    printf '%s %s %s\n' "$now" "$label" "$p" >> "$f" 2>/dev/null || return 0
  done
  return 0
}

# Record an event against the files in play. `$3` empty = working tree vs HEAD (a failed gate);
# `$3` = a ref means that commit's files (a red CI, where the tree is already clean).
companion_rework_from_diff() {  # $1 root · $2 label · $3 ref|""
  local files
  if [ -n "${3:-}" ]; then
    files="$(git -C "$1" show --name-only --pretty=format: "$3" 2>/dev/null | grep -v '^$' | head -20)"
  else
    files="$(git -C "$1" diff --name-only HEAD 2>/dev/null | head -20)"
  fi
  # shellcheck disable=SC2086
  if [ -n "$files" ]; then companion_rework_record "$1" "$2" $files
  else companion_rework_record "$1" "$2" "-"; fi
}

# MODE FLAGS ARE REPO STATE (R96). They used to live under $HOME keyed by an encoded repo path,
# which made every mode machine-bound: a fresh container or a cloud agent starts with autopilot,
# ship, sweep, decisive and burndown all OFF and no way to inherit any of it. A mode is a fact about
# the REPO ("autopilot is on for this project"), so it travels with the repo. The encoded-path key
# disappears with the move — there is nothing left to disambiguate.
#
# READ falls back to the legacy home-scoped flag so an existing install does not silently lose its
# modes on upgrade; CLEAR removes BOTH, or a legacy flag would keep resurrecting a mode the owner
# turned off. Writers only ever create the repo-scoped one.
companion_mode_flag()   { printf '%s/.companion/modes/%s' "${1:-}" "${2:-}"; }
companion_mode_legacy() { printf '%s/%s/%s' "$(companion_state_dir)" "${2:-}" "$(companion_enc "${1:-}")"; }
companion_mode_on() {
  [ -n "${1:-}" ] || return 1
  [ -f "$(companion_mode_flag "$1" "$2")" ] && return 0
  [ -f "$(companion_mode_legacy "$1" "$2")" ]
}
# DUAL-WRITE during the transition, and this is not belt-and-braces — it is structural. The CLI is
# run from the REPO while hooks are served from the installed CACHE, so writer and reader are
# routinely DIFFERENT VERSIONS of this plugin. New code reads the legacy flag, but old code cannot
# read the new one, so writing only the repo flag left `autopilot on` reporting ON while the
# installed Stop hook saw OFF and stood down every turn. Measured on the owner's machine: the queue
# had work, the CLI said armed, and nothing ever ran. Drop the legacy write once the floor version
# is past the move.
companion_mode_set() {
  [ -n "${1:-}" ] || return 1
  local f g; f="$(companion_mode_flag "$1" "$2")"; g="$(companion_mode_legacy "$1" "$2")"
  mkdir -p "${f%/*}" 2>/dev/null || return 1
  : > "$f" 2>/dev/null || return 1
  mkdir -p "${g%/*}" 2>/dev/null && : > "$g" 2>/dev/null
  return 0
}
companion_mode_clear() {
  [ -n "${1:-}" ] || return 0
  rm -f "$(companion_mode_flag "$1" "$2")" "$(companion_mode_legacy "$1" "$2")" 2>/dev/null || true
}

companion_autopilot_flag() { companion_mode_flag "${1:-}" autopilot; }
companion_autopilot_on() { companion_mode_on "${1:-}" autopilot; }
# Clear the flag (single source of truth — autopilot.sh `off` and resume.sh both use this so the
# teardown can't drift). Best-effort; a missing flag is not an error.
companion_autopilot_clear() { companion_mode_clear "${1:-}" autopilot; }

# Ship-mode (R34): while autopilot is ON, the Stop hook auto-COMMITS accumulated work to a
# non-default branch (never main, never a push) so completed work is captured as reversible
# checkpoints for the owner to review + `/companion:ship-it`.
companion_ship_flag() { companion_mode_flag "${1:-}" ship; }
companion_ship_on() { companion_mode_on "${1:-}" ship; }

# Decisive mode (R59): while autopilot is ON, instead of PARKING every decision, autopilot
# auto-picks its own recommended option for **reversible** choices (design/wording/direction
# included — overrides R33), records each pick, and keeps going; it still parks (❓) / blocks (⏳)
# only the irreversible / externally-binding / data-destructive. Opt-in, per-repo, persisted; the
# safety is the audit trail (every auto-pick is a `tq note`), read back by /companion:review.
companion_decisive_flag() { companion_mode_flag "${1:-}" decisive; }
companion_decisive_on() { companion_mode_on "${1:-}" decisive; }

# SWEEP mode (R77) — decisive, but reaching BACKWARDS into the pile that is already parked.
# Decisive stops new reversible decisions from being parked; sweep additionally stops the drain
# treating a ❓-only queue as finished, so an unattended run works the existing options-parks using
# each one's recorded `rec:`. Deliberately narrow in code: the ENFORCED part is only "don't stop".
# WHICH parks are safe stays judgment (STEERING) — a park may exist precisely because it is
# irreversible, and those must never be auto-applied; they get reclassified ⏳ so the loop ends.
# `⏳` blocked and `decompose:` parks (R65) are NEVER eligible, in any mode.
companion_sweep_flag() { companion_mode_flag "${1:-}" sweep; }
companion_sweep_on() { companion_mode_on "${1:-}" sweep; }

# PAUSED-FOR-REVIEW marker. `/companion:review` has to ask questions, and the ask-guard blocks
# those while autopilot is armed — so a review must disarm it. Turning it permanently OFF made the
# owner re-arm by hand every time, which is why review became something you avoided running.
# `pause` records that autopilot WAS on; `resume` puts it back. The marker is a file, so a crash
# mid-review leaves a recoverable state rather than a silently-disarmed one.
# An explicit `autopilot off` CLEARS this marker — an owner saying "off" outranks a pending resume.
companion_autopilot_paused_flag() { companion_mode_flag "${1:-}" autopilot-paused; }
companion_autopilot_paused()      { [ -n "${1:-}" ] && [ -f "$(companion_autopilot_paused_flag "$1")" ]; }

# BURN-DOWN mode — opt-in, per-repo, OFF by default. When the 7d rate-limit window is forecast to
# end UNDERSPENT and there is no queued work left, autopilot may generate candidate work rather
# than idle. Everything it produces lands behind a feature flag on a branch; nothing merges.
# Deliberately its own flag, not a mode of autopilot: this is the only mode that AUTHORS work, so
# turning it on must be a separate, explicit act.
companion_burndown_flag() { companion_mode_flag "${1:-}" burndown; }
companion_burndown_on() { companion_mode_on "${1:-}" burndown; }

# Where the status line drops its rate-limit snapshot. The window data arrives ONLY on the
# statusLine stdin payload, so anything outside that process (like the burn-down forecaster) can
# read it only if the status line writes it down. One short line, overwritten in place.
companion_rl_snapshot() { printf '%s/ratelimit' "$(companion_state_dir)"; }

# Per-repo feature OFF flags (R50) — a single per-repo file storing only OFF overrides, one
# `<feature>=off` line each. Absence of a line ⇒ the feature's default (secret/steering
# default ON). Read by every enforced-core reader (session-start steering, statusline shield);
# env var (CLAUDE_COMPANION_SECSCAN) stays as a *global* override that wins, so a per-repo flag
# never fights CI. autopilot/ship keep their own flag files (their commands own that state).
# NOTE: the self-contained hook (secret-guard.sh) MUST NOT source this lib — it
# reads the file with an inline grep instead; keep that path/encoding in sync with companion_enc.
# The `/companion:features` CLI writer was removed 2026-07-18 (R50 amended); the flag mechanism +
# its readers remain (settable by hand or a future re-add), so no reader's behavior changed.
companion_feature_file()  { printf '%s/features/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
# 0 (true) only when the feature is *explicitly* turned off for this repo — fail-safe: any read
# error leaves the feature at its default (on), never silently disables an enforced gate.
companion_feature_off()   { [ -n "${2:-}" ] && grep -qs "^${1:-}=off\$" "$(companion_feature_file "$2")"; }

# The high-confidence, vendor-anchored credential shapes (~zero false positive). Ship-mode greps
# a staged diff against this before committing, so it never bakes a real key into a checkpoint.
# NOTE: `bin/secret-guard.sh` keeps its OWN inline copy on purpose (the enforced gate stays
# self-contained — no `lib` dependency that could make it fail open). Keep the two in sync.
companion_secret_re() { printf '%s' 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'; }

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
_COMPANION_TASK_RENDER='select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "") + (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end) + (if (.context//"")!="" then "\n       └ context: " + .context else "" end) + (if ((.notes//[])|length)>0 then "\n       └ note: " + ((.notes[-1].text)//"") elif (.description//"")!="" then "\n       └ note: " + .description else "" end)'

# NOTE: $1 must be a RESOLVED root (what companion_root returns). The `.root` stamps are written
# resolved, so passing an unresolved path — e.g. $PWD after cd-ing through a symlink, which stays
# logical — compares apples to oranges and silently matches NOTHING. Every shipped caller already
# goes through companion_root; a test that did not spent a while looking like a product bug.
companion_open_tasks() {
  local root="$1" store d id rid rroot f out; local -a files=(); local -a stores=()
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
