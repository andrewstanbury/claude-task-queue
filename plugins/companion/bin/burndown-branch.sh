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
# Manifests are REPO state (R96 stage 3) — a branch built in a container is worthless if the record
# of WHY it exists dies with that container. No legacy fallback: manifests describe branches, and a
# branch from a wiped container is gone too.
MANIFEST_DIR="$root/.companion/burndown-manifests"

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

# `sed -E` with `+`, NOT BRE `\+`. `\+` is a GNU extension that BSD sed (the macOS lane) reads as
# a LITERAL plus — so on macOS this collapsed nothing and every multi-word candidate produced a
# branch name containing spaces, which git rejects outright. Burn-down was simply broken there.
# LESSONS has carried "BSD is not GNU — \?/\+/\| are GNU extensions BSD reads as LITERALS" since
# it shipped red three times; this is the fourth, in code written the same day.
slugify() {  # a branch-safe, filesystem-safe, bounded slug
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' \
    | sed -E -e 's/[^a-z0-9]+/-/g' -e 's/^-+//' -e 's/-+$//' | cut -c1-48
}

# ---- ACCEPTANCE-GATED TIERS (R82, owner-decided 2026-08-15) --------------------------------
# The owner asked for the ladder to climb automatically from debt paydown up to auto-authored
# features "when I'm behind schedule on burning tokens". The trigger stays the utilization
# forecast — that is a fine answer to WHETHER there is spare capacity. It is a terrible answer to
# WHAT may be built, because it measures spending and never value: the binding constraint is the
# owner's review throughput, which does not grow when the token budget does. A ladder climbing on a
# spending clock converts a token surplus into a review backlog.
#
# So WHICH tier is gated on DEMONSTRATED ACCEPTANCE instead — the share of generated branches the
# owner actually kept. It is self-correcting in both directions and needs no new judgement from
# anyone: keep the work and the ceiling rises, discard it and the ceiling falls back.
#
# THE LEDGER IS APPROXIMATE, AND SAYS SO. `created` is recorded here, `abandoned` on discard;
# MERGED is inferred as created - abandoned - still-present, because a merged branch is routinely
# pruned (ship.sh does it) and would otherwise be invisible. A branch deleted by hand therefore
# reads as accepted. That biases toward permissiveness, so the thresholds below are set where a
# couple of stray hand-deletions cannot promote a tier on their own.
LEDGER="$root/.companion/burndown-outcomes"

ledger_record() {  # $1 event · $2 slug — best-effort (R68): never break the command that triggered it
  { mkdir -p "$(dirname "$LEDGER")" 2>/dev/null && printf '%s %s\n' "$1" "$2" >> "$LEDGER"; } 2>/dev/null || true
}

# Highest candidate rank this repo has earned. Ranks are PRIORITY, not difficulty, so the tiers are
# named explicitly rather than derived from the number:
#   3 TODO · 4 untested flow  — pure debt paydown. Verifiable against the suite that already
#                               exists, which is what makes it safe to do unattended. ALWAYS on.
#   1 parked-with-rec · 2 ROADMAP — owner-recorded intent, and where FEATURES live. Needs evidence
#                               the owner keeps this kind of output.
#   5 rework rebuild          — large and structural; needs a strong record.
#   6 invent                  — never automatic. Nothing recorded asked for it.
tier_allows() {  # $1 rank -> 0 when permitted
  local rank="$1" created=0 abandoned=0 present=0 merged=0 judged=0 pct=0
  case "$rank" in 3|4) return 0 ;; 6) return 1 ;; esac
  if [ -f "$LEDGER" ]; then
    created="$(grep -c '^created ' "$LEDGER" 2>/dev/null || printf 0)"
    abandoned="$(grep -c '^abandoned ' "$LEDGER" 2>/dev/null || printf 0)"
  fi
  case "$created" in ''|*[!0-9]*) created=0 ;; esac
  case "$abandoned" in ''|*[!0-9]*) abandoned=0 ;; esac
  present="$(git -C "$root" branch --list 'burndown/*' 2>/dev/null | grep -c . || printf 0)"
  case "$present" in ''|*[!0-9]*) present=0 ;; esac
  merged=$(( created - abandoned - present )); [ "$merged" -lt 0 ] && merged=0
  judged=$(( merged + abandoned ))
  [ "$judged" -gt 0 ] || return 1                      # no history -> debt only
  pct=$(( merged * 100 / judged ))
  case "$rank" in
    1|2) [ "$judged" -ge 2 ] && [ "$pct" -ge 50 ] && return 0 ;;
    5)   [ "$judged" -ge 4 ] && [ "$pct" -ge 75 ] && return 0 ;;
  esac
  return 1
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
  # STRUCTURAL, like every other guarantee in this file: an ungated tier is a promise nobody keeps.
  git -C "$root" rev-parse --verify --quiet "$branch" >/dev/null 2>&1 && die "branch $branch already exists" 3

  # NEVER start from a dirty tree: the generated work must be separable from whatever was already
  # in flight, or "discard the branch" silently discards the owner's uncommitted work too.
  # The guard exists to refuse building on top of the OWNER's uncommitted changes. Plugin state is
  # not that: since R96 a mode flag lives at .companion/modes/, so merely ARMING burn-down dirtied
  # the tree and blocked burn-down from ever creating a branch — the feature disabled itself.
  if git -C "$root" status --porcelain 2>/dev/null | grep -qvE '^.{2} \.companion/'; then
    die "working tree is dirty — refusing to start autonomous work on top of it" 4
  fi
  # TIER GATE — deliberately LAST of the refusals, after every SAFETY guard above. A dirty tree or a
  # colliding branch is a fact about the repo and must be reported as itself; the tier is policy on
  # top. Ordering it first made a dirty tree read as a tier problem, which sends the reader to fix
  # the wrong thing (caught by the containerisation test, which asserts the dirty refusal).
  [ "$rank" != 6 ] || die "rank 6 is INVENTED work — nothing recorded asked for it, so it is never built unattended at any acceptance rate. Record the intent first (a ROADMAP line, a TODO, a parked decision) and it becomes buildable as the tier it actually is." 13
  tier_allows "$rank" || die "rank $rank is above this repo's earned tier — burn-down may build debt paydown (TODOs, untested flows) until generated branches are demonstrably kept. Merge or discard the existing burndown/* branches and the ceiling moves on its own; \`burndown-branch.sh list\` shows what is waiting." 12
  ledger_record created "$slug"

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
  ledger_record abandoned "$slug"
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
