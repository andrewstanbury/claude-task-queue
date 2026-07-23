#!/usr/bin/env bash
# ship.sh — the deterministic rail under /companion:ship-it (R71).
#
# ship-it's judgment steps (the case, devil's-advocate, contract-impact naming, flow-page
# proposal, commit MESSAGE, history curation) stay with Claude; this script executes only the
# mechanical spine those steps sandwich, collapsing ~8-12 model round-trips into two calls:
#
#   ship.sh preflight [gate-cmd...]      verify gate -> drift backstop -> tq export -> summary
#   ship.sh land -F <msgfile> [--gate <cmd>] [--prune-all]
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
#   secret, delete-guard)
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
resolve_gate() {
  if [ "$#" -gt 0 ]; then printf '%s\n' "$@"; return 0; fi
  if [ -x ./check.sh ]; then printf '%s\n' ./check.sh; return 0; fi
  if [ -x .companion/check.sh ]; then printf '%s\n' .companion/check.sh; return 0; fi
  return 1
}

run_gate() { # $@ = gate command
  printf '== ship.sh: gate: %s\n' "$*"
  "$@" || die 4 "gate FAILED — do not ship; fix and retry"
}

# Bash-3.2-safe (macOS CI): read resolve_gate's one-arg-per-line output into an array with a
# plain read loop — the bash-4-only array builtins are banned by a bats regression guard.
# Empty array = no gate found.
read_gate() { gate=(); while IFS= read -r _g; do gate+=("$_g"); done < <(resolve_gate "$@"); }

preflight() {
  local gate cur def
  read_gate "$@"
  [ "${#gate[@]}" -gt 0 ] || die 3 "no gate found — pass one: ship.sh preflight <cmd...>"
  run_gate "${gate[@]}"
  printf '== ship.sh: contract-drift backstop\n'
  "$here/contract-drift.sh" || true                     # advisory by design (R58)
  printf '== ship.sh: queue export (R60)\n'
  "$here/tq" export || printf 'ship.sh: warn: tq export failed (continuing — export is auxiliary)\n' >&2
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || printf 'HEAD')"
  def="$(default_branch)" || def="(undetermined)"
  printf '== ship.sh: summary\n'
  printf 'branch: %s   default: %s   ' "$cur" "$def"
  git rev-parse --abbrev-ref --symbolic-full-name '@{u}' >/dev/null 2>&1 \
    && printf 'upstream: %s (ahead %s, behind %s)\n' \
         "$(git rev-parse --abbrev-ref --symbolic-full-name '@{u}')" \
         "$(git rev-list --count '@{u}..HEAD' 2>/dev/null || printf '?')" \
         "$(git rev-list --count 'HEAD..@{u}' 2>/dev/null || printf '?')" \
    || printf 'upstream: (none)\n'
  git status --short
  git diff --stat
  printf '== ship.sh: preflight OK\n'
}

