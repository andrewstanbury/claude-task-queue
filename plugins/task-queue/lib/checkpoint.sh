#!/usr/bin/env bash
# task-queue — support lib: crash checkpoint (working-tree snapshots, no history).
#
# Opt-in, per-repo. When enabled, tq-checkpoint.sh (wired on PostToolUse) snapshots
# the working tree — tracked AND untracked, .gitignore honored — into a single hidden
# ref (refs/tq/checkpoint) using a throwaway index, so the owner's HEAD, index,
# working tree and branch history are NEVER touched and the ref is never pushed.
# A machine crash → restore the lost edits from the ref. This is the one hook that
# writes to git, hence opt-in (the read-only invariant is a deliberate exception here).
#
# Sourced by bin/tq-checkpoint.sh and bin/tq-resume.sh.

set -uo pipefail

# Per-repo enable flag (same scheme as agent/away).
tq_ckpt_dir()      { printf '%s' "${CLAUDE_TQ_CKPT_DIR:-$HOME/.claude/state/task-queue/checkpoint}"; }
tq_ckpt_file()     { printf '%s/%s' "$(tq_ckpt_dir)" "$(printf '%s' "$1" | sed 's:/:-:g')"; }
# Armed when this repo has an explicit opt-in flag, OR the global default is on
# (CLAUDE_TQ_CHECKPOINT_MODE=on|1 — set once in settings.json env to arm every repo
# without a per-repo decision, mirroring CLAUDE_TQ_AGENT_MODE). Off by default
# otherwise, so the read-only invariant holds for anyone who never opts in. A flag
# whose content is the literal "off" is a TOMBSTONE: it lets /task-queue:checkpoint
# turn a single repo off even when the global default would otherwise arm it.
tq_ckpt_enabled()  {
  [ -n "${1:-}" ] || return 1
  local f; f="$(tq_ckpt_file "$1")"
  if [ -f "$f" ]; then [ "$(cat "$f" 2>/dev/null || true)" != "off" ]; return; fi
  case "${CLAUDE_TQ_CHECKPOINT_MODE:-}" in on|1) return 0 ;; esac
  return 1
}

# The hidden ref the snapshot lands on. Under refs/tq/ (not refs/heads|tags), so it's
# invisible to log/branch and excluded from a normal push.
tq_ckpt_ref() { printf 'refs/tq/checkpoint'; }

# Does a checkpoint currently exist for this repo? (a ref we can restore from)
tq_ckpt_exists() {
  local root="$1"
  [ -n "$root" ] || return 1
  git -C "$root" rev-parse -q --verify "$(tq_ckpt_ref)" >/dev/null 2>&1
}

# The exact command the owner runs to recover lost edits after a crash.
tq_ckpt_restore_cmd() {
  printf 'git restore --source=%s --worktree -- .' "$(tq_ckpt_ref)"
}

# Snapshot the working tree of $root into the checkpoint ref. No-op (return 0) when
# checkpoint is disabled, $root isn't a git repo, nothing changed since the last
# snapshot, or any git step fails — best-effort, never breaks the edit that triggered
# it. Captures tracked+untracked via a temp index; leaves HEAD/index/worktree intact.
tq_ckpt_save() {
  local root="$1"
  tq_ckpt_enabled "$root" || return 0
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || return 0

  local ref head tree prev commit tmpidx
  ref="$(tq_ckpt_ref)"
  head="$(git -C "$root" rev-parse -q --verify HEAD 2>/dev/null || true)"
  tmpidx="$(mktemp 2>/dev/null)" || return 0

  # Build a full tree from HEAD + every working-tree change, in a throwaway index.
  if [ -n "$head" ]; then
    GIT_INDEX_FILE="$tmpidx" git -C "$root" read-tree "$head" 2>/dev/null || { rm -f "$tmpidx"; return 0; }
  fi
  GIT_INDEX_FILE="$tmpidx" git -C "$root" add -A 2>/dev/null || { rm -f "$tmpidx"; return 0; }
  tree="$(GIT_INDEX_FILE="$tmpidx" git -C "$root" write-tree 2>/dev/null || true)"
  rm -f "$tmpidx"
  [ -n "$tree" ] || return 0

  # Skip when the snapshot tree is identical to the last checkpoint's — no churn.
  prev="$(git -C "$root" rev-parse -q --verify "$ref^{tree}" 2>/dev/null || true)"
  [ "$tree" = "$prev" ] && return 0

  # commit-tree with HEAD as parent (or parentless on an unborn branch). Provide a
  # fallback identity so it works in repos with no user.name/email configured.
  local -a idre=(GIT_AUTHOR_NAME=task-queue GIT_AUTHOR_EMAIL=task-queue@localhost \
                 GIT_COMMITTER_NAME=task-queue GIT_COMMITTER_EMAIL=task-queue@localhost)
  if [ -n "$head" ]; then
    commit="$(printf 'tq checkpoint' | env "${idre[@]}" git -C "$root" commit-tree "$tree" -p "$head" 2>/dev/null || true)"
  else
    commit="$(printf 'tq checkpoint' | env "${idre[@]}" git -C "$root" commit-tree "$tree" 2>/dev/null || true)"
  fi
  [ -n "$commit" ] || return 0
  git -C "$root" update-ref "$ref" "$commit" 2>/dev/null || true
}
