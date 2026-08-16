#!/usr/bin/env bats
#
# RESUME + SESSION CONTEXT - session-start, resume, prompt-continue, steering delivery, LESSONS, rework.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper


@test "steering off (per-repo flag): resume drops the working agreement (tasks/lessons unaffected, R50)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off steering "$repo"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Working agreement"* ]]
  # clear the flag → agreement returns (default ON)
  _feature_clear
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" == *"Working agreement"* ]]
  rm -rf "$repo"
}

@test "resume survives a repo MOVE — scoping keys on a per-worktree identity, not the abspath (R63)" {
  # The papercut in path-scoping: move the repo and your carried queue silently vanishes (the abspath
  # .root no longer matches). tq now also stamps .repo (a per-working-tree id in the tree's git dir,
  # which moves WITH the tree), and companion_open_tasks matches on it, so a move no longer hides tasks.
  local a b; a="$(_tmpd)/proj"; mkdir -p "$a"; git -C "$a" init -q
  ( cd "$a" && "$TQ" add "carry me" ) >/dev/null
  [ -f "$CLAUDE_COMPANION_TASKS_DIR/s1/.repo" ]                       # identity stamp written
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$a" "$ROOT"
  [[ "$output" == *"carry me"* ]]                                     # found at the original path
  b="$(_tmpd)/moved"; mkdir -p "$(dirname "$b")"; mv "$a" "$b"    # MOVE to a different abspath
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$b" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carry me"* ]]                                     # STILL found after the move
  rm -rf "$(dirname "$b")"
}

@test "resume ISOLATES git worktrees — same history, separate trees, separate queues (R63: not root-SHA)" {
  # A worktree (or clone/fork) shares the root commit but is a DISTINCT working tree; its queue must
  # stay separate (the "no cross-project task bleed" invariant). Identity is a per-worktree tag, NOT
  # the root-SHA — which would collide worktrees/clones and merge their queues (a devil's-advocate catch).
  local main wt; main="$(_tmpd)/main"; mkdir -p "$main"; git -C "$main" init -q
  git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
  ( cd "$main" && "$TQ" add "main-tree task" ) >/dev/null
  wt="$(_tmpd)/feature"; git -C "$main" worktree add -q "$wt" 2>/dev/null
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$main" "$ROOT"
  [[ "$output" == *"main-tree task"* ]]                               # the main tree sees its task
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$wt" "$ROOT"
  [[ "$output" != *"main-tree task"* ]]                               # the worktree does NOT — isolated
  git -C "$main" worktree remove --force "$wt" 2>/dev/null || true
  rm -rf "$(dirname "$main")" "$(dirname "$wt")"
}

# ---- session start (steering + root-scoped resume, no native transcript) ----

@test "resume: prints STEERING and resumes THIS repo's tasks only (scoped by .root) — R39" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sMine"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sMine" "$repo"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOther"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"
  # this repo's LESSONS.md is surfaced (R30·d7)
  mkdir -p "$repo/docs"; printf 'GOTCHA_MARKER: brace vars before emoji\n' > "$repo/docs/LESSONS.md"

  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]     # STEERING injected
  [[ "$output" == *"resume me"* ]]             # this repo's task
  [[ "$output" != *"NOT MINE"* ]]              # no cross-repo bleed
  [[ "$output" == *"GOTCHA_MARKER"* ]]         # this repo's LESSONS surfaced
}

@test "resume: prints the STEERING CORE only — rationale below the marker excluded; missing marker fails OPEN (R69)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core is printed…
  [[ "$output" == *"Posture"* ]]                   # …through its last section
  [[ "$output" != *"Rationale (not injected"* ]]   # the below-marker half NEVER ships
  [[ "$output" != *"injection stops here"* ]]      # the marker line itself is excluded too
  # Fail-open (R7): a STEERING with no marker (old copy, botched edit) prints the WHOLE doc —
  # degraded-but-working beats silently steering-less. Build a marker-less plugin dir to prove it.
  local plug; plug="$(_tmpd)"; mkdir -p "$plug/bin" "$plug/lib"
  cp "$RESUME" "$plug/bin/resume.sh"; cp "$ROOT/lib/companion.sh" "$ROOT/lib/resume-report.sh" "$plug/lib/"
  sed '/injection stops here/d' "$ROOT/STEERING.md" > "$plug/STEERING.md"
  run bash -c 'cd "$1" && "$2/bin/resume.sh"' _ "$repo" "$plug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rationale (not injected"* ]]   # no marker → whole doc (fail-open, not fail-silent)
}

