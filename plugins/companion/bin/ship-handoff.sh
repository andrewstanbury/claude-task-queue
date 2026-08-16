#!/usr/bin/env bash
# ship-handoff.sh — PARK UNFINISHED WORK FOR ANOTHER MACHINE (R72). Split out of ship.sh 2026-08-16
# when the size gate warned it was at 296/300.
#
# THE SEAM IS THE GOAL, not the line count. ship.sh takes VERIFIED work to shipped: it re-runs the
# gate, refuses staged credentials, commits, ff-merges to the default branch, pushes, and watches
# CI. Handoff does almost the opposite — it takes UNFINISHED work and parks it on a `wip/*` branch
# so another machine can pick it up. No gate runs, because the whole point is that the work is not
# done yet; the gate fires later, at ship. The two shared exactly `die` and `default_branch`, which
# is a poor reason to live in one file.
#
# What travels with it, unchanged, because each is a recorded incident:
#   · detached HEAD is refused (exit 9) · no remote is refused (exit 8 — git IS the transport)
#   · mode flags are UNSTAGED after `git add -A` (R96·b: a review pause deleted the autopilot flag,
#     got committed as "autopilot off", and silently disarmed it later)
#   · a staged credential shape is refused before anything is pushed
#   · on the DEFAULT branch the checkpoint moves to `wip/<stamp>` — WIP never lands on default
# ship.sh — the deterministic rail under /companion:ship-it (R71).
#
# ship-it's judgment steps (the case, devil's-advocate, contract-impact naming, flow-page
# proposal, commit MESSAGE, history curation) stay with Claude; this script executes only the
# mechanical spine those steps sandwich, collapsing ~8-12 model round-trips into two calls:
#
#   ship.sh preflight [gate-cmd...]      verify gate -> drift backstop -> summary
#   ship.sh land -F <msgfile> [--da <finding>] [--prune-all] [--gate <cmd>]
#                                        re-verify -> stage -> commit -> ff-only merge to the
#                                        default branch -> push -> prune the shipped branch
#
# NOT a hook (R68 binds hooks, not command tools) — but its spirit shapes the guards: this is
# the biggest-blast script in bin/, so every unexpected state BAILS LOUDLY and hands back to
# Claude instead of improvising. Never `-D`, never the default branch as a delete target, never
# force, never a non-ff merge (curation is judgment — hand it back, exit 7).
#
# Exit codes (distinct so the caller can route the handback):
#   0 ok · 2 usage · 3 no gate found · 4 gate failed · 5 not a git repo · 6 nothing to commit
#   7 merge is not fast-forward (curate/rebase, then retry) · 8 push failed (local state is
#   committed+merged — safe, report it) · 9 refused an unsafe state (detached HEAD, staged
#   secret, delete-guard) · 11 no --da on a declared critical path (R78) · 12 shipped, CI unwatched
set -uo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../lib/companion.sh
. "$here/../lib/companion.sh"

die() { code="$1"; shift; printf 'ship.sh: %s\n' "$*" >&2; exit "$code"; }

command -v git >/dev/null 2>&1 || die 5 "git not found"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die 5 "not a git repository"
cd "$root" || die 5 "cannot cd to repo root"

# Default branch — remote HEAD, else config, else main/master — but ALWAYS verified to exist as
# a local branch: this rail merges INTO the result, so a wrong guess must fail here, not at
# checkout. (stop-autopilot.sh guesses looser on purpose — there over-matching is the safe side.)
default_branch() {
  local def
  for def in \
    "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's@^origin/@@')" \
    "$(git config --get init.defaultBranch 2>/dev/null)" main master; do
    [ -n "$def" ] && git rev-parse --verify -q "refs/heads/$def" >/dev/null && { printf '%s' "$def"; return 0; }
  done
  return 1
}

# Gate resolution: explicit args win; else the repo's own ./check.sh; else the companion-generated
# home (R64). Anything else (make test, npm test, ...) is the MODEL's recognition job (R9) — it
# passes the command in; the rail never guesses frameworks.

handoff() {
  local cur def branch
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$cur" ] || [ "$cur" = "HEAD" ]; then die 9 "detached HEAD — check out a branch first"; fi
  git remote get-url origin >/dev/null 2>&1 || die 8 "no remote — git is the transport (R72); add one first"
  git add -A
  # A ship must never SNAPSHOT live mode state (R96·b). Mode flags are files in the repo, so
  # `git add -A` was recording whatever happened to be set at that instant — a review pause, which
  # deletes the autopilot flag, got committed as "autopilot off" and silently disarmed it later.
  # Unstaging leaves any DELIBERATELY committed mode intact while dropping the transient churn.
  git reset -q -- .companion/modes 2>/dev/null || true
  git diff --cached --quiet && die 6 "nothing to hand off (clean tree, no changes)"
  if git diff --cached | grep -qE "$(companion_secret_re)"; then
    die 9 "staged diff matches a credential shape — unstage the secret before handing off"
  fi
  def="$(default_branch)" || def=""
  if [ -n "$def" ] && [ "$cur" = "$def" ]; then
    branch="wip/$(date -u +%Y%m%d-%H%M%S)"                 # WIP never lands on default (R34-spirit)
    git checkout -qb "$branch" || die 9 "cannot create $branch"   # staged changes ride the checkout
    cur="$branch"
  fi
  git commit -q -m "wip: handoff checkpoint (working tree + queue, R72)" || die 9 "commit failed"
  git push -qu origin "$cur" || die 8 "push failed — checkpoint is safe locally; resolve and push"
  printf '== ship.sh: handed off %s on %s\n' "$(git rev-parse --short HEAD)" "$cur"
  printf '== on the other machine: git fetch && git checkout %s && /companion:resume\n' "$cur"
}

case "${1:-}" in
  handoff|"") handoff ;;
  *) die 2 "usage: ship-handoff.sh handoff" ;;
esac
