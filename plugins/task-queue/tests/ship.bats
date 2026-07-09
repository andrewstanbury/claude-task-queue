#!/usr/bin/env bats
#
# Tests for bin/tq-ship.sh — the gated working-tree→merged-on-main flow behind
# /task-queue:ship-it. Hermetic: a local bare repo stands in for origin, and a `gh` stub
# on PATH simulates PR view/create/merge (performing the merge on the bare remote), so
# nothing touches the network. The script itself is deterministic git plumbing only;
# the green gate is the caller's job (commands/ship-it.md), not tested here.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHIP="$ROOT/bin/tq-ship.sh"

  ORIGIN="$(mktemp -d)/origin.git"
  git init -q --bare -b main "$ORIGIN"

  REPO="$(mktemp -d)/proj"
  git init -q -b main "$REPO"
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  git -C "$REPO" remote add origin "$ORIGIN"
  printf 'v1\n' > "$REPO/tracked.txt"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm init
  git -C "$REPO" push -q -u origin main
  git -C "$REPO" remote set-head origin main 2>/dev/null || true

  # gh stub on PATH — state dir carries the branch/base between subcommands.
  STUB_DIR="$(mktemp -d)"
  export GH_STUB_STATE="$(mktemp -d)"
  export GH_STUB_ORIGIN="$ORIGIN"
  export GH_STUB_REPO="$REPO"
  cat > "$STUB_DIR/gh" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
S="$GH_STUB_STATE"
case "${1:-}" in
  auth) exit 0 ;;                                       # authenticated (gh_ok probe)
  pr)   ;;                                              # handled below
  *)    echo "gh-stub: unsupported: $*" >&2; exit 3 ;;
esac
shift; action="${1:-}"; shift || true
case "$action" in
  view)   [ -f "$S/pr" ] && echo 1 || exit 1 ;;
  create)
    head=""; base=""
    while [ $# -gt 0 ]; do case "$1" in --head) head="$2"; shift 2;; --base) base="$2"; shift 2;; *) shift;; esac; done
    printf '%s' "$head" > "$S/branch"; printf '%s' "$base" > "$S/base"; : > "$S/pr"
    echo "https://example.test/pr/1" ;;
  merge)  # <n> --squash --delete-branch : fast-forward base on origin, drop the branch
    br="$(cat "$S/branch")"; base="$(cat "$S/base")"
    git -C "$GH_STUB_REPO" push -q "$GH_STUB_ORIGIN" "origin/$br:refs/heads/$base"
    git -C "$GH_STUB_REPO" push -q "$GH_STUB_ORIGIN" --delete "$br"
    : > "$S/merged" ;;
  *) echo "gh-stub: unsupported pr $action" >&2; exit 3 ;;
esac
STUBEOF
  chmod +x "$STUB_DIR/gh"
  export PATH="$STUB_DIR:$PATH"
}

teardown() {
  rm -rf "$(dirname "$ORIGIN")" "$(dirname "$REPO")" "$GH_STUB_STATE" "$STUB_DIR"
}

@test "happy path: branches, commits, pushes, merges to main, deletes branch, syncs" {
  printf 'v2\n' > "$REPO/tracked.txt"                       # a completed change on main
  run bash -c 'cd "$1" && bash "$2" --title "ship it" --body "why"' _ "$REPO" "$SHIP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"squash-merged into main"* ]]
  # origin main advanced to the new content…
  [ "$(git -C "$ORIGIN" show main:tracked.txt)" = "v2" ]
  # …the feature branch was deleted on origin (only main remains)…
  [ "$(git -C "$ORIGIN" for-each-ref --format='%(refname:short)' refs/heads | grep -c .)" -eq 1 ]
  # …and the local default branch is synced.
  [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = "main" ]
  [ "$(cat "$REPO/tracked.txt")" = "v2" ]
}

@test "refuses a no-op: clean tree on the default branch is nothing to ship" {
  run bash -c 'cd "$1" && bash "$2" --title "x"' _ "$REPO" "$SHIP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"nothing to ship"* ]]
}

@test "refuses outside a git repository" {
  local nonrepo; nonrepo="$(mktemp -d)"
  run bash -c 'cd "$1" && bash "$2" --title "x"' _ "$nonrepo" "$SHIP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not inside a git repository"* ]]
  rm -rf "$nonrepo"
}

@test "requires --title when there are uncommitted changes to commit" {
  printf 'v2\n' > "$REPO/tracked.txt"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$SHIP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no --title"* ]]
}

# ---- gh-absent degraded path ------------------------------------------------
# When gh is missing/unauthenticated, ship still branches + commits + pushes, then hands
# back a compare URL instead of opening/merging a PR — and exits SUCCESS.

# Swap the happy-path gh stub for one whose `auth status` FAILS (unauthenticated) and
# which records a marker if `pr` is ever invoked (it must not be, on the degraded path).
stub_gh_unauth() {
  cat > "$STUB_DIR/gh" <<'STUBEOF'
#!/usr/bin/env bash
set -uo pipefail
case "${1:-}" in
  auth) exit 1 ;;                                        # unauthenticated → degraded path
  pr)   : > "$GH_STUB_STATE/pr-invoked"; exit 3 ;;       # must NOT be reached
  *)    exit 3 ;;
esac
STUBEOF
  chmod +x "$STUB_DIR/gh"
}

@test "gh unavailable: branches, commits, pushes, prints a compare URL, exits 0, no PR/merge" {
  stub_gh_unauth
  printf 'v2\n' > "$REPO/tracked.txt"                    # a completed change on main
  run bash -c 'cd "$1" && bash "$2" --title "ship it" --branch ship/feat' _ "$REPO" "$SHIP"
  [ "$status" -eq 0 ]                                    # SUCCESS despite no gh
  [[ "$output" == *"cannot open or merge a PR"* ]]       # clear manual-merge message
  [[ "$output" == *"ship/feat"* ]]                       # names the pushed branch
  [[ "$output" == *"/compare/ship/feat?expand=1"* ]]     # compare URL for the branch
  # the branch was pushed to origin…
  git -C "$ORIGIN" rev-parse --verify -q "refs/heads/ship/feat" >/dev/null
  # …and no PR create/merge was ever attempted.
  [ ! -f "$GH_STUB_STATE/pr-invoked" ]
  [[ "$output" != *"squash-merged"* ]]
  # fail-safe: the default branch is not left dirty (work moved onto the feature branch).
  [ "$(git -C "$REPO" rev-parse --abbrev-ref HEAD)" = "ship/feat" ]
}

@test "gh unavailable: derives owner/repo compare URL from a git@ origin form" {
  # Parse check without touching the network: origin's FETCH url is a github git@ form
  # (what `git remote get-url` reads for the compare URL), while its PUSH url stays the
  # hermetic local bare repo, so the branch push still lands locally.
  stub_gh_unauth
  git -C "$REPO" remote set-url origin "git@github.com:acme/widgets.git"
  git -C "$REPO" remote set-url --push origin "$ORIGIN"
  printf 'v2\n' > "$REPO/tracked.txt"
  run bash -c 'cd "$1" && bash "$2" --title "ship it" --branch ship/feat' _ "$REPO" "$SHIP"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/acme/widgets/compare/ship/feat?expand=1"* ]]
}
