#!/usr/bin/env bats
#
# ship.sh — the deterministic rail under /companion:ship-it (R71). These pin the GUARDS: the
# rail pushes and merges to the default branch, so every bail must fire BEFORE damage — gate-fail
# aborts uncommitted, secrets never commit, non-ff hands back, the default branch is never a
# delete target, and the merged-branch sweep is list-only without --prune-all.

# Fixture dirs go under BATS_TEST_TMPDIR, which bats removes after each test. Plain `mktemp -d`
# leaks: one session of this suite left 37,000 directories in /tmp and exhausted the inode table,
# which then fails unrelated tests for reasons that look like code defects.
_tmpd() { mktemp -d "$BATS_TEST_TMPDIR/d.XXXXXX"; }

setup() {
  # Tests live in dev/ and are NOT shipped. ROOT still means the SHIPPED plugin dir; DEV is
  # where the gates that verify it live. Keeping the two named apart is the point of the split.
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../plugins/companion" && pwd)"
  DEV="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  SHIP="$ROOT/bin/ship.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)"
  export CLAUDE_COMPANION_STATE_DIR="$(_tmpd)"
  export CLAUDE_COMPANION_SESSION_ID="s1"
  export SHIP_CI_WATCH=0        # R74: default the CI watch OFF for the fixture (no GitHub remote);
                                # the R74 tests re-enable it with a stubbed gh. Keeps land tests fast.
  WORK="$(_tmpd)"
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
  # R78: the DA gate is opt-in per repo — declare this fixture's critical paths, and commit them
  # with the rest so the tree starts CLEAN (an untracked file here broke the exit-6 cases).
  mkdir -p .companion
  printf '^plugins/[^/]+/(bin|lib)/\n^check\\.sh$\n' > .companion/da-paths
  printf 'a\n' > a.txt; git add -A; git commit -qm init; git push -qu origin "$1" 2>/dev/null
  printf 'msg subject\n\nmsg body\n' > "$WORK/msg.txt"
  # R78: the DA gate is opt-in per repo. Declare this fixture's critical paths so the gate is live
  # (a repo with no .companion/da-paths must be unaffected — that is its own case below).
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
  # ...and the failure is COUNTED (R94). A gate that fails without being recorded lets the defect
  # rate be narrated instead of measured, which is the habit the ledger exists to remove. CI found
  # this as a hole: the recording shipped with nothing that could redden if it were removed.
  run env CLAUDE_COMPANION_STATE_DIR="$CLAUDE_COMPANION_STATE_DIR" REWORK_ROOT="$PWD" \
      bash "$ROOT/bin/rework.sh" report
  [[ "$output" == *"gate-fail"* ]]
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