land() {
  local msgfile="" prune_all=0 gate_cmd=() gate cur def had_remote=0
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -F) shift; msgfile="${1:-}"; shift || true ;;
      # --gate slurps EVERYTHING after it as the gate command+args, so a multi-word gate
      # (`--gate make test`) works the same as preflight's trailing varargs — no per-flag
      # asymmetry. It must therefore come LAST (after -F / --prune-all).
      --gate) shift; while [ "$#" -gt 0 ]; do gate_cmd+=("$1"); shift; done ;;
      --prune-all) prune_all=1; shift ;;
      *) die 2 "unknown argument: $1" ;;
    esac
  done
  if [ -z "$msgfile" ] || [ ! -s "$msgfile" ]; then die 2 "land requires -F <non-empty message file>"; fi

  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$cur" ] || [ "$cur" = "HEAD" ]; then die 9 "detached HEAD — check out a branch first"; fi
  def="$(default_branch)" || die 9 "cannot determine the default branch (no remote HEAD / config / main / master)"

  # Re-run the gate on the exact tree being shipped (contract-doc edits staged since preflight
  # can themselves fail the gate — byte caps, drift refs — so this re-run is not optional).
  read_gate ${gate_cmd[@]+"${gate_cmd[@]}"}
  [ "${#gate[@]}" -gt 0 ] || die 3 "no gate found — pass one: --gate <cmd>"
  run_gate "${gate[@]}"

  git add -A
  if git diff --cached --quiet; then
    # Nothing staged. That's fine IF unmerged commits already exist (the retry path: a previous
    # land bailed after committing, or the owner curated commits by hand) — proceed to merge.
    if [ "$cur" != "$def" ] && [ "$(git rev-list --count "$def..HEAD" 2>/dev/null || printf 0)" -gt 0 ]; then
      printf '== ship.sh: nothing staged; shipping the %s existing commit(s) on %s\n' \
        "$(git rev-list --count "$def..HEAD")" "$cur"
    else
      die 6 "nothing to commit"
    fi
  else
    # Staged-secret backstop — same anchored shapes as ship-mode (lib). A rail that pushes must
    # never be the thing that publishes a key.
    if git diff --cached | grep -qE "$(companion_secret_re)"; then
      die 9 "staged diff matches a credential shape — unstage the secret before shipping"
    fi
    git commit -F "$msgfile" || die 9 "commit failed"
    printf '== ship.sh: committed %s on %s\n' "$(git rev-parse --short HEAD)" "$cur"
  fi

  git remote get-url origin >/dev/null 2>&1 && had_remote=1

  if [ "$cur" = "$def" ]; then
    if [ "$had_remote" -eq 1 ]; then
      git push -u origin "$def" || die 8 "push failed — commit is safe locally; resolve and push"
    else
      printf '== ship.sh: no remote — nothing pushed\n'
    fi
  else
    git checkout -q "$def" || die 9 "cannot check out $def"
    if ! git merge --ff-only -q "$cur"; then
      git checkout -q "$cur" || true
      die 7 "merge $cur -> $def is not fast-forward — curate/rebase (judgment), then retry"
    fi
    printf '== ship.sh: merged %s -> %s (ff)\n' "$cur" "$def"
    if [ "$had_remote" -eq 1 ]; then
      git push -u origin "$def" || die 8 "push failed — merge is safe locally; resolve and push"
    else
      printf '== ship.sh: no remote — nothing pushed\n'
    fi
    # Prune the shipped branch: remote copy first, then `fetch --prune`, THEN local `-d` — while
    # a remote-tracking ref lives, -d refuses ("not merged to its upstream") even though the
    # ff-merge just landed it. -d ONLY (never -D); never the default (this arm is cur != def);
    # a refusal is a warn, never an abort.
    if [ "$had_remote" -eq 1 ] && git ls-remote --exit-code --heads origin "$cur" >/dev/null 2>&1; then
      git push origin --delete "$cur" \
        && printf '== ship.sh: deleted remote branch %s\n' "$cur" \
        || printf 'ship.sh: warn: could not delete remote %s (continuing)\n' "$cur" >&2
      git fetch --prune --quiet 2>/dev/null || true
    fi
    git branch -d "$cur" >/dev/null 2>&1 \
      && printf '== ship.sh: deleted local branch %s\n' "$cur" \
      || printf 'ship.sh: warn: could not -d local branch %s (left in place)\n' "$cur" >&2
  fi

  # Merged-branch sweep (R35): DEFAULT IS LIST-ONLY — deleting other branches needs the owner's
  # confirm in shared repos, and that confirm is judgment. --prune-all executes after it.
  local sweep
  sweep="$(git branch --merged "$def" --format='%(refname:short)' | grep -vxE "$def" || true)"
  if [ -n "$sweep" ]; then
    if [ "$prune_all" -eq 1 ]; then
      printf '%s\n' "$sweep" | while IFS= read -r b; do
        [ -n "$b" ] && [ "$b" != "$def" ] && git branch -d "$b" && printf '== ship.sh: pruned %s\n' "$b"
      done
      [ "$had_remote" -eq 1 ] && git fetch --prune --quiet 2>/dev/null
    else
      printf '== ship.sh: merged branches (list-only; confirm with owner, then --prune-all):\n%s\n' "$sweep"
    fi
  fi
  printf '== ship.sh: shipped %s on %s\n' "$(git rev-parse --short "$def")" "$def"
}

# Cross-machine handoff (R72): checkpoint the WIP + queue for another machine — NOT a ship.
# The gate is deliberately not run (a red tree mid-work is normal; the gate fires at `land`),
# but the secret backstop still is: this pushes.
handoff() {
  local cur def branch
  cur="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$cur" ] || [ "$cur" = "HEAD" ]; then die 9 "detached HEAD — check out a branch first"; fi
  git remote get-url origin >/dev/null 2>&1 || die 8 "no remote — git is the transport (R72); add one first"
  printf '== ship.sh: queue export (R60)\n'
  "$here/tq" export || printf 'ship.sh: warn: tq export failed (continuing)\n' >&2
  git add -A
  git diff --cached --quiet && die 6 "nothing to hand off (clean tree, no queue delta)"
  # A FRESH, EMPTY queue export in an otherwise-clean tree is noise, not a handoff — without this
  # guard, "nothing to hand off" is unreachable in any repo that never used the queue.
  if [ "$(git diff --cached --name-only)" = ".companion/queue.json" ] \
     && ! git rev-parse -q --verify HEAD:.companion/queue.json >/dev/null 2>&1 \
     && [ "$(jq -r 'if type=="array" then length else (.tasks|length) end' .companion/queue.json 2>/dev/null || echo 1)" = "0" ]; then
    git reset -q; rm -f .companion/queue.json
    die 6 "nothing to hand off (clean tree, empty queue)"
  fi
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
  preflight) shift; preflight "$@" ;;
  land)      shift; land "$@" ;;
  handoff)   shift; handoff "$@" ;;
  *) die 2 "usage: ship.sh preflight [gate-cmd...] | ship.sh land -F <msgfile> [--gate <cmd>] [--prune-all] | ship.sh handoff" ;;
esac