@test "resume: shows the FULL STEERING core alongside the live queue — no abbreviated path left to pick (R100/Pass 2)" {
  # R30·d2's old abbreviated compact-only re-anchor is retired with the hook it lived in: there is no
  # more "source:compact" signal to detect (no stdin JSON at all), so resume always shows the same
  # full core plus the live queue — simpler, and never under-shows what a partial-detection bug once
  # risked. The queue re-anchor property R30·d2 existed for (each task's done-when is its own
  # acceptance test, so it survives a compaction the STEERING prose does not need to repeat) still
  # holds — it is just no longer a SEPARATE code path from the ordinary case.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/xc"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/xc" "$repo"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/xc/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]     # the full STEERING core...
  [[ "$output" == *"resume me"* ]]             # ...and the live queue, together, every time
}

@test "resume: BATCHED scan — many dirs x many files in one jq, newline-less markers still match" {
  # companion_open_tasks collects every matching file and runs ONE jq over all of them (it used to
  # spawn a jq per file: 277 spawns / ~2s on a real store, on the SessionStart + compaction path).
  # Two failure modes this pins, both of which lose tasks SILENTLY — no error, just a short list:
  #   1. markers are written with `printf '%s'` (NO trailing newline), so the `read` builtin returns
  #      1 on them. Reading them with `read … && match` instead of checking the VARIABLE drops the
  #      whole session dir.
  #   2. a batched jq that mishandles multi-file input drops files after the first.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  # Compute the identity from the RESOLVED root, not the possibly-symlinked mktemp path — the
  # readers all resolve, so a fixture that does not writes an id nothing will match.
  local rid; rid="$(cd "$(git -C "$repo" rev-parse --show-toplevel)" && bash -c 'source "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  # dir A matches on the path-stable .repo identity, dir B on the legacy .root abspath — both
  # newline-less, exactly as `tq` writes them. Several files each, so batching has to span dirs.
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sA"; printf '%s' "$rid"  > "$CLAUDE_COMPANION_TASKS_DIR/sA/.repo"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sB"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sB" "$repo"
  jq -n '{id:"1",subject:"alpha A1",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sA/1.json"
  jq -n '{id:"2",subject:"alpha A2",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sA/2.json"
  jq -n '{id:"3",subject:"alpha A3",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/sA/3.json"
  jq -n '{id:"1",subject:"beta B1",status:"pending"}'      > "$CLAUDE_COMPANION_TASKS_DIR/sB/1.json"
  jq -n '{id:"2",subject:"beta B2",status:"pending"}'      > "$CLAUDE_COMPANION_TASKS_DIR/sB/2.json"
  # a third repo's dir must not leak in, and a marker-less dir must not match by accident
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sC"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sC/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sC/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sD"
  jq -n '{id:"1",subject:"UNSTAMPED",status:"pending"}'    > "$CLAUDE_COMPANION_TASKS_DIR/sD/1.json"

  # Pass a RESOLVED root, which is what every real caller does (they go through companion_root).
  # `cd` into a symlinked path leaves $PWD logical, so passing it compares an unresolved path
  # against a resolved stamp and silently matches nothing.
  run bash -c 'cd "$1" && source "$2" && companion_open_tasks "$(git rev-parse --show-toplevel)"' _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  # every OPEN task across BOTH matching dirs survives the batch — the count is the real assertion.
  # Both markers, since open means pending (◻) OR in_progress (▸) and alpha A2 is the latter.
  [ "$(printf '%s\n' "$output" | grep -c '[◻▸]')" -eq 4 ]
  [[ "$output" == *"alpha A1"* ]] && [[ "$output" == *"alpha A2"* ]]
  [[ "$output" == *"beta B1"*  ]] && [[ "$output" == *"beta B2"*  ]]
  [[ "$output" != *"alpha A3"* ]]    # completed excluded
  [[ "$output" != *"NOT MINE"* ]]    # no cross-repo bleed
  [[ "$output" != *"UNSTAMPED"* ]]   # an unmarked dir is not a match
  # and it stays a SINGLE jq: batching is the point, so a regression to per-file is a failure
  local n; n="$(cd "$repo" && strace -f -e trace=execve -o /dev/stdout \
      bash -c 'source "$1"; companion_open_tasks "$PWD"' _ "$ROOT/lib/companion.sh" 2>/dev/null \
      | grep -c 'execve("[^"]*/jq"' || true)"
  [ -z "$n" ] || [ "$n" -le 1 ]      # skips cleanly where strace is unavailable (macOS CI)
}

@test "resume: RECENT out-of-band changes print; old ones and no-file cost nothing (R93, now on-demand only)" {
  # The failure this exists for is CONTEXT LOSS: clear the state, open a bug, and the fact that
  # something relevant changed last week is gone. R93's own reasoning was that this must arrive
  # UNASKED because "go look" cannot survive that — pulling it on demand instead (R100/Pass 2, no
  # hook left to inject it automatically) reopens exactly that failure. Recorded honestly, not
  # fixed: this test now proves the content survives the mechanism change, not that the original
  # guarantee still holds — it doesn't.
  local r; r="$(_tmpd)"; git -C "$r" init -q; mkdir -p "$r/docs"
  local today old
  today="$(date -u +%Y-%m-%d)"
  old="$(date -u -d '-60 days' +%Y-%m-%d 2>/dev/null || date -u -v-60d +%Y-%m-%d)"
  printf '## Log\n\n- %s · aws · widened the RDS security group\n  could break: auth callbacks\n- %s · dns · moved the apex A record\n' \
    "$today" "$old" > "$r/docs/CHANGES-OUTSIDE-GIT.md"
  _ctx() { run bash -c 'cd "$1" && "$2"' _ "$1" "$RESUME"; }

  _ctx "$r"
  [[ "$output" == *"widened the RDS security group"* ]]   # recent entry rides in, unasked
  [[ "$output" == *"could break: auth callbacks"* ]]      # ...with its continuation line
  [[ "$output" != *"apex A record"* ]]                    # 60 days old: history, not noise

  # a repo with NO ledger contributes NOTHING — the whole cost argument rests on this
  local p2; p2="$(_tmpd)"; git -C "$p2" init -q
  _ctx "$p2"
  [[ "$output" != *"Changed OUTSIDE"* ]]
}

@test "rework ledger: counts FAILURES not touches, flags a rebuild candidate, and resume prints it (R94)" {
  # Owner: "Claude seems to be making more and more obvious mistakes requiring rework then telling
  # me about how it caught the mistakes." A caught mistake reported as an apparatus win reframes a
  # defect rate as a success. This makes the rate a number, and surfaces it unasked.
  local r st; r="$(_tmpd)"; git -C "$r" init -q; st="$(_tmpd)"
  local RW="$ROOT/bin/rework.sh"
  _rw() { run env CLAUDE_COMPANION_STATE_DIR="$st" REWORK_ROOT="$r" bash "$RW" "$@"; }

  _rw report; [ "$status" -eq 0 ]; [[ "$output" == *"none recorded"* ]]

  # the event that matters most: the owner had to supply the answer
  _rw record owner-supplied; [ "$status" -eq 0 ]
  _rw report; [[ "$output" == *"owner-supplied"* ]]

  # three FAILURES against one file make it a rebuild candidate; the offer names the command
  _rw record gate-fail src/auth.js
  _rw record ci-red   src/auth.js
  _rw record hole     src/auth.js
  _rw report
  [[ "$output" == *"src/auth.js"* ]]; [[ "$output" == *"redesign"* ]]

  # ...but a file seen ONCE is not a candidate — this counts failures, not churn
  [[ "$output" != *"src/other.js"* ]]
  _rw record gate-fail src/other.js
  _rw report; [[ "$output" != *"⟳ src/other.js"* ]]

  # and it shows up whenever resume is called
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3"' _ "$r" "$st" "$RESUME"
  [[ "$output" == *"REWORK already recorded"* ]]

  # a repo with nothing recorded contributes NOTHING
  local clean; clean="$(_tmpd)"; git -C "$clean" init -q
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3"' _ "$clean" "$st" "$RESUME"
  [[ "$output" != *"REWORK already recorded"* ]]
}

@test "resume: carried tasks render the done-when + LATEST note sub-lines (R56 G2 — R47/PR126 resume enrichment)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=rEn; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"carry me",status:"pending",done_when:"green tests",notes:[{ts:"t1",text:"first crumb"},{ts:"t2",text:"latest crumb"}]}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carry me"* ]]                 # the task surfaces
  [[ "$output" == *"done when: green tests"* ]]   # acceptance re-surfaced (the R47 resume side)
  [[ "$output" == *"note: latest crumb"* ]]       # LATEST note (PR #126), not the first
  [[ "$output" != *"note: first crumb"* ]]        # only the latest, not the whole trail
}

