#!/usr/bin/env bash
# Shared helpers for the persisted per-repo autopilot flag + the companion task store — sourced by
# autopilot.sh, board.sh, burn-down.sh, candidates.sh, burndown-branch.sh, rework.sh, ship.sh,
# ship-checkpoint.sh, resume.sh, prompt-continue.sh, and the status line. (One plugin, so a shared
# lib is fine; the encoding MUST be identical across readers — that's why it lives here.)

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

# Ship-mode (R34): while autopilot is ON, work is captured as reversible checkpoints on a
# non-default branch (never main, never a push) for the owner to review + `/companion:ship-it`.
# NOT automatic — the Stop hook's auto-commit was retired and `bin/ship-checkpoint.sh` owns it,
# invoked deliberately; a lib comment claiming otherwise is how the R100 passes got misread.
companion_ship_on() { companion_mode_on "${1:-}" ship; }

# Decisive mode (R59): while autopilot is ON, instead of PARKING every decision, autopilot
# auto-picks its own recommended option for **reversible** choices (design/wording/direction
# included — overrides R33), records each pick, and keeps going; it still parks (❓) / blocks (⏳)
# only the irreversible / externally-binding / data-destructive. Opt-in, per-repo, persisted; the
# safety is the audit trail (every auto-pick is a `tq note`), read back by /companion:review.
companion_decisive_on() { companion_mode_on "${1:-}" decisive; }

# SWEEP mode (R77) — decisive, but reaching BACKWARDS into the pile that is already parked.
# Decisive stops new reversible decisions from being parked; sweep additionally stops the drain
# treating a ❓-only queue as finished, so an unattended run works the existing options-parks using
# each one's recorded `rec:`. Deliberately narrow in code: the ENFORCED part is only "don't stop".
# WHICH parks are safe stays judgment (STEERING) — a park may exist precisely because it is
# irreversible, and those must never be auto-applied; they get reclassified ⏳ so the loop ends.
# `⏳` blocked and `decompose:` parks (R65) are NEVER eligible, in any mode.
companion_sweep_on() { companion_mode_on "${1:-}" sweep; }

# PAUSED-FOR-REVIEW marker. `/companion:review` has to ask questions, and the ask-guard blocks
# those while autopilot is armed — so a review must disarm it. Turning it permanently OFF made the
# owner re-arm by hand every time, which is why review became something you avoided running.
# `pause` records that autopilot WAS on; `resume` puts it back. The marker is a file, so a crash
# mid-review leaves a recoverable state rather than a silently-disarmed one.
# An explicit `autopilot off` CLEARS this marker — an owner saying "off" outranks a pending resume.
companion_autopilot_paused_flag() { companion_mode_flag "${1:-}" autopilot-paused; }

# BURN-DOWN mode — opt-in, per-repo, OFF by default. When the 7d rate-limit window is forecast to
# end UNDERSPENT and there is no queued work left, autopilot may generate candidate work rather
# than idle. Everything it produces lands behind a feature flag on a branch; nothing merges.
# Deliberately its own flag, not a mode of autopilot: this is the only mode that AUTHORS work, so
# turning it on must be a separate, explicit act.
companion_burndown_on() { companion_mode_on "${1:-}" burndown; }

# Where the status line drops its rate-limit snapshot. The window data arrives ONLY on the
# statusLine stdin payload, so anything outside that process (like the burn-down forecaster) can
# read it only if the status line writes it down. One short line, overwritten in place.
companion_rl_snapshot() { printf '%s/ratelimit' "$(companion_state_dir)"; }

