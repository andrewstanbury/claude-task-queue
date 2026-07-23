#!/usr/bin/env bats
#
# ship.sh — the deterministic rail under /companion:ship-it (R71). These pin the GUARDS: the
# rail pushes and merges to the default branch, so every bail must fire BEFORE damage — gate-fail
# aborts uncommitted, secrets never commit, non-ff hands back, the default branch is never a
# delete target, and the merged-branch sweep is list-only without --prune-all.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHIP="$ROOT/bin/ship.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_SESSION_ID="s1"
  export SHIP_CI_WATCH=0        # R74: default the CI watch OFF for the fixture (no GitHub remote);
                                # the R74 tests re-enable it with a stubbed gh. Keeps land tests fast.
  WORK="$(mktemp -d)"
}

# Stub `gh` on PATH so watch_ci resolves it before any real gh: `run list` yields a run id,
# `run view` yields $1 (e.g. completed/success). Re-enables the watch with tiny timeouts.
_gh_stub() {  # $1 = what `gh run view` reports
  mkdir -p "$WORK/stub"
  cat > "$WORK/stub/gh" <<STUB
#!/usr/bin/env bash
case "\$1 \$2" in
  "run list") echo 999 ;;
  "run view") echo "$1" ;;
  *) exit 0 ;;
esac
STUB
  chmod +x "$WORK/stub/gh"
  export PATH="$WORK/stub:$PATH"
  export SHIP_CI_WATCH=1 SHIP_CI_APPEAR=1 SHIP_CI_POLL=1 SHIP_CI_TIMEOUT=2
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR" "$WORK"; }

# Fixture: bare remote + clone with a passing gate, one commit on the default branch, pushed.
_repo() {  # $1=default-branch name
  git init -q --bare "$WORK/remote.git"
  git clone -q "$WORK/remote.git" "$WORK/work" 2>/dev/null
  cd "$WORK/work"
  git config user.email t@t; git config user.name t
  git checkout -qb "$1" 2>/dev/null || true
  printf '#!/bin/sh\nexit 0\n' > check.sh; chmod +x check.sh
  printf 'a\n' > a.txt; git add -A; git commit -qm init; git push -qu origin "$1" 2>/dev/null
  printf 'msg subject\n\nmsg body\n' > "$WORK/msg.txt"
}

@test "ship.sh land: happy path — commit, ff-merge to default, push, prune shipped branch (local+remote)" {
  _repo main
  git checkout -qb feature/x; printf 'b\n' > b.txt; git push -qu origin feature/x 2>/dev/null
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
  [ "$(git -C "$WORK/remote.git" log --format=%s -1 main)" = "msg subject" ]   # pushed
  ! git show-ref --verify -q refs/heads/feature/x                              # local pruned (-d)
  ! git ls-remote --exit-code --heads origin feature/x >/dev/null 2>&1         # remote pruned
  git show-ref --verify -q refs/heads/main                                     # default NEVER deleted
}

@test "ship.sh land: gate failure aborts BEFORE any commit (exit 4)" {
  _repo main
  git checkout -qb feature/x; printf 'b\n' > b.txt
  printf '#!/bin/sh\nexit 1\n' > check.sh
  before="$(git rev-parse HEAD)"
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 4 ]
  [ "$(git rev-parse HEAD)" = "$before" ]                                      # nothing committed
}

@test "ship.sh land: a staged credential shape is refused BEFORE commit (exit 9)" {
  _repo main
  local k="AKIA""ABCDEFGHIJKLMNOP"                                             # split so THIS file passes the gate
  git checkout -qb feature/x; printf 'key=%s\n' "$k" > creds.txt
  before="$(git rev-parse HEAD)"
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 9 ]
  [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "ship.sh land: non-ff merge bails (exit 7), hands back ON the feature branch, default untouched" {
  _repo main
  git checkout -qb feature/x; printf 'b\n' > b.txt; git add -A; git commit -qm feat
  git checkout -q main; printf 'd\n' > d.txt; git add -A; git commit -qm diverge   # diverge default
  def_head="$(git rev-parse main)"
  git checkout -q feature/x
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 7 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]                       # handed back here
  [ "$(git rev-parse main)" = "$def_head" ]                                    # default untouched
}

@test "ship.sh land: retry path — nothing staged but unmerged commits exist -> still ships" {
  _repo master                                                                  # also pins master-detection
  git checkout -qb feature/x; printf 'b\n' > b.txt; git add -A; git commit -qm feat
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK/remote.git" log --format=%s -1 master)" = "feat" ]        # curated commit shipped as-is
}

@test "ship.sh land: on the default branch — commit + push, no merge, no prune" {
  _repo main
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  [ "$(git -C "$WORK/remote.git" log --format=%s -1 main)" = "msg subject" ]
  git show-ref --verify -q refs/heads/main
}