# ---- crash resume: what an interrupted session leaves behind, and what says so on the way back ----

@test "resume: an in_progress task renders ▸ (mid-flight), a pending one ◻ — a crash left them different" {
  # Both statuses used to render "◻", so the task a crashed session was actually WORKING ON came
  # back indistinguishable from one merely queued — the queue knew where the work stopped and the
  # resume path threw it away.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=rIP; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"merely queued",status:"pending"}'    > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"was mid-flight",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▸ was mid-flight"* ]]
  [[ "$output" == *"◻ merely queued"* ]]
  [[ "$output" != *"◻ was mid-flight"* ]]
}

@test "resume: dirty tree + NO task in_progress warns UNRECONCILED and names the files" {
  # The crash case the durable queue does not already cover: edits survive on disk, but nothing in
  # the queue claims them, so the next session cannot tell 10%-done from 90%-done.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/tracked.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  local sid=rUn; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"open but unclaimed",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  echo edited >> "$repo/tracked.txt"; echo brand-new > "$repo/untracked.txt"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRECONCILED WORK"* ]]
  [[ "$output" == *"2 uncommitted change(s)"* ]]
  [[ "$output" == *"NO task is in_progress"* ]]
  [[ "$output" == *"tracked.txt"* ]] && [[ "$output" == *"untracked.txt"* ]]
  [[ "$output" == *"tq doing"* ]]                 # says what to DO about it, not just that it is so
}

