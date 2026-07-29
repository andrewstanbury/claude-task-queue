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

companion_autopilot_flag() { printf '%s/autopilot/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_autopilot_on()   { [ -n "${1:-}" ] && [ -f "$(companion_autopilot_flag "$1")" ]; }
# Clear the flag (single source of truth — autopilot.sh `off` and resume.sh both use this so the
# teardown can't drift). Best-effort; a missing flag is not an error.
companion_autopilot_clear() { rm -f "$(companion_autopilot_flag "${1:-}")" 2>/dev/null || true; }

# Ship-mode (R34): while autopilot is ON, the Stop hook auto-COMMITS accumulated work to a
# non-default branch (never main, never a push) so completed work is captured as reversible
# checkpoints for the owner to review + `/companion:ship-it`.
companion_ship_flag() { printf '%s/ship/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_ship_on()   { [ -n "${1:-}" ] && [ -f "$(companion_ship_flag "$1")" ]; }

# Decisive mode (R59): while autopilot is ON, instead of PARKING every decision, autopilot
# auto-picks its own recommended option for **reversible** choices (design/wording/direction
# included — overrides R33), records each pick, and keeps going; it still parks (❓) / blocks (⏳)
# only the irreversible / externally-binding / data-destructive. Opt-in, per-repo, persisted; the
# safety is the audit trail (every auto-pick is a `tq note`), read back by /companion:review.
companion_decisive_flag() { printf '%s/decisive/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_decisive_on()   { [ -n "${1:-}" ] && [ -f "$(companion_decisive_flag "$1")" ]; }

# SWEEP mode (R77) — decisive, but reaching BACKWARDS into the pile that is already parked.
# Decisive stops new reversible decisions from being parked; sweep additionally stops the drain
# treating a ❓-only queue as finished, so an unattended run works the existing options-parks using
# each one's recorded `rec:`. Deliberately narrow in code: the ENFORCED part is only "don't stop".
# WHICH parks are safe stays judgment (STEERING) — a park may exist precisely because it is
# irreversible, and those must never be auto-applied; they get reclassified ⏳ so the loop ends.
# `⏳` blocked and `decompose:` parks (R65) are NEVER eligible, in any mode.
companion_sweep_flag()    { printf '%s/sweep/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_sweep_on()      { [ -n "${1:-}" ] && [ -f "$(companion_sweep_flag "$1")" ]; }

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
companion_tasks_dir() { printf '%s' "${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}"; }

# Open (pending/in_progress) task subjects for a repo, across every session dir whose `.root`
# stamp matches — the cross-session resume signal. One "  ◻ <subject>" line each; empty when
# none. Shared by the SessionStart hook (auto-resume) and `bin/resume.sh` (manual).
# The one render program, shared by the batched pass and its per-file fallback so the two can
# never drift into printing different things for the same task.
_COMPANION_TASK_RENDER='select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "") + (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end) + (if ((.notes//[])|length)>0 then "\n       └ note: " + ((.notes[-1].text)//"") elif (.description//"")!="" then "\n       └ note: " + .description else "" end)'

companion_open_tasks() {
  local root="$1" store d id rid rroot f out; local -a files=()
  store="$(companion_tasks_dir)"; [ -d "$store" ] || return 0
  id="$(companion_repo_id "$root")"
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    # Marker files are read with the `read` BUILTIN, not `$(cat …)`: this runs on SessionStart and
    # every compaction, and two forks per session directory was 82 spawns on a real store. `read`
    # returns 1 on a final line with no newline, so check the variable, not the status.
    rid=""; rroot=""
    [ -f "$d.repo" ] && { IFS= read -r rid  < "$d.repo"  || true; }
    [ -f "$d.root" ] && { IFS= read -r rroot < "$d.root" || true; }
    # Match on repo IDENTITY (path-stable) first, else the legacy abspath stamp (back-compat).
    { [ "$rid" = "$id" ] || [ "$rroot" = "$root" ]; } || continue
    set -- "$d"*.json
    [ -f "$1" ] || continue
    files+=("$@")
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
  # `tq export` already learned this exact lesson — "one corrupt file skipped-with-count, never
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