@test "ship.sh land: clean tree and no unmerged commits -> exit 6, nothing shipped" {
  _repo main
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 6 ]
}

@test "ship.sh land: merged-branch sweep is LIST-ONLY without --prune-all; --prune-all deletes with -d, never the default" {
  _repo main
  git branch old-merged                                                         # merged (same tip)
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"                                           # on-default ship
  [ "$status" -eq 0 ]
  git show-ref --verify -q refs/heads/old-merged                                # list-only: survived
  [[ "$output" == *"old-merged"* ]]                                             # ...but listed
  printf 'c\n' > c.txt
  run "$SHIP" land -F "$WORK/msg.txt" --prune-all
  [ "$status" -eq 0 ]
  ! git show-ref --verify -q refs/heads/old-merged                              # swept
  git show-ref --verify -q refs/heads/main                                      # default survives the sweep
}

@test "ship.sh handoff: on the default branch — WIP moves to a wip/* branch, default untouched, queue rides the commit" {
  _repo main
  "$ROOT/bin/tq" add "carry me" >/dev/null                                      # a queue to carry (R60)
  def_head="$(git rev-parse main)"
  printf 'wip\n' > wip.txt
  run "$SHIP" handoff
  [ "$status" -eq 0 ]
  cur="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$cur" == wip/* ]]                                                         # WIP never lands on default
  [ "$(git rev-parse main)" = "$def_head" ]                                     # default untouched
  git show --stat --format= HEAD | grep -q '.companion/queue.json'              # queue rides the commit
  git ls-remote --exit-code --heads origin "$cur" >/dev/null                    # pushed
}

@test "ship.sh handoff: on a feature branch — commits in place and pushes; a staged credential is refused" {
  _repo main
  git checkout -qb feature/x
  local k="AKIA""ABCDEFGHIJKLMNOP"                                              # split so THIS file passes the gate
  printf 'key=%s\n' "$k" > creds.txt
  run "$SHIP" handoff
  [ "$status" -eq 9 ]                                                           # secret refused — it pushes
  rm creds.txt; printf 'wip\n' > wip.txt
  run "$SHIP" handoff
  [ "$status" -eq 0 ]
  [ "$(git rev-parse --abbrev-ref HEAD)" = "feature/x" ]                        # in place, no wip/* detour
  git ls-remote --exit-code --heads origin feature/x >/dev/null                 # pushed
}

@test "ship.sh handoff: clean tree + no queue delta -> exit 6; no remote -> exit 8" {
  _repo main
  run "$SHIP" handoff
  [ "$status" -eq 6 ]                                                           # nothing to hand off
  git remote remove origin
  printf 'wip\n' > wip.txt
  run "$SHIP" handoff
  [ "$status" -eq 8 ]                                                           # git IS the transport
}

@test "ship.sh land: --gate accepts a MULTI-WORD gate (slurps trailing args, matching preflight)" {
  _repo main
  rm check.sh                                                                   # force an explicit gate
  git checkout -qb feature/x; printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt" --gate env true                           # two-word gate, last
  [ "$status" -eq 0 ]                                                           # DA #1: not a spurious exit 4
  [ "$(git rev-parse --abbrev-ref HEAD)" = "main" ]
}

@test "ship.sh land: ENFORCES the CI watch — GREEN run exits 0 (R74)" {
  _repo main
  _gh_stub completed/success
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI GREEN"* ]]
}

@test "ship.sh land: CI RED after a successful push exits 10 — SHIPPED, fix-forward not un-shipped (R74)" {
  _repo main
  _gh_stub completed/failure
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 10 ]
  [[ "$output" == *"CI RED"* ]]
  [ "$(git -C "$WORK/remote.git" log --format=%s -1 main)" = "msg subject" ]   # commit still landed
}

@test "ship.sh land: SHIP_CI_WATCH=0 opts out of the watch (R74)" {
  _repo main
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"            # setup() already exports SHIP_CI_WATCH=0
  [ "$status" -eq 0 ]
  [[ "$output" == *"CI watch off"* ]]
}

@test "ship.sh preflight: gate + drift + export + summary in one call; no gate -> exit 3" {
  _repo main
  "$ROOT/bin/tq" add "carry me via preflight" >/dev/null   # a queue for the R60 export to carry
  printf 'dirty\n' > dirty.txt                             # so the summary's git status has content
  run "$SHIP" preflight
  [ "$status" -eq 0 ]
  [[ "$output" == *"preflight OK"* ]]
  [[ "$output" == *"branch: main"* ]]
  [[ "$output" == *"dirty.txt"* ]]                         # the summary step ran `git status`
  [ -f .companion/queue.json ]                             # the R60 export step ran...
  grep -q "carry me via preflight" .companion/queue.json   # ...and actually carried the open task
  rm check.sh
  run "$SHIP" preflight
  [ "$status" -eq 3 ]
}