@test "resume: UNRECONCILED is silent on a clean tree, and silent while a task IS in_progress" {
  # A warning that fires when there is nothing to reconcile gets ignored, which costs the warning
  # its whole value on the one session where it matters.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  local sid=rQu; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"queued",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # clean tree -> nothing to say
  # now dirty it, but leave a proper breadcrumb: the mid-flight task IS the reconciliation
  echo edited >> "$repo/f.txt"
  jq -n '{id:"2",subject:"claimed it",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # breadcrumb present -> the warning stands down
  [[ "$output" == *"▸ claimed it"* ]]             # …and the mid-flight task is what shows instead
}

@test "resume: UNRECONCILED ignores the companion's OWN store — it must not warn about its bookkeeping" {
  # .companion/ is untracked in most projects. Counting it would make this fire every single
  # session, which is the same as not having it.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  mkdir -p "$repo/.companion/tasks"
  jq -n '{id:"1",subject:"in the repo store",status:"pending"}' > "$repo/.companion/tasks/1.json"
  local sid=rSelf; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # only the store is dirty -> silent
  echo edited >> "$repo/f.txt"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" == *"UNRECONCILED"* ]]             # a REAL edit appears -> it fires…
  [[ "$output" == *"1 uncommitted change(s)"* ]]  # …counting 1, not 2: the store never counted
}

@test "session-start: the UNRECONCILED warning reaches the HOOK path too, not just manual resume" {
  # session-start.sh is the one that fires after a crash without anyone asking, so the warning is
  # worth nothing if it only rides the manual pull.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  echo edited >> "$repo/f.txt"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRECONCILED WORK"* ]]
  [[ "$output" == *"f.txt"* ]]
}

@test "resume: an UNSTAMPED store dir holding open work is reported as UNREACHABLE" {
  # `tq` only writes stamps on `add`, so once the owning session is gone a stamp-less dir can never
  # heal itself — no later `add` runs there. Its open tasks are invisible to every repo forever.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/ghost"          # deliberately NO .repo and NO .root
  jq -n '{id:"1",subject:"lost work",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/ghost/1.json"
  jq -n '{id:"2",subject:"also lost",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/ghost/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNREACHABLE QUEUE"* ]]
  [[ "$output" == *"2 open"* ]]                          # counts open only, and both statuses count
  [[ "$output" == *"ghost"* ]]                           # names the directory so it can be acted on
}