@test "ship.sh handoff: on the default branch — WIP moves to a wip/* branch, default untouched, work rides the commit" {
  _repo main
  "$ROOT/bin/tq" add "carry me" >/dev/null                                      # a queue to carry (R60)
  def_head="$(git rev-parse main)"
  printf 'wip\n' > wip.txt
  run "$SHIP" handoff
  [ "$status" -eq 0 ]
  cur="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$cur" == wip/* ]]                                                         # WIP never lands on default
  [ "$(git rev-parse main)" = "$def_head" ]                                     # default untouched
  git show --stat --format= HEAD | grep -q 'wip.txt'                            # the WIP itself rides the commit
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
  run "$SHIP" land -F "$WORK/msg.txt" --da "gate-parsing fixture, not a real change" --gate env true                           # two-word gate, last
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
  rm check.sh
  run "$SHIP" preflight
  [ "$status" -eq 3 ]
}

# ── enforced-core diffs require a devil's-advocate pass (R78) ──────────────────────────────────
# ship-it.md always *said* to run one on a consequential change; prose is skippable, and the two
# defects that reached `land` here — a predicate that selected the set it existed to exclude, and a
# termination claim that was false — were invisible to a green gate and caught only by that pass.

@test "ship.sh land: an enforced-core diff is REFUSED without --da (exit 11, R78)" {
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'echo changed\n' > plugins/companion/bin/x.sh
  before="$(git rev-parse HEAD)"
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [ "$(git rev-parse HEAD)" = "$before" ]              # nothing committed
  [[ "$output" == *"plugins/companion/bin/x.sh"* ]]    # names the file that triggered it
  [[ "$output" == *"--da"* ]]
}

@test "ship.sh land: --da lets an enforced-core diff ship and records the trailer (R78)" {
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'echo changed\n' > plugins/companion/bin/x.sh
  git push -qu origin feature/x 2>/dev/null
  run "$SHIP" land -F "$WORK/msg.txt" --da "attacked the arg parser and the exit codes; clean"
  [ "$status" -eq 0 ]
  run git log -1 --format=%B main
  [[ "$output" == *"Devil-advocate: attacked the arg parser"* ]]   # auditable later
}

@test "ship.sh land: a NON-core diff still ships with no --da (R78 stays narrow)" {
  _repo main
  git checkout -qb feature/x; printf 'docs\n' > README.md
  git push -qu origin feature/x 2>/dev/null
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  run git log -1 --format=%B main
  [[ "$output" != *"Devil-advocate"* ]]
}

@test "ship.sh land: lib/ counts as enforced core too (R78)" {
  # `bin/` and `check.sh` were covered; without this, narrowing the pattern to bin-only passed.
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/lib; printf 'helper() { :; }\n' > plugins/companion/lib/y.sh
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"plugins/companion/lib/y.sh"* ]]
}

@test "ship.sh land: check.sh itself counts as enforced core (R78)" {
  _repo main
  git checkout -qb feature/x; printf '#!/bin/sh\n# tweak\nexit 0\n' > check.sh
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"check.sh"* ]]
}

@test "ship.sh land: rename bypasses are closed — both sides of a rename count (R78)" {
  # `git status --porcelain` prints `old -> new` for a rename, which a naive path grep misses.
  # The worst case was renaming check.sh AWAY — removing the project's gate — and shipping clean.
  _repo main
  # The core file must already exist ON MAIN: committing it on the branch would surface the path
  # through `log def..HEAD` and mask the very bypass under test.
  mkdir -p plugins/companion/bin docs
  printf 'x\n' > plugins/companion/bin/x.sh; git add -A; git commit -qm "add core file"
  git push -q origin main 2>/dev/null
  git checkout -qb feature/x
  # Rename a critical file OUT of the critical set. With rename DETECTION on, `--name-only` reports
  # only the destination (`docs/x.sh`), which matches nothing — the change to the enforced core
  # becomes invisible. `--no-renames` reports both sides, so the departing path is still seen.
  git mv plugins/companion/bin/x.sh docs/x.sh
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"plugins/companion/bin/x.sh"* ]]   # the path it LEFT, not just where it landed
}

@test "ship.sh land: paths with spaces and non-ASCII are still seen (R78)" {
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin
  printf 'x\n' > "plugins/companion/bin/my script.sh"
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"my script.sh"* ]]
  rm -f "plugins/companion/bin/my script.sh"
  printf 'x\n' > "plugins/companion/bin/café.sh"
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"café.sh"* ]]        # quotepath off — not \303\251
}

@test "ship.sh land: NO .companion/da-paths means NO gate — a stranger's repo is untouched (R78/R9)" {
  # The gate must never assume the companion's own layout. A third-party repo with a root check.sh
  # (the name this project itself recommends) would otherwise be permanently unable to ship.
  _repo main
  rm -f .companion/da-paths
  git add -A; git commit -qm "drop da-paths"
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'x\n' > plugins/companion/bin/x.sh
  printf '#!/bin/sh\n# edited\nexit 0\n' > check.sh
  git push -qu origin feature/x 2>/dev/null
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]                    # ships freely: this repo declared nothing critical
}

@test "ship.sh land: --da rejects a flag or a whitespace-only value (R78)" {
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'x\n' > plugins/companion/bin/x.sh
  run "$SHIP" land -F "$WORK/msg.txt" --da --prune-all
  [ "$status" -eq 2 ]                    # would have eaten the flag and recorded it as the finding
  run "$SHIP" land -F "$WORK/msg.txt" --da "   "
  [ "$status" -eq 2 ]                    # would have recorded an empty trailer
}

@test "ship.sh land: the trailer does not orphan Co-Authored-By, and retries don't duplicate (R78)" {
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'x\n' > plugins/companion/bin/x.sh
  printf 'subject\n\nbody\n\nCo-Authored-By: Someone <s@s>\n' > "$WORK/msg.txt"
  git push -qu origin feature/x 2>/dev/null
  run "$SHIP" land -F "$WORK/msg.txt" --da "attacked the arg parser; clean"
  [ "$status" -eq 0 ]
  run git log -1 --format=%B main
  [[ "$output" == *"Co-Authored-By: Someone"* ]]        # still present...
  [[ "$output" == *"Devil-advocate: attacked"* ]]
  run git log -1 --format=%B main
  run bash -c 'git log -1 --format=%B main | git interpret-trailers --parse'
  [[ "$output" == *"Co-Authored-By: Someone"* ]]        # ...and still a RECOGNISED trailer
  run grep -c 'Devil-advocate' "$WORK/msg.txt"
  [ "$output" = "0" ]                                    # caller's file never mutated
}

# ── the CI watch must not report a give-up as a pass (R74 amended, R78) ────────────────────────
# The timeout returned 0 with a "not failed" line, so a watch that gave up read exactly like one
# that passed. Adding a ~9min CI job put the run duration either side of the 300s default and two
# ships reported "not failed" — one of them was RED on macOS, found only by checking manually.

@test "ship.sh land: a run still in flight at timeout exits 12 — SHIPPED but UNWATCHED (R74)" {
  _repo main
  _gh_stub in_progress/          # a run EXISTS and never concludes
  printf 'b\n' > b.txt
  git push -qu origin main 2>/dev/null || true
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 12 ]
  [[ "$output" == *"UNWATCHED"* ]]
  [[ "$output" != *"not failed"* ]]      # the phrasing that made a give-up look like a pass
  # and it really did ship — 12 is about the watch, never about the commit
  run git log -1 --format=%s main
  [ "$output" = "msg subject" ]
}

@test "ship.sh land: genuinely no CI to watch still exits 0, not 12 (R74)" {
  # No `gh` at all, and a run that never registers, are different facts from abandoning a live run:
  # there is nothing to watch, so they must not be reported as an unwatched ship.
  _repo main
  mkdir -p "$WORK/nogh"; export PATH="$WORK/nogh:$PATH"   # shadow gh with nothing
  cat > "$WORK/nogh/gh" <<'NOGH'
#!/usr/bin/env bash
exit 127
NOGH
  chmod +x "$WORK/nogh/gh"
  export SHIP_CI_WATCH=1 SHIP_CI_APPEAR=1 SHIP_CI_POLL=1 SHIP_CI_TIMEOUT=2
  printf 'b\n' > b.txt
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNWATCHED"* ]]       # still SAYS so...
  [[ "$output" != *"CI STILL RUNNING"* ]] # ...but not as an abandoned run
}

@test "ci-watch.sh is callable standalone and reports its own exit codes (R74/R78)" {
  _repo main
  _gh_stub completed/failure
  run "$ROOT/bin/ci-watch.sh" "$(git rev-parse HEAD)"
  [ "$status" -eq 10 ]
  [[ "$output" == *"CI RED"* ]]
  run "$ROOT/bin/ci-watch.sh"
  [ "$status" -eq 2 ]                    # usage: needs a sha
}

@test "ship.sh land: a RUBBER-STAMP --da is refused; a substantive clean note passes (R78)" {
  # One word was the cheapest way to defeat the whole gate, and a stamp is WORSE than no gate —
  # it launders the decision instead of testing it. A clean pass must still say what it examined.
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'x\n' > plugins/companion/bin/x.sh
  local stamp
  for stamp in clean none "n/a" ok LGTM "  Clean  " "no findings" "checked it"; do
    run "$SHIP" land -F "$WORK/msg.txt" --da "$stamp"
    [ "$status" -eq 2 ]
    { [[ "$output" == *"rubber stamp"* ]] || [[ "$output" == *"substantive"* ]]; }
  done
  # a real clean note that NAMES what was attacked is accepted (not refused at parse time)
  run "$SHIP" land -F "$WORK/msg.txt" --da "attacked the arg parser on empty and array input plus the delete path; no defect found"
  [ "$status" -ne 2 ]
}

@test "da-gate match: the widened path set is evaluated by the REAL gate, not a re-implementation" {
  # This used to re-implement the comment-strip + grep inline, so deleting `da-gate.sh match`
  # entirely still passed it — a guard that proves nothing about the gate (the same trap
  # _ux_check_resolves exists to avoid). It now pipes through the real script.
  local dg="$ROOT/bin/da-gate.sh" repo p
  repo="$(cd "$ROOT/../.." && pwd)"
  [ -f "$repo/.companion/da-paths" ] || skip "repo da-paths not present"
  for p in plugins/companion/hooks/hooks.json dev/tests/companion-core.bats \
           plugins/companion/commands/autopilot.md plugins/companion/STEERING.md \
           .github/workflows/ci.yml .companion/da-paths \
           .claude-plugin/marketplace.json plugins/companion/.claude-plugin/plugin.json; do
    run bash -c 'cd "$1" && printf "%s\n" "$2" | "$3" match' _ "$repo" "$p" "$dg"
    [ "$status" -eq 1 ] || { echo "NOT GATED: $p (rc=$status)" >&2; return 1; }
  done
  # pure prose stays OUT on purpose — a gate that fires on a typo trains a reflexive "clean"
  for p in docs/adr/PROVENANCE.md README.md; do
    run bash -c 'cd "$1" && printf "%s\n" "$2" | "$3" match' _ "$repo" "$p" "$dg"
    [ "$status" -eq 0 ] || { echo "UNEXPECTEDLY GATED: $p (rc=$status)" >&2; return 1; }
  done
}

@test "da-gate match: FAILS CLOSED on an unusable config, and CRLF cannot disable it" {
  # Three demonstrated fail-OPENs, all of which merged a bin/ change to main with no --da:
  # an unreadable file, a directory in place of the file, and CRLF line endings from a Windows
  # clone (this repo ships no .gitattributes, so autocrlf gives that by default).
  local dg="$ROOT/bin/da-gate.sh" w; w="$(_tmpd)"; mkdir -p "$w/.companion"
  printf '^plugins/[^/]+/(bin|lib)/\n' > "$w/.companion/da-paths"
  run bash -c 'cd "$1" && printf "plugins/companion/bin/x.sh\n" | "$2" match' _ "$w" "$dg"
  [ "$status" -eq 1 ]                                        # control: gated
  if [ "$(id -u)" -ne 0 ]; then
    chmod 000 "$w/.companion/da-paths"
    run bash -c 'cd "$1" && printf "plugins/companion/bin/x.sh\n" | "$2" match' _ "$w" "$dg"
    [ "$status" -eq 2 ]                                      # unreadable -> fail CLOSED
    chmod 644 "$w/.companion/da-paths"
  fi
  rm -f "$w/.companion/da-paths"; mkdir "$w/.companion/da-paths"
  run bash -c 'cd "$1" && printf "plugins/companion/bin/x.sh\n" | "$2" match' _ "$w" "$dg"
  [ "$status" -eq 2 ]                                        # a directory -> fail CLOSED
  rmdir "$w/.companion/da-paths"
  printf '^plugins/[^/]+/(bin|lib)/\r\n^check\\.sh$\r\n' > "$w/.companion/da-paths"
  run bash -c 'cd "$1" && printf "plugins/companion/bin/x.sh\n" | "$2" match' _ "$w" "$dg"
  [ "$status" -eq 1 ]                                        # CRLF still gates
  rm -rf "$w"
}

@test "da-gate note: rejects stamps and trailer injection, ACCEPTS a non-ASCII finding (R1)" {
  local dg="$ROOT/bin/da-gate.sh" v
  for v in clean none "n/a" ok LGTM "  Clean  " "no findings" "checked it"; do
    run "$dg" note "$v"; [ "$status" -eq 2 ]
  done
  # a newline would forge a second commit trailer (Signed-off-by:) — one line only
  run "$dg" note "$(printf 'a genuine and reasonably long finding\nSigned-off-by: forged')"
  [ "$status" -eq 2 ]
  # length is measured on the ORIGINAL, so a substantive non-ASCII finding is accepted: the
  # ASCII fold is for the denylist compare only. "Write it in English" is not a requirement.
  run "$dg" note "パーサーを空配列と非UTF8入力で攻撃し、削除経路も確認した。欠陥なし"
  [ "$status" -eq 0 ]
  run "$dg" note "attacked the arg parser on empty and array input plus the delete path; none found"
  [ "$status" -eq 0 ]
}

@test "ship.sh land: a COMMENT in da-paths cannot disable the gate, and an invalid one FAILS CLOSED (R78)" {
  # `grep -Ef` compiles EVERY line as a regex, so "(registering a hook)" in a comment made grep
  # exit 2, `core` came back empty, and the gate silently did not fire. Measured on the real file.
  _repo main
  git checkout -qb feature/x
  mkdir -p plugins/companion/bin; printf 'x\n' > plugins/companion/bin/x.sh
  printf '# a note with (an unmatched paren and a [bracket\n^plugins/[^/]+/(bin|lib)/\n' > .companion/da-paths
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]                                  # comment ignored, real pattern still gates
  [[ "$output" == *"critical paths"* ]]
  # a genuinely invalid PATTERN line must refuse to ship rather than sail through ungated
  printf '^plugins/(bin\n' > .companion/da-paths
  run "$SHIP" land -F "$WORK/msg.txt"
  [ "$status" -eq 11 ]
  [[ "$output" == *"refusing to ship UNGATED"* ]]
}

@test "ship.sh land: on the DEFAULT branch, committed-but-unpushed work still ships (retry path)" {
  # The retry path was gated on `cur != def`, so on the default branch it could never fire: being
  # ON main makes `def..HEAD` empty by definition. A clean tree with unpushed commits therefore
  # reported "nothing to commit" and shipped nothing — which is precisely the state a land that
  # bailed after committing leaves you in, on the branch most people work from. Hit for real
  # while shipping this session.
  local up repo msg; up="$(_tmpd)"; git init -q --bare "$up"
  repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$repo" remote add origin "$up"; git -C "$repo" push -q -u origin main
  printf '#!/bin/sh\nexit 0\n' > "$repo/gate.sh"; chmod +x "$repo/gate.sh"
  git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m gate
  # Clean tree, one unpushed commit, standing on the default branch.
  [ -z "$(git -C "$repo" status --porcelain)" ]
  msg="$(mktemp "$BATS_TEST_TMPDIR/m.XXXXXX")"; printf 'ship it\n' > "$msg"
  run bash -c 'cd "$1" && SHIP_CI_WATCH=0 bash "$2" land -F "$3" --gate ./gate.sh' _ "$repo" "$SHIP" "$msg"
  [ "$status" -eq 0 ]
  [[ "$output" == *"unpushed commit"* ]]
  # The remote actually advanced — the whole point.
  [ "$(git -C "$up" rev-parse main)" = "$(git -C "$repo" rev-parse HEAD)" ]
  # And a genuinely empty state still exits 6 rather than pushing nothing.
  run bash -c 'cd "$1" && SHIP_CI_WATCH=0 bash "$2" land -F "$3" --gate ./gate.sh' _ "$repo" "$SHIP" "$msg"
  [ "$status" -eq 6 ]
}

@test "ship.sh: a ship never SNAPSHOTS live mode state (R96·b)" {
  # Mode flags are files in the repo, so `git add -A` was recording whatever happened to be set at
  # that instant. A review PAUSE deletes the autopilot flag — and one ship committed that as
  # "autopilot off", which silently disarmed it afterwards for no reason the owner could see.
  # Transient state must not become a version-controlled fact.
  _repo main
  printf 'work\n' > w.txt
  mkdir -p .companion/modes; : > .companion/modes/autopilot
  git add -A; git commit -qm "mode committed deliberately"
  rm -f .companion/modes/autopilot            # a pause: the flag goes away
  : > .companion/modes/autopilot-paused

  printf '#!/bin/sh\nexit 0\n' > check.sh; chmod +x check.sh
  run "$SHIP" land -F "$WORK/msg.txt" --da "checked that unstaging the modes directory does not also drop the owner's real work from the commit, and that a deliberately committed mode flag survives the ship rather than being deleted by the pause"
  [ "$status" -eq 0 ]
  # the DELETION must not have been recorded — the deliberately committed mode survives
  git show HEAD --stat --format= | grep -q '.companion/modes' && false || true
  git cat-file -e HEAD:.companion/modes/autopilot 2>/dev/null
}

_fc_repo() {  # a repo with a flow page, implementation, and a gate
  FCR="$(_tmpd)"; mkdir -p "$FCR/docs/flows" "$FCR/src"
  git -C "$FCR" init -q -b main
  echo x > "$FCR/src/a.sh"
  { echo '# flow:f'; echo 'steps:'; echo '- a'; } > "$FCR/docs/flows/f.md"
  echo 'check() { :; }' > "$FCR/check.sh"; chmod +x "$FCR/check.sh"
  git -C "$FCR" add -A
  git -C "$FCR" -c user.email=t@t -c user.name=t commit -qm base
  FCM="$(_tmpd)/m.txt"; echo msg > "$FCM"
}

@test "ship.sh land: FEATURE-CLASS work will not land on the default branch, and refuses BEFORE committing" {
  # The asymmetry this closes: autonomously-generated features already got a branch + flag +
  # never-merge, while a feature the OWNER asked for landed straight on main like a typo fix.
  # Refusing before staging matters — a refusal that leaves a commit behind is a mess to unpick.
  _fc_repo
  echo '- b' >> "$FCR/docs/flows/f.md"; echo y >> "$FCR/src/a.sh"
  local before; before="$(git -C "$FCR" rev-list --count HEAD)"
  run bash -c 'cd "$1" && "$2" land -F "$3" --gate ./check.sh' _ "$FCR" "$SHIP" "$FCM"
  [ "$status" -eq 15 ]
  [[ "$output" == *"FEATURE-CLASS"* ]]; [[ "$output" == *"Branch first"* ]]
  [ "$(git -C "$FCR" rev-list --count HEAD)" -eq "$before" ]   # nothing committed
}

@test "ship.sh land: FEATURE-CLASS from a branch commits but does NOT auto-merge" {
  _fc_repo
  git -C "$FCR" checkout -qb feat/x
  echo '- b' >> "$FCR/docs/flows/f.md"; echo y >> "$FCR/src/a.sh"
  run bash -c 'cd "$1" && "$2" land -F "$3" --gate ./check.sh' _ "$FCR" "$SHIP" "$FCM"
  [ "$status" -eq 0 ]
  [[ "$output" == *"does NOT auto-merge"* ]]
  [[ "$output" == *"merge on your say-so"* ]]
  [ "$(git -C "$FCR" rev-list --count main)" -eq 1 ]              # default branch untouched
  [ "$(git -C "$FCR" rev-parse --abbrev-ref HEAD)" = "feat/x" ]   # left on the branch
}

@test "ship.sh land: --merge-feature overrides, and ordinary work is untouched by the gate" {
  # The override must come BEFORE --gate, which deliberately slurps everything after it.
  _fc_repo
  echo '- b' >> "$FCR/docs/flows/f.md"; echo y >> "$FCR/src/a.sh"
  run bash -c 'cd "$1" && "$2" land -F "$3" --merge-feature --gate ./check.sh' _ "$FCR" "$SHIP" "$FCM"
  [ "$status" -eq 0 ]; [[ "$output" == *"shipped"* ]]

  # a FLOW-PAGE-ONLY edit is not a release, and code-only is not a documented behaviour change
  _fc_repo
  echo '- b' >> "$FCR/docs/flows/f.md"
  run bash -c 'cd "$1" && "$2" land -F "$3" --gate ./check.sh' _ "$FCR" "$SHIP" "$FCM"
  [ "$status" -eq 0 ]; [[ "$output" == *"shipped"* ]]

  _fc_repo
  echo y >> "$FCR/src/a.sh"
  run bash -c 'cd "$1" && "$2" land -F "$3" --gate ./check.sh' _ "$FCR" "$SHIP" "$FCM"
  [ "$status" -eq 0 ]; [[ "$output" == *"shipped"* ]]
}
