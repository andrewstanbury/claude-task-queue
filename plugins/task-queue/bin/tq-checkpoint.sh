#!/usr/bin/env bash
# tq-checkpoint — arm/disarm the crash checkpoint for this repo, and take snapshots.
#
#   bash bin/tq-checkpoint.sh on       # arm: auto-snapshot the working tree as work happens
#   bash bin/tq-checkpoint.sh off      # disarm (default)
#   bash bin/tq-checkpoint.sh status   # print "on" or "off"
#   bash bin/tq-checkpoint.sh now      # take one snapshot now (no-op if disarmed) — the hook path
#
# The toggle (on|off|status) is run by the model on request ("checkpoint my work" /
# "stop checkpointing"). `now` is what the PostToolUse hook calls after each edit; it
# reads the repo from the hook's stdin JSON (cwd), falling back to $PWD, and no-ops
# silently when disarmed or outside a git repo — a best-effort hook must never break
# the edit that triggered it.
#
# Snapshots land on a hidden ref (refs/tq/checkpoint), NOT on your branch — history
# stays clean and nothing is pushed. Restore lost edits after a crash with:
#   git restore --source=refs/tq/checkpoint --worktree -- .

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/checkpoint.sh
. "$PLUGIN_DIR/lib/checkpoint.sh"

action="${1:-status}"

# `now` (hook path): resolve the repo from stdin JSON cwd, else $PWD; snapshot; done.
# Fast exit FIRST — this runs on every edit, so when NO repo is armed (the default for
# everyone who never enabled it) skip before spending a git subprocess to resolve the
# root. A single cheap dir listing gates the whole per-edit cost.
if [ "$action" = "now" ]; then
  # Fast exit before spending a git subprocess: nothing armed anywhere AND no global
  # default. CLAUDE_TQ_CHECKPOINT_MODE must override the empty-dir short-circuit, else
  # a global-default-armed repo with no per-repo flag would silently never snapshot.
  case "${CLAUDE_TQ_CHECKPOINT_MODE:-}" in
    on|1) : ;;
    *) [ -n "$(ls -A "$(tq_ckpt_dir)" 2>/dev/null)" ] || exit 0 ;;   # nothing armed → done
  esac
  input=""; [ -t 0 ] || input="$(cat 2>/dev/null || true)"
  cwd=""
  [ -n "$input" ] && cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  [ -n "$cwd" ] || cwd="$PWD"
  tq_ckpt_save "$(tq_root_for_cwd "$cwd")" 2>/dev/null || true
  exit 0
fi

root="$(tq_root_for_cwd "$PWD")"
flag="$(tq_ckpt_file "$root")"

# `toggle` (the /task-queue:checkpoint command) flips based on the current state.
[ "$action" = "toggle" ] && { tq_ckpt_enabled "$root" && action="off" || action="on"; }

case "$action" in
  on|enable)
    mkdir -p "$(tq_ckpt_dir)" 2>/dev/null || true
    : > "$flag"
    printf 'Checkpoint ON — your edits are auto-saved for %s so a crash cannot lose them (recover with /task-queue:resume, or: %s).\n' \
      "$root" "$(tq_ckpt_restore_cmd)"
    ;;
  off|disable)
    mkdir -p "$(tq_ckpt_dir)" 2>/dev/null || true
    printf 'off' > "$flag" 2>/dev/null || true      # tombstone: sticks even under a global default
    printf 'Checkpoint OFF for %s (the last saved snapshot, if any, is left in place).\n' "$root"
    ;;
  status)
    if tq_ckpt_enabled "$root"; then printf 'on (%s)\n' "$root"
    else printf 'off (%s)\n' "$root"; fi
    ;;
  restore)
    if ! tq_ckpt_exists "$root"; then
      printf 'no checkpoint to restore for %s (nothing was snapshotted)\n' "$root"; exit 0
    fi
    # Overlay the checkpoint onto the working tree. The ref is left untouched, so a
    # restore is idempotent and re-runnable (do NOT re-snapshot here — that would
    # overwrite the single ref with the current, possibly-lost, tree).
    if git -C "$root" restore --source="$(tq_ckpt_ref)" --worktree -- . 2>/dev/null; then
      printf 'restored working tree from %s for %s\n' "$(tq_ckpt_ref)" "$root"
    else
      printf 'restore failed for %s — recover manually with: %s\n' "$root" "$(tq_ckpt_restore_cmd)" >&2
      exit 1
    fi
    ;;
  *)
    printf 'usage: tq-checkpoint.sh on|off|toggle|status|now|restore\n' >&2
    exit 2
    ;;
esac