@test "resume: UNREACHABLE never reports another repo's dir — a stamp is a stamp even if that repo is not here" {
  # THE bleed guard. The first draft required the .root path to exist on disk, and immediately
  # reported a dir belonging to a repo that simply was not mounted — turning a cross-project-safety
  # feature into the cross-project leak it exists to prevent. Absent path = repo elsewhere, not
  # unclaimable. Also: a stamp-less dir whose tasks are all FINISHED is dead weight, not lost work.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/elsewhere"
  printf '%s' "/no/such/path/anymore" > "$CLAUDE_COMPANION_TASKS_DIR/elsewhere/.root"
  jq -n '{id:"1",subject:"theirs",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/elsewhere/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/byid"
  printf '%s' "some-identity" > "$CLAUDE_COMPANION_TASKS_DIR/byid/.repo"
  jq -n '{id:"1",subject:"id-stamped",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/byid/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/spent"          # unstamped, but nothing open in it
  jq -n '{id:"1",subject:"finished",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/spent/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNREACHABLE"* ]]
  [[ "$output" != *"theirs"* ]]                          # and no other repo's task text leaks in
}

@test "resume: a store path containing a NEWLINE still returns the whole backlog" {
  # Found by the pre-ship adversarial pass: extracting companion_task_files made it hand paths back
  # newline-separated, and a store path with a newline in it split one path into two non-existent
  # ones — every task silently rendered as ZERO, on the one path whose entire job is handing the
  # backlog back after a crash. Same total-loss shape as the corrupt-file abort, different cause.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local root; root="$(git -C "$repo" rev-parse --show-toplevel)"
  local weird="$CLAUDE_COMPANION_TASKS_DIR/we"$'\n'"ird"
  mkdir -p "$weird"; printf '%s' "$root" > "$weird/.root"
  jq -n '{id:"1",subject:"still here",status:"pending"}'  > "$weird/1.json"
  jq -n '{id:"2",subject:"mid-flight",status:"in_progress"}' > "$weird/2.json"
  run bash -c 'cd "$1" && . "$2" && companion_open_tasks "$(git rev-parse --show-toplevel)"' \
    _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"still here"* ]]
  [[ "$output" == *"▸ mid-flight"* ]]
}

@test "resume: UNRECONCILED survives a corrupt task file — a bad file must not hide a mid-flight task" {
  # companion_any_in_progress batches its jq, and jq aborts at the first unparseable file. If the
  # batch failure were read as "nothing in progress", one torn write would resurrect the warning on
  # top of work that WAS properly claimed — noise exactly when the store is already damaged.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  echo edited >> "$repo/f.txt"
  local sid=rCor; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  printf '{ NOT VALID JSON' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"claimed it",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNRECONCILED"* ]]             # the mid-flight task is still found
}

@test "resume: keeps the recommendation-contract clause (R56 G3 — R49), since it now rides in the full core every call" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation-first"* ]]   # the R49 posture — always present now, not just after a compaction
}

@test "STEERING cap may only RATCHET DOWN — a raise must be funded by a deletion (2026-08-16 audit)" {
  # The cap rose EIGHT times (6144->8730, +42%) and ended at 8725/8730 with five bytes of headroom,
  # each raise a one-character edit inside an unrelated change. This makes raising it a two-place,
  # deliberate act: the gate AND this test. It cannot stop a determined author and should not — it
  # only removes "nobody noticed" as an explanation.
  # The cap moved into dev/token-budget.sh with the byte-cap section (2026-08-16); the guard
  # follows the constant, or it silently stops guarding anything.
  run grep -E '^core_cap=[0-9]+$' "$DEV/token-budget.sh"
  [ "$status" -eq 0 ]
  local cap="${output#core_cap=}"
  [ -n "$cap" ]
  [ "$cap" -le 8500 ]
}

@test "resume: carries BOTH halves of the posture — the options half and the honesty-rides-the-pick half (R80)" {
  # R80's original "the verdict is unconditional" clause was already reversed by R80·b (2026-08-03);
  # what survives here is the OTHER half: the honest read stays attached to the recommendation, not
  # tacked onto every reply. R30·d2's separate abbreviated compact path is gone with the hook it
  # lived in (R100/Pass 2) — resume now always shows the full core, which already contains both
  # halves, so there is no longer a distinct "does the short path drop one" case to guard.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation-first"* ]]      # the options half
  [[ "$output" == *"goes ON the pick"* ]]           # honesty rides the pick (the closing verdict is RETIRED, R80·b)
  [[ "$output" == *"Posture"* ]]                    # the core (incl. this section) DOES ride now (R30·d2 retired with the hook)
}


