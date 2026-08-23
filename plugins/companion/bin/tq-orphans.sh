#!/usr/bin/env bash
# tq-orphans — ORPHANED STATE reporting for the companion's state dir. Extracted from `tq` at its
# 300-line cap, the same move as ci-watch.sh / da-gate.sh / mutate-gate.sh: this is a
# DIAGNOSTIC over what is on disk, not queue mechanics, so it is the cohesion-correct seam rather
# than the biggest block. It already had its own tests, which retarget here unchanged.
#
#   tq-orphans.sh              report state kinds no shipped code builds a path to
#   tq-orphans.sh --orphans    remove them
#
# Reached as `tq orphans [--orphans]`, which `exec`s this so the exit code is tq's own.
set -uo pipefail

# ORPHANED STATE (owner-decided 2026-08-05). Deleting a feature used to leave its state directory
# behind forever: `captures/`, `review/`, `intent-*` and `reminded-*` all outlived the code that
# wrote them, and the only way to know they were dead was to grep the source by hand.
#
# The legitimate kinds are DERIVED FROM THE SHIPPED SOURCE, never listed here — a hardcoded list
# is a second thing to update whenever a state kind is added, which is the drift this repo keeps
# deleting. Anything on disk that no shipped code builds a path to is reported.
#
# REPORT by default, remove only with --orphans. Automatically deleting data whose purpose is
# unknown is precisely the operation that should stay deliberate.

  plug="$(cd "$(dirname "$0")/.." && pwd)"   # same bin/, so ../ is still the plugin root
  sd="${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}"
  [ -d "$sd" ] || { echo "tq orphans: no state dir at $sd"; exit 0; }
  # [a-z0-9-] — DIGITS INCLUDED, and that is not cosmetic. The class was [a-z-], so a kind whose
  # name contains a digit derived TRUNCATED at the digit: `slcache2` yielded "slcache", the real
  # directory matched nothing known, and it was reported as an orphan — which `--orphans` deletes
  # with `rm -rf`. A latent data-loss path that stayed invisible for as long as no state kind had a
  # digit in its name, and surfaced the moment one did (R117 renamed the status-line cache).
  known="$( { grep -rhoE "printf '%s/[a-z0-9-]+" "$plug/lib" "$plug/bin" 2>/dev/null | sed "s|.*/||"
              grep -rhoE 'companion_state_dir\)/[a-z0-9-]+' "$plug/lib" "$plug/bin" 2>/dev/null | sed 's|.*/||'
              grep -rhoE 'companion_mode_[a-z]+ "[^"]*" [a-z0-9-]+' "$plug/lib" "$plug/bin" 2>/dev/null | awk '{print $NF}'
              printf 'tasks\n'
            } | sort -u )"
  [ -n "$known" ] || { echo "tq orphans: derived NO known kinds — refusing to call anything an orphan" >&2; exit 1; }
  found=0
  for e in "$sd"/*; do
    [ -e "$e" ] || continue
    name="${e##*/}"
    printf '%s\n' "$known" | grep -qx "$name" && continue
    found=$((found+1))
    if [ "${1:-}" = "--orphans" ]; then rm -rf "$e" 2>/dev/null && echo "  removed $name" || echo "  FAILED to remove $name"
    else echo "  orphan: $name"; fi
  done
  if [ "$found" -eq 0 ]; then echo "tq orphans: none — every state kind on disk is built by shipped code"
  elif [ "${1:-}" = "--orphans" ]; then echo "tq orphans: removed $found"
  else echo "tq orphans: $found orphaned state kind(s); re-run with --orphans to remove"; fi