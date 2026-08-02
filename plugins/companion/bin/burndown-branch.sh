#!/usr/bin/env bash
# burndown-branch.sh — the container for autonomously-generated work. It does not write features;
# it guarantees that whatever does can be thrown away without argument.
#
# Every guarantee here is structural, not advisory:
#   · work happens on `burndown/<slug>`, created from the default branch, never ON it
#   · it never pushes and never merges — reviewing is a human act, so it stays one
#   · a manifest is written BEFORE any work, so a branch can never exist without a stated reason,
#     the flag that hides it, how to try it, and how to delete it
#   · `discard` removes branch and manifest in one command, because "cheap to discard" is only
#     true if discarding is genuinely one step
#
# THE FLAG IS DECLARED HERE, IMPLEMENTED IN THE PROJECT'S OWN IDIOM. This plugin cannot know how
# your project does feature flags (env var, config key, build tag, LaunchDarkly) and guessing would
# be worse than useless — so the manifest NAMES the flag and states that it must default to off,
# and the implementing agent honours that in whatever way the project already does it (R9).
#
#   start "<rank>|<source>|<text>"   create the branch + manifest, print the slug
#   list                             every unreviewed branch with its reason
#   show <slug>                      one manifest
#   discard <slug>                   delete the branch and its manifest
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${BURNDOWN_ROOT:-$PWD}")"
# OUTSIDE the repo, deliberately. A manifest committed to the burndown branch disappears the
# moment you check out the default branch — which is exactly when you want to read it. Keeping it
# in the state dir also means reviewing generates no diff and discarding leaves no trace.
#
# `burndown-manifests`, NOT `burndown`: the mode's ON flag is a FILE at $STATE/burndown/<enc>, and
# this was a DIRECTORY at the identical path. Armed — the only state the mode can actually run in —
# `mkdir` failed, no manifest was written, and `start` still exited 0 with a branch created. The
# feature's headline guarantee was void on every real run, and the tests missed it because they
# never armed the flag in the same state dir. Separate namespaces so the two can never collide.
MANIFEST_DIR="$(companion_state_dir)/burndown-manifests/$(companion_enc "$root")"

die() { printf 'burndown-branch: %s\n' "$1" >&2; exit "${2:-2}"; }

default_branch() {
  local d
  d="$(git -C "$root" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)"
  d="${d#origin/}"
  [ -n "$d" ] || d="$(git -C "$root" config --get init.defaultBranch 2>/dev/null)"
  [ -n "$d" ] || d=main
  printf '%s' "$d"
}

# A slug reaches the filesystem as "$MANIFEST_DIR/$slug.md" and git as "burndown/$slug", so it is
# untrusted input on both. `slugify` produces safe values, but `discard`/`show` take a slug the
# CALLER supplies — and `discard '../../victim'` deleted a file outside the state dir entirely.
# Validate at the point of USE, not only at the point of creation.
valid_slug() {
  case "${1:-}" in
    ''|*/*|*..*) return 1 ;;                    # no separators, no traversal
    *[!a-z0-9-]*) return 1 ;;                   # exactly what slugify can emit
    *) return 0 ;;
  esac
}

slugify() {  # a branch-safe, filesystem-safe, bounded slug
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -e 's/[^a-z0-9]\+/-/g' -e 's/^-*//' -e 's/-*$//' | cut -c1-48
}

cmd_start() {
  local spec="${1:-}" rank source text slug branch def
  [ -n "$spec" ] || die "start needs a candidate: '<rank>|<source>|<text>'"
  rank="${spec%%|*}"; spec="${spec#*|}"; source="${spec%%|*}"; text="${spec#*|}"
  [ -n "$text" ] || die "candidate has no text"
  case "$rank" in ''|*[!0-9]*) die "candidate rank must be numeric" ;; esac

  slug="$(slugify "$text")"; [ -n "$slug" ] || slug="candidate"
  branch="burndown/$slug"
  def="$(default_branch)"
  # `discard` refuses any slug named like the default branch, so minting one here created a branch
  # that could never be removed and counted against the backpressure cap forever. Refuse at the
  # point of creation instead — the guard on the delete side protects nothing, since the delete
  # target is always `burndown/<slug>` and can never BE the default branch.
  case "$slug" in "$def"|main|master) die "slug '$slug' collides with the default branch name — discard would refuse it forever" 9 ;; esac
  git -C "$root" rev-parse --verify --quiet "$def" >/dev/null 2>&1 || die "no default branch '$def' to branch from"
  git -C "$root" rev-parse --verify --quiet "$branch" >/dev/null 2>&1 && die "branch $branch already exists" 3

  # NEVER start from a dirty tree: the generated work must be separable from whatever was already
  # in flight, or "discard the branch" silently discards the owner's uncommitted work too.
  [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] || die "working tree is dirty — refusing to start autonomous work on top of it" 4

  # Manifest FIRST, and fatally: a branch without one is precisely what this tool exists to make
  # impossible, so a failed write must abort before the branch exists — not after.
  mkdir -p "$MANIFEST_DIR" || die "cannot create $MANIFEST_DIR — refusing to open a branch with no manifest" 7
  git -C "$root" checkout -q -b "$branch" "$def" || die "could not create $branch"
  cat > "$MANIFEST_DIR/$slug.md" <<EOF