@test "resume: ONE corrupt task file loses only ITSELF, never the whole backlog (DA blocker)" {
  # The batched jq aborts at the first parse error, so a single half-written file took every task
  # in every LATER file with it — 7 open tasks rendering as 0, silently, on the one path whose job
  # is handing the backlog back after a crash. The per-file fallback is what makes that survivable.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/cA" "$CLAUDE_COMPANION_TASKS_DIR/cB"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/cA/.repo"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/cB/.repo"
  printf '{ NOT VALID JSON' > "$CLAUDE_COMPANION_TASKS_DIR/cA/1.json"
  local i
  for i in 2 3 4;   do jq -n --arg i "$i" '{id:$i,subject:"alpha \($i)",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/cA/$i.json"; done
  for i in 5 6 7 8; do jq -n --arg i "$i" '{id:$i,subject:"beta \($i)",status:"pending"}'  > "$CLAUDE_COMPANION_TASKS_DIR/cB/$i.json"; done
  run bash -c 'cd "$1" && . "$2" && companion_open_tasks "$PWD"' _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◻')" -eq 7 ]   # all 7 healthy tasks, not 0
  [[ "$output" == *"alpha 2"* ]] && [[ "$output" == *"beta 8"* ]]
}

@test "resume: LESSONS is two-tier — only the core above the marker prints (R69/R30·d7)" {
  # The cap is on PRINTED bytes, not on the file. Before the split, LESSONS sat 5B under its
  # ceiling while the process told every session to append to it, so each new lesson was paid for
  # by deleting a true one — two real remedies were lost that way before this landed.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; mkdir -p "$repo/docs"
  cat > "$repo/docs/LESSONS.md" <<'EOF'
# Lessons
- ALPHA-CORE-TRAP always injected
<!-- lessons injection stops here -->
- OMEGA-ONDEMAND-TRAP read on demand only
EOF
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL "$4"' _ "$repo" "$(_tmpd)" "$(_tmpd)" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALPHA-CORE-TRAP"* ]]        # the core rides every call...
  [[ "$output" != *"OMEGA-ONDEMAND-TRAP"* ]]    # ...the tail does not, which is the whole point
  [[ "$output" != *"lessons injection stops here"* ]]   # and the marker itself is never printed

  # FAILS OPEN on a file with no marker — a stranger's repo (R9) keeps working, whole file prints.
  printf '# Lessons\n- ZETA-UNSPLIT-TRAP\n' > "$repo/docs/LESSONS.md"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL2 "$4"' _ "$repo" "$(_tmpd)" "$(_tmpd)" "$RESUME"
  [[ "$output" == *"ZETA-UNSPLIT-TRAP"* ]]
}

@test "resume: autopilot mode prose rides ONLY when the mode WAS armed at call time (R69)" {
  # ~2.7KB of mode rules that are dead weight in every session where autopilot is off — which is
  # most of them. Conditional, not deleted: when the mode IS on the rules are exactly as present as
  # they ever were. This is rent paid per call forever, so the gate is worth having. Checked
  # PRE-clear (resume.sh always disarms autopilot as its own first step, R39) — "armed at call
  # time" is what decides whether the prose shows, not the state after resume has already run.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp "$3"' \
      _ "$repo" "$st" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core always rides...
  [[ "$output" != *"Keep-going mode"* ]]          # ...the mode prose does not
  [[ "$output" != *"autopilot:start"* ]]          # and the delimiter never leaks
  local off_len="${#output}"

  ( cd "$repo" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" on ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp2 "$3"' \
      _ "$repo" "$st" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keep-going mode"* ]]          # armed → the rules are there
  [[ "$output" == *"park with the full payload"* ]]
  [ "${#output}" -gt "$off_len" ]
}

