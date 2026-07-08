#!/usr/bin/env bash
# tq-ship — take completed work from the working tree to merged-on-main in one gated
# step. Backs /task-queue:ship-it. This is DETERMINISTIC GIT PLUMBING ONLY; the CALLER
# (the model, per commands/ship-it.md) MUST have VERIFIED the work is green first — a
# bash script can't know an arbitrary repo's test command, so the green gate lives
# with the caller, not here. The mechanical, repeatable part:
#   on default branch? -> branch. uncommitted? -> commit. push -> PR -> squash-merge
#   --delete-branch -> sync default. Stops and reports on the first failure, and never
#   leaves the default branch dirty. If the remote blocks the merge (branch protection
#   / required checks), that is the REMOTE gate — it reports and leaves the PR open.
#
# Usage: tq-ship.sh --title "..." [--body "..."] [--branch name]
# Requires: git, gh (GitHub CLI, authenticated), a remote named origin.
set -uo pipefail

title=""; body=""; branch=""
while [ $# -gt 0 ]; do
  case "$1" in
    --title)  title="${2:-}"; shift 2 ;;
    --body)   body="${2:-}";  shift 2 ;;
    --branch) branch="${2:-}"; shift 2 ;;
    *) printf 'tq-ship: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
done

die() { printf 'tq-ship: %s\n' "$1" >&2; exit 1; }

command -v git >/dev/null 2>&1 || die "git not found"
command -v gh  >/dev/null 2>&1 || die "the GitHub CLI (gh) is not installed/authenticated — cannot open or merge a PR"
root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository"
cd "$root" || die "cannot cd to repo root"
git remote get-url origin >/dev/null 2>&1 || die "no 'origin' remote to push to"

cur="$(git rev-parse --abbrev-ref HEAD)"
default_branch="$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's:^origin/::')"
[ -n "$default_branch" ] || default_branch="main"

# Dirty = staged, unstaged, or untracked.
dirty=0
git diff --quiet && git diff --cached --quiet || dirty=1
[ -n "$(git ls-files --others --exclude-standard)" ] && dirty=1

# 1. Branch — never commit straight onto the default branch; move work onto a feature
#    branch first. If already on one, keep it.
if [ "$cur" = "$default_branch" ]; then
  [ "$dirty" -eq 1 ] || die "on $default_branch with a clean tree — nothing to ship"
  [ -n "$branch" ] || branch="ship/$(date +%Y%m%d-%H%M%S)"
  git checkout -q -b "$branch" || die "could not create branch $branch"
  cur="$branch"
fi

# 2. Commit any pending work (title required if there is something to commit).
if [ "$dirty" -eq 1 ]; then
  [ -n "$title" ] || die "there are uncommitted changes but no --title for the commit"
  git add -A || die "git add failed"
  msg="$title"
  [ -n "$body" ] && msg="$title"$'\n\n'"$body"
  msg="$msg"$'\n\n'"Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>"
  git commit -q -m "$msg" || die "git commit failed"
fi

# Refuse a no-op ship (branch has nothing the default branch doesn't already have).
ahead="$(git rev-list --count "origin/$default_branch..HEAD" 2>/dev/null || echo 0)"
[ "${ahead:-0}" -ge 1 ] || die "no commits ahead of $default_branch — nothing to ship"

# 3. Push.
git push -q -u origin "$cur" || die "git push failed"

# 4. PR — reuse an existing one for this branch, else create it.
pr="$(gh pr view "$cur" --json number --jq '.number' 2>/dev/null || true)"
if [ -z "$pr" ]; then
  if [ -n "$title" ]; then
    gh pr create --base "$default_branch" --head "$cur" --title "$title" --body "${body:-$title}" >/dev/null \
      || die "gh pr create failed"
  else
    gh pr create --base "$default_branch" --head "$cur" --fill >/dev/null || die "gh pr create failed"
  fi
  pr="$(gh pr view "$cur" --json number --jq '.number' 2>/dev/null || true)"
fi
[ -n "$pr" ] || die "could not determine the PR number after creating it"

# 5. Squash-merge + delete the branch. gh refuses when required checks are pending or
#    failing — that is the remote's gate, not an error to paper over: report and stop
#    with the PR left open (branch NOT deleted).
merge_err="$(mktemp)"
if ! gh pr merge "$pr" --squash --delete-branch 2>"$merge_err"; then
  err="$(cat "$merge_err" 2>/dev/null)"; rm -f "$merge_err"
  printf 'tq-ship: PR #%s is open and pushed, but the merge did not complete:\n%s\nBranch NOT deleted. Merge once checks pass: gh pr merge %s --squash --delete-branch\n' \
    "$pr" "$err" "$pr" >&2
  exit 1
fi
rm -f "$merge_err"

# 6. Sync the local default branch so the working copy reflects the merge.
# Best-effort: never let a checkout/pull failure break the ship (SC2015-safe).
if git checkout -q "$default_branch" 2>/dev/null; then
  git pull -q --ff-only origin "$default_branch" 2>/dev/null || true
fi

printf 'tq-ship: PR #%s squash-merged into %s and the branch was deleted. Local %s synced.\n' \
  "$pr" "$default_branch" "$default_branch"