# Per-repo feature OFF flags (R50) — a single per-repo file storing only OFF overrides, one
# `<feature>=off` line each. Absence of a line ⇒ the feature's default (secret/steering
# default ON). Read by every enforced-core reader (resume's steering print, statusline shield);
# env var (CLAUDE_COMPANION_SECSCAN) stays as a *global* override that wins, so a per-repo flag
# never fights CI. autopilot/ship keep their own flag files (their commands own that state).
# NOTE: the self-contained scanner (bin/check-secrets.sh, advisory since R100/Pass 3 — was the
# enforced secret-guard.sh hook) MUST NOT source this lib — it reads the file with an inline grep
# instead; keep that path/encoding in sync with companion_enc.
# The `/companion:features` CLI writer was removed 2026-07-18 (R50 amended); the flag mechanism +
# its readers remain (settable by hand or a future re-add), so no reader's behavior changed.
companion_feature_file()  { printf '%s/features/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
# 0 (true) only when the feature is *explicitly* turned off for this repo — fail-safe: any read
# error leaves the feature at its default (on), never silently disables an enforced gate.
companion_feature_off()   { [ -n "${2:-}" ] && grep -qs "^${1:-}=off\$" "$(companion_feature_file "$2")"; }
# THE default branch, in one place (R117). There were three copies before this — ship.sh,
# ship-handoff.sh (byte-identical) and burndown-branch.sh (NOT: it returns "main" unconditionally
# without verifying the ref exists, so on a `master` repo with no origin/HEAD it answers a branch
# that is not there while ship.sh answers correctly). A fourth copy was about to be written for
# awaiting-review.sh, which is what surfaced the drift. Carries ship.sh's semantics because they
# are the stricter ones: a candidate only wins if the ref actually EXISTS, and no candidate means
# failure (return 1), never a confident guess.
companion_default_branch() {  # $1 root (default $PWD)
  local d r="${1:-$PWD}"
  for d in \
    "$(git -C "$r" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')" \
    "$(git -C "$r" config --get init.defaultBranch 2>/dev/null)" main master; do
    [ -n "$d" ] && git -C "$r" rev-parse --verify -q "refs/heads/$d" >/dev/null 2>&1 &&
      { printf '%s' "$d"; return 0; }
  done
  return 1
}


# The high-confidence, vendor-anchored credential shapes (~zero false positive). Ship-mode greps
# a staged diff against this before committing, so it never bakes a real key into a checkpoint.
# NOTE: `bin/check-secrets.sh` keeps its OWN inline copy on purpose (stays self-contained, no
# `lib` dependency — R100/Pass 3: advisory now, but still no reason to add a failure mode). Keep
# the two in sync.
companion_secret_re() { printf '%s' 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'; }


# The task-store half lives in lib/task-store.sh (split 2026-08-16 — see its header). Sourced HERE
# rather than by each caller so every existing `. companion.sh` keeps working unchanged; a split
# that forces seven callers to learn a new file name is a rename, not a decomposition.
# Resolved from THIS file's own location, following symlinks, because callers source us by many
# different relative paths.
_COMPANION_SELF="${BASH_SOURCE[0]}"
while [ -L "$_COMPANION_SELF" ]; do
  _l="$(readlink "$_COMPANION_SELF")"
  case "$_l" in /*) _COMPANION_SELF="$_l" ;; *) _COMPANION_SELF="$(dirname "$_COMPANION_SELF")/$_l" ;; esac
done
# shellcheck source=./task-store.sh
. "$(cd "$(dirname "$_COMPANION_SELF")" && pwd)/task-store.sh"

# companion_is_feature_class <newline-separated changed paths> -> 0 when the change is USER-VISIBLE.
#
# ONE BIT, DERIVED FROM THE CONTRACT (owner-decided 2026-08-20, adr R116). The alternative on the
# table was a task-level taxonomy — feature / NFR / spec / chore — set by hand on each task. That was
# declined for a specific reason: this repo already carries needs -> requirements -> tests, and a
# second classification is a second thing to keep in sync. Every drift defect found in the
# 2026-08-16 audit had that shape. A hand-set level also cannot be verified, and its likeliest use is
# to justify a LOWER bar ("just a chore") — erosion the uniform rule prevents today.
#
# So the class comes from a signal the project ALREADY maintains: a `docs/flows/<flow>.md` page
# documents what the user can DO (R58), so touching one alongside implementation means behaviour
# changed. It cannot rot, because it IS the contract.
#
# GENERIC, no extension allowlist (R9). "Implementation" is simply a changed path OUTSIDE the docs
# tree and outside the plugin's own state dir — the flow page describes the behaviour, anything else
# that moved with it is the thing doing it. Naming languages here would be the exact violation this
# file polices elsewhere.
#
# Deliberately NOT feature-class: a docs-only edit (a typo in a flow page is not a release), a
# code-only change (a fix that alters no documented behaviour), and queue/mode churn under
# `.companion/`. False positives cost the owner a branch; false negatives ship behaviour with no
# review gate, so where it is uncertain this errs toward calling it a feature.
companion_is_feature_class() {
  local changed="${1:-}"
  [ -n "$changed" ] || return 1
  printf '%s\n' "$changed" | grep -qE '^docs/flows/[^/]+\.md$' || return 1
  printf '%s\n' "$changed" | grep -qvE '^(docs/|\.companion/)' || return 1
  return 0
}
