#!/usr/bin/env bash
# ship-checkpoint.sh (R100/Pass 4) — the one piece of the retired stop-autopilot.sh with standalone
# value once "force continuation" itself is gone: ship-mode's commit-to-a-throwaway-branch logic.
# Was automatic (fired on every Stop while ship-mode + autopilot were both on); now it's a CLI the
# model calls itself at a natural stopping point, if ship-mode is on. Same guarantees, same code,
# just no trigger left to fire it for you — that's the accepted cost of R100, not a fix for it.
#
# Captures the CURRENT uncommitted work as a reversible COMMIT on a non-default branch — never the
# default branch, never a push. Silent no-op if ship-mode is off, the tree is clean, or the repo has
# no commits yet. Best-effort: nothing here may fail loudly enough to look like a bigger problem
# than an uncommitted checkpoint.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

cwd="$PWD"
root="$(companion_root "$cwd")"
companion_ship_on "$root" || { echo "ship-mode is off — nothing to checkpoint (companion:autopilot ship on to enable)"; exit 0; }
[ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ] || { echo "clean tree — nothing to checkpoint"; exit 0; }
git -C "$cwd" rev-parse HEAD >/dev/null 2>&1 || { echo "no commits yet — nothing to checkpoint onto"; exit 0; }

def="$(git -C "$cwd" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')"
[ -n "$def" ] || def="$(git -C "$cwd" config --get init.defaultBranch 2>/dev/null)"; [ -n "$def" ] || def="main"
cur="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$cur" in "$def"|main|master|HEAD|"")                                # protect the default branch
  git -C "$cwd" checkout -q -b "autopilot/$(date +%Y%m%d-%H%M%S)" 2>/dev/null || { echo "could not create a checkpoint branch"; exit 1; } ;;
esac
cur="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$cur" in "$def"|main|master|HEAD|"") echo "refused: still on the default branch"; exit 1 ;; esac  # NEVER commit to default

git -C "$cwd" add -A 2>/dev/null || true
# Don't bake a real credential into a checkpoint (this `git add` isn't seen by check-secrets.sh,
# which only scans on explicit request now — R100 — so this stays as its own backstop).
if git -C "$cwd" diff --cached 2>/dev/null | grep -qE "$(companion_secret_re)"; then
  git -C "$cwd" reset -q 2>/dev/null || true
  echo "refused: staged diff has a high-confidence credential shape — resolve it before checkpointing"
  exit 2
fi
# Use the repo's own identity if configured; else a companion fallback (these throwaway checkpoints
# get squashed under the owner's identity on /companion:ship-it). Without this the commit fails
# wherever git identity isn't set (CI, a fresh machine) — silently capturing nothing.
if git -C "$cwd" commit -q -m "autopilot: checkpoint on $cur" 2>/dev/null \
  || git -C "$cwd" -c user.name='companion (autopilot)' -c user.email='autopilot@companion.local' \
         commit -q -m "autopilot: checkpoint on $cur" 2>/dev/null; then
  echo "checkpointed to $cur"
else
  echo "commit failed"; exit 1
fi
