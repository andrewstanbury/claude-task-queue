#!/usr/bin/env bash
# awaiting-review.sh — work that is FINISHED and waiting on the OWNER (R117).
#
#   awaiting-review.sh [count|list]      (default: count)
#
# THE GAP THIS CLOSES. `tq` tracks work that needs DOING; ❓/⏳ track decisions that need ANSWERING.
# Nothing tracked work that was already done and was sitting on a branch waiting to be looked at —
# so a burn-down branch built overnight, and a feature-class change that `ship.sh` pushed and
# deliberately declined to merge, both rendered exactly like "nothing is happening". That is the
# one state where silence is most expensive: the work is already paid for.
#
# WHAT COUNTS, and why the two rules differ:
#   · `burndown/*` not merged into the default    — ALWAYS. It was authored unattended, on purpose,
#     for the owner to judge; that is the entire contract of burn-down (R82) and a manifest exists
#     for it whether or not the branch was ever pushed.
#   · any other non-default branch not merged, WITH an upstream — pushed means handed over. An
#     unpushed local branch is somebody mid-thought, not a queue item, and counting it would make
#     the lane fire during ordinary work, which is how an indicator gets ignored.
# The default branch itself is never listed: work merged there is shipped, not waiting.
#
# BOUNDED (R81): one `git branch --no-merged` walk, whose cost tracks BRANCH COUNT, not repo size,
# file count or store age. It is not free — `--no-merged` walks history per branch — so the status
# line calls this once per cache TTL, never once per paint, and `./check.sh` measures the ceiling
# rather than asserting it.
set -uo pipefail
# Resolve through symlinks before locating lib/ — the plugin is SERVED from a versioned cache dir
# and may be reached by a link, in which case $0's dirname is not where lib/ lives. The idiom is
# copied from the other bin scripts deliberately; a second way of finding lib/ is a second thing
# to get wrong.
SELF="$0"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${AWAITING_ROOT:-$PWD}")"
mode="${1:-count}"

# No repo, or a repo with no resolvable default branch, is not an error here: this is a display
# helper on a best-effort path (R68), and a status line that dies takes the whole prompt with it.
def="$(companion_default_branch "$root" 2>/dev/null || true)"
if [ -z "$def" ] || ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  [ "$mode" = list ] || printf '0\n'; exit 0
fi

# `%09` is a literal TAB from git's own formatter — building the separator here rather than in the
# read loop keeps branch names containing spaces parseable, and a branch name cannot contain a tab.
emit() {
  git -C "$root" branch --no-merged "$def" \
      --format='%(refname:short)%09%(upstream:short)' 2>/dev/null |
  while IFS="$(printf '\t')" read -r br up; do
    [ -n "$br" ] || continue
    # No explicit "skip the default branch" guard: `--no-merged "$def"` can never list "$def"
    # itself, since a branch always contains its own tip. Writing one anyway would be a line no
    # test could ever redden — coverage claimed over code that cannot run — so it is stated here
    # instead. The behaviour is still pinned: a test asserts the default never appears.
    case "$br" in
      burndown/*) printf 'burndown\t%s\n' "$br" ;;
      # An upstream is the handover signal. Checked with -n on git's own field rather than by
      # asking for the ref again: one query, and it cannot disagree with itself between calls.
      *) [ -n "$up" ] && printf 'branch\t%s\n' "$br" ;;
    esac
  done
}

case "$mode" in
  list)  emit ;;
  count) # `grep -c .` not `wc -l`: an empty stream must print 0, and grep -c prints 0 while EXITING
         # 1, which is why the `|| true` is here and not a `|| printf 0` (that emitted "0\n0" once).
         n="$(emit | grep -c . || true)"
         case "${n:-}" in ''|*[!0-9]*) n=0 ;; esac
         printf '%s\n' "$n" ;;
  *)     printf 'usage: awaiting-review.sh [count|list]\n' >&2; exit 2 ;;
esac