# $slug

**Generated autonomously.** Nothing here is merged, pushed, or enabled. It exists so you can look
at it later and either keep it or delete it — those are the only two expected outcomes.

- **Source signal:** \`$source\` (rank $rank)
- **Because:** $text
- **Feature flag:** \`BURNDOWN_$(printf '%s' "$slug" | tr 'a-z-' 'A-Z_')\` — **must default to OFF**,
  implemented in whatever idiom this project already uses for flags.
- **Branch:** \`$branch\`

## Try it
Check out \`$branch\` and turn the flag on. If it is not obvious how to try it in one step, that
is a defect in the work, not in these instructions.

## Delete it
\`\`\`
$PLUGIN_DIR/bin/burndown-branch.sh discard $slug
\`\`\`
Deleting is the DEFAULT expectation, not a failure. Work generated to fill idle capacity has to
earn its place exactly like any other work.
EOF
  # An empty marker commit so the branch is genuinely distinguishable from the default branch —
  # `--no-merged` is how everything downstream counts unreviewed work, and a zero-commit branch is
  # invisible to it (correctly: there would be nothing to review).
  git -C "$root" -c user.email=companion@local -c user.name=companion \
      commit -q --allow-empty -m "burndown: open $slug ($source, rank $rank)

$text

No implementation yet. Flag defaults OFF; nothing merges; discard is the default outcome." >/dev/null 2>&1 || true
  printf '%s\n' "$slug"
}

cmd_list() {
  local def b slug
  def="$(default_branch)"
  git -C "$root" rev-parse --verify --quiet "$def" >/dev/null 2>&1 || return 0
  while IFS= read -r b; do
    [ -n "$b" ] || continue
    slug="${b#burndown/}"
    printf '%s' "$b"
    if [ -f "$MANIFEST_DIR/$slug.md" ]; then
      printf '  — %s\n' "$(sed -n 's/^- \*\*Because:\*\* //p' "$MANIFEST_DIR/$slug.md" | head -1)"
    else
      printf '  — (no manifest — created outside this tool)\n'
    fi
  done < <(git -C "$root" branch --no-merged "$def" --list 'burndown/*' --format='%(refname:short)' 2>/dev/null)
}

cmd_discard() {
  local slug="${1:-}" def cur
  [ -n "$slug" ] || die "discard needs a slug"
  valid_slug "$slug" || die "refusing a slug that is not [a-z0-9-]: '$slug'" 8
  def="$(default_branch)"
  cur="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  # Refuse to delete the branch you are standing on, and never touch the default branch.
  [ "$cur" = "burndown/$slug" ] && die "you are on burndown/$slug — switch to $def first" 5
  case "$slug" in "$def"|main|master) die "refusing to touch $slug" 6 ;; esac
  git -C "$root" branch -D "burndown/$slug" >/dev/null 2>&1 || true
  rm -f "$MANIFEST_DIR/$slug.md" 2>/dev/null || true
  printf 'discarded burndown/%s\n' "$slug"
}

case "${1:-list}" in
  start)   shift; cmd_start "${1:-}" ;;
  list)    cmd_list ;;
  show)    shift; [ -n "${1:-}" ] || die "show needs a slug"
           valid_slug "${1:-}" || die "refusing a slug that is not [a-z0-9-]: '$1'" 8
           cat "$MANIFEST_DIR/$1.md" 2>/dev/null || die "no manifest for $1" 1 ;;
  discard) shift; cmd_discard "${1:-}" ;;
  *)       die "usage: burndown-branch.sh [start <candidate>|list|show <slug>|discard <slug>]" ;;
esac