@test "prompt-continue: a bare 'continue' with a parked pile routes to review FIRST (R85)" {
  # The owner types "continue" and gets more building on top of decisions they were never asked
  # about. As STEERING prose this is a reflex the model can skip; as an injection it cannot be,
  # and it costs nothing in every session where nothing is parked.
  local d st tk; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$tk/sP"; _stamp_root "$tk/sP" "$d"
  _pc() { run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' \
            _ "$(jq -nc --arg c "$d" --arg p "$1" '{cwd:$c,session_id:"sP",prompt:$p}')" "$st" "$tk" "$ROOT/bin/prompt-continue.sh"; }

  _pc continue; [ "$status" -eq 0 ]; [ -z "$output" ]        # empty queue → silent
  jq -n '{id:"1",subject:"plain buildable work",status:"pending"}' > "$tk/sP/1.json"
  _pc continue; [ -z "$output" ]                              # buildable work → just drain, silently
  jq -n '{id:"2",subject:"❓ [parked] pick a backend; rec: A",status:"pending"}' > "$tk/sP/2.json"
  _pc continue
  [[ "$output" == *"/companion:review"* ]]; [[ "$output" == *"WHOLE pile"* ]]
  # The ordering is the whole point of the hook, so pin it: unblocking outranks everything, and
  # the model must not answer a parked decision on the owner's behalf.
  [[ "$output" == *"HIGHEST PRIORITY"* ]]
  # The OPENING imperative, not just the ranking further down: a declared mutation replaced
  # "STOP — DO NOT START ANY OTHER WORK YET" with a mild "Note:" and the suite stayed green for
  # three shipped commits, because every assertion here read a LATER sentence. An injection that
  # opens with "Note:" is advisory, which is exactly what this hook exists not to be.
  [[ "$output" == *"STOP — DO NOT START ANY OTHER WORK YET"* ]]
  [[ "$output" == *"do not answer one of these on their behalf"* ]]
  [[ "$output" == *"no pause is needed"* ]]                   # autopilot off
  # ARMED: it must say pause first, because the ask-guard would otherwise PARK the review's own
  # questions instead of asking them — the review would silently accomplish nothing.
  mkdir -p "$st/autopilot"; touch "$(_flagpath "$st" autopilot "$d")"
  _pc continue
  [[ "$output" == *"autopilot.sh pause"* ]] && [[ "$output" == *"resume"* ]]
  [[ "$output" == *"never leave autopilot off"* ]]     # resume is not optional
  # A ⏳ alone counts too — manual jobs are equally the owner's.
  rm "$tk/sP/2.json"; jq -n '{id:"3",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$tk/sP/3.json"
  _pc continue; [[ "$output" == *"/companion:review"* ]]
  # A REAL instruction is never second-guessed, even when it starts with the word.
  _pc "continue by refactoring the parser"; [ -z "$output" ]
  _pc "Keep going."; [[ "$output" == *"/companion:review"* ]]   # punctuation and case tolerated
}

@test "resume: warns when the INSTALLED plugin lags this working tree (R6)" {
  # Claude Code runs the plugin from its CACHE, not the checkout you are editing. On 2026-08-02 a
  # session opened on a cache with no UserPromptSubmit registration at all, so every hook added
  # that day was inert while the repo was green — six hours of work reported as shipped that was
  # not running. Nothing surfaced it; the status line showed the old version and neither of us
  # read it as a warning.
  local repo st tk running
  repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$repo/plugins/companion/.claude-plugin"
  running="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  _ss2() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" "$4"' \
             _ "$repo" "$st" "$tk" "$RESUME"; }

  # Tree AHEAD of the running build → warn, and name both versions.
  jq -n '{name:"companion",version:"9.9.9"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [ "$status" -eq 0 ]
  [[ "$output" == *"RUNNING v${running}"* ]]; [[ "$output" == *"9.9.9"* ]]; [[ "$output" == *"INERT"* ]]

  # Same version → silent. A warning that fires when nothing is wrong is noise nobody reads.
  jq -n --arg v "$running" '{name:"companion",version:$v}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [[ "$output" != *"RUNNING v"* ]]

  # A DIFFERENT plugin's manifest is not this plugin — must not warn on someone else's repo (R9).
  jq -n '{name:"somebody-elses-plugin",version:"0.0.1"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [[ "$output" != *"RUNNING v"* ]]

  # An ordinary repo with no plugin manifest at all → silent.
  rm -rf "$repo/plugins"
  _ss2; [ "$status" -eq 0 ]; [[ "$output" != *"RUNNING v"* ]]
}
@test "session-start: fresh start injects the FULL STEERING core + carried tasks, unlike resume it does NOT clear autopilot" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sX"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sX" "$repo"
  jq -n '{id:"1",subject:"carried via session-start",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sX/1.json"
  ( cd "$repo" && "$AP" on ) >/dev/null

  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]           # STEERING core, unlike prompt-continue/ask-guard
  [[ "$output" == *"carried via session-start"* ]]    # this repo's carried task
  run bash -c 'cd "$1" && "$2" status' _ "$repo" "$AP"
  [ "$output" = "on" ]                                # NOT cleared — the whole point vs resume.sh
}

@test "session-start: post-compaction re-anchor is SHORT — queue + posture, not the full STEERING core" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sY"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sY" "$repo"
  jq -n '{id:"1",subject:"survives compaction",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sY/1.json"

  _ss_ctx "$repo" "compact"
  [ "$status" -eq 0 ]
  [[ "$output" == *"just compacted"* ]]
  [[ "$output" == *"survives compaction"* ]]          # the live queue re-anchors
  [[ "$output" == *"recommendation-first options"* ]]  # the posture clause, restated (R49)
  [[ "$output" != *"## The two reflexes"* ]]           # NOT the full STEERING core (token cost, R69)
}

@test "session-start: compact re-anchor carries the SAME version-lag + rework as a fresh start (R93 — a compaction IS a state clear)" {
  local repo st tk; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$repo/plugins/companion/.claude-plugin"
  jq -n '{name:"companion",version:"9.9.9"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"compact\"}" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" "$4" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$st" "$tk" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"just compacted"* ]]
  [[ "$output" == *"RUNNING v"* ]]                     # version-lag warning, not skipped on compact
  [[ "$output" == *"INERT"* ]]
}

@test "session-start: steering=off drops the working agreement, carried tasks unaffected (R50)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off steering "$repo"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sZ"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sZ" "$repo"
  jq -n '{id:"1",subject:"still carried",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sZ/1.json"

  _ss_ctx "$repo" ""
  [[ "$output" != *"Working agreement"* ]]
  [[ "$output" != *"Read the working agreement below"* ]]   # DA-caught: the preamble told the
  # model to read a block that steering=off had already dropped — token waste dressed up as a
  # correct render, exactly the R69 carelessness this test exists to pin.
  [[ "$output" == *"still carried"* ]]
  _feature_clear
}

@test "session-start: self-contained fallback — a marker-less plugin dir still reaches lib/resume-report.sh" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local plug; plug="$(_tmpd)"; mkdir -p "$plug/bin" "$plug/lib"
  cp "$SS" "$plug/bin/session-start.sh"
  cp "$ROOT/lib/companion.sh" "$ROOT/lib/resume-report.sh" "$plug/lib/"
  cp "$ROOT/STEERING.md" "$plug/STEERING.md"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2/bin/session-start.sh" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$plug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]
}

@test "STEERING: the observation-point reflex reaches a session through the REAL hook (R109 steering half)" {
  # R106's precedent: pin DELIVERY, not mere presence in a file. A line that exists but never
  # reaches a session is the same nothing as a line that was never written — and this repo has
  # shipped that exact nothing twice (the retired capture hook, the inert plugin cache).
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2"' _ "$repo" "$SS"
  [ "$status" -eq 0 ]

  # The three shapes. Each names a way a real 2026-08-10 miss slipped past a check that passed.
  [[ "$output" == *"built ≠ running"* ]]        # the fix that was never deployed
  [[ "$output" == *"typed ≠ resolved"* ]]       # typecheck cannot see string-typed router paths
  [[ "$output" == *"refused ≠ accepted"* ]]     # the approval gate's accept path

  # THE DEEPEST ONE, and the only one no mechanism can cover: an agent ruling something untestable
  # is making a DECISION (verification traded for delivery) while it looks like a fact about the
  # world, so it never enters the parked pile. pty.openpty() was available the whole time.
  [[ "$output" == *"never a conclusion"* ]]
  [[ "$output" == *"asking how"* ]]

  # The owner naming their runtime makes THAT runtime the target — the three-day-old bundle server.
  [[ "$output" == *"what is actually serving it"* ]]
}
