#!/usr/bin/env bats
#
# AUTONOMY - autopilot, its guards (ask-guard/stop-autopilot), burn-down, candidates and generated branches.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper


# ---- autopilot (persisted, ADVISORY as of R100/Pass 4 — ask-guard.sh and stop-autopilot.sh
#      retired; nothing enforces this flag anymore, STEERING states it) ----

@test "autopilot: toggle persists per repo, independent of other modes (R26)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  [ "$(cd "$repo" && "$AP" status)" = "off" ]
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "on" ]                       # persisted flag
  ( cd "$repo" && "$AP" off ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "off" ]
}

@test "modes are REPO state: they survive a wiped state dir and do not block burn-down (R96)" {
  local AP2="$ROOT/bin/autopilot.sh"
  local r h1 h2; r="$(_tmpd)"; git -C "$r" init -q; h1="$(_tmpd)"; h2="$(_tmpd)"
  ( cd "$r" && CLAUDE_COMPANION_STATE_DIR="$h1" bash "$AP2" on ) >/dev/null

  # the flag is a file IN THE REPO, so git carries it to a cloud agent or a fresh container
  [ -f "$r/.companion/modes/autopilot" ]
  # ...AND the legacy location, because the CLI runs from the repo while HOOKS are served from the
  # installed cache — writer and reader are routinely different versions of this plugin. New code
  # reads the legacy flag; OLD code cannot read the new one. Writing only the repo flag left
  # `autopilot on` reporting ON while the installed Stop hook saw OFF and stood down every turn,
  # with work sitting in the queue. Dual-write is what makes the move survivable across versions.
  [ -f "$(_flagpath "$h1" autopilot "$r")" ]
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r" "$h2" "$AP2"
  [ "$output" = "on" ]                       # h2 is a BRAND-NEW state dir: $HOME wiped

  # off must clear it everywhere, or a stale flag resurrects a mode the owner turned off
  ( cd "$r" && CLAUDE_COMPANION_STATE_DIR="$h1" bash "$AP2" off ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r" "$h1" "$AP2"
  [ "$output" = "off" ]
  [ ! -f "$r/.companion/modes/autopilot" ]
  [ ! -f "$(_flagpath "$h1" autopilot "$r")" ]     # BOTH cleared, or an old reader stays armed

  # a LEGACY home-scoped flag is still honoured, so upgrading does not silently lose a mode...
  local r2 h3; r2="$(_tmpd)"; git -C "$r2" init -q; h3="$(_tmpd)"
  mkdir -p "$h3/autopilot"; touch "$(_flagpath "$h3" autopilot "$r2")"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r2" "$h3" "$AP2"
  [ "$output" = "on" ]
  # ...and turning it off clears the legacy one too
  ( cd "$r2" && CLAUDE_COMPANION_STATE_DIR="$h3" bash "$AP2" off ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r2" "$h3" "$AP2"
  [ "$output" = "off" ]

  # plugin state must NOT count as a dirty tree, or arming burn-down disables burn-down; the
  # owner's own uncommitted work still must.
  local r3 st3; r3="$(_tmpd)"; st3="$(_tmpd)"
  git -C "$r3" init -q -b main; git -C "$r3" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$r3/.companion/modes"; : > "$r3/.companion/modes/burndown"
  run env CLAUDE_COMPANION_STATE_DIR="$st3" BURNDOWN_ROOT="$r3" bash "$ROOT/bin/burndown-branch.sh" start '3|todo|only plugin state dirty'
  [ "$status" -eq 0 ]
  git -C "$r3" checkout -q main
  printf 'the owner work\n' > "$r3/notes.txt"
  run env CLAUDE_COMPANION_STATE_DIR="$st3" BURNDOWN_ROOT="$r3" bash "$ROOT/bin/burndown-branch.sh" start '3|todo|real dirt'
  [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
}

@test "candidates: the ladder escalates small-first and ends at a REBUILD before inventing (R82/R94)" {
  # The owner asked for small work first, escalating as it is exhausted. That is a ladder of
  # PROVENANCE, not of size: a complexity dial was asked for and rejected because the agent would
  # be scoring its own work unauditably (contract-guard.sh). A repeatedly-FAILING component is the
  # largest recorded signal there is, so it ranks after every cleanup and before invention.
  local r st; r="$(_tmpd)"; st="$(_tmpd)"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  _cand() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" REWORK_ROOT="$1" "$3"' _ "$r" "$st" "$ROOT/bin/candidates.sh"; }

  # nothing recorded → invention, explicitly labelled, at the BOTTOM of the ladder
  _cand; [[ "$output" == *"|invent|"* ]]

  # three recorded FAILURES against one file make it a rebuild candidate, ranked above invention
  local RW="$ROOT/bin/rework.sh"
  for k in gate-fail ci-red hole; do
    run env CLAUDE_COMPANION_STATE_DIR="$st" REWORK_ROOT="$r" bash "$RW" record "$k" src/flaky.js
  done
  _cand
  [[ "$output" == *"5|rework|"* ]]; [[ "$output" == *"src/flaky.js"* ]]
  [[ "$output" != *"|invent|"* ]]                 # invention is suppressed while a signal remains

  # a genuine TODO in source outranks the rebuild — small work first
  mkdir -p "$r/src"; printf '// TODO: bound the retry loop\n' > "$r/src/a.js"
  git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m todo
  _cand
  [[ "$output" == "3|todo|"* ]]

  # ...but PROSE about TODO markers in the contract is not a task. Excluding markdown alone was
  # never the rule; this repo's contract is yaml, and its own description of the scanner was being
  # offered as work to do.
  local r2 st2; r2="$(_tmpd)"; st2="$(_tmpd)"
  git -C "$r2" init -q -b main
  mkdir -p "$r2/docs"; printf 'note: >\n  Covers TODO detection across ecosystems\n' > "$r2/docs/contract.yaml"
  git -C "$r2" add -A; git -C "$r2" -c user.email=t@t -c user.name=t commit -q -m c
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" REWORK_ROOT="$1" "$3"' _ "$r2" "$st2" "$ROOT/bin/candidates.sh"
  [[ "$output" != *"|todo|"* ]]
}

@test "autopilot decisive (R59): toggle persists, independent of plain autopilot" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "off" ]           # off by default
  ( cd "$repo" && "$AP" decisive on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "on" ]            # persisted flag
  ( cd "$repo" && "$AP" off ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "on" ]            # decisive outlives plain autopilot toggling off
}
@test "autopilot sweep: flag persists per-repo and is independent of ship/decisive (R77)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "off" ]
  ( cd "$repo" && "$AP" sweep on ) >/dev/null
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "on" ]
  run bash -c 'cd "$1" && "$2" decisive status' _ "$repo" "$AP"; [ "$output" = "off" ]
  ( cd "$repo" && "$AP" sweep off ) >/dev/null
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "off" ]
}

@test "autopilot sweep: OFF stops on a parked-only queue, ON works a rev: park (R77)" {
  local repo; repo="$(_sw_repo)"; cd "$repo"
  _sw_task "❓ [parked] rev: colour scheme — options: A) dark B) light; rec: A + matches the app" 1
  [ -z "$(_sw_next false)" ]                  # sweep off: parked-only -> nothing startable
  [[ "$(_sw_next true)" == *"colour scheme"* ]]  # sweep on: the rev: park is work
}

@test "autopilot sweep: an IRREVERSIBLE park (no rev: marker) is never eligible (R77/R59)" {
  # The case that killed the first design: decisive mode parks ONLY the irreversible and writes
  # `rec:` on it, so a rec-based filter selected precisely the set it had to protect.
  local repo; repo="$(_sw_repo)"; cd "$repo"
  _sw_task "❓ [parked] force-push the rewrite to origin/main — options: A) force B) PR; rec: A + why" 1
  [ -z "$(_sw_next)" ]
  _sw_task "❓ [parked] delete the staging bucket and its snapshots — options: A) delete B) keep; rec: A + cost" 2
  [ -z "$(_sw_next)" ]                        # still nothing sweepable
  _sw_task "❓ [parked] rev: button copy — options: A) Save B) Done; rec: A + clearer" 3
  [[ "$(_sw_next)" == *"button copy"* ]]      # only the marked-reversible one is work
  [[ "$(_sw_next)" != *"force-push"* ]]
  [[ "$(_sw_next)" != *"delete the staging bucket"* ]]
}

@test "autopilot sweep: ⏳, decompose:, unrecorded and prose-only markers stay excluded (R77/R65)" {
  local repo; repo="$(_sw_repo)"; cd "$repo"
  # each fixture carries EVERY other marker, so it can only be excluded by the rule it targets
  _sw_task "⏳ [blocked] rev: delete the production bucket; rec: yes do it" 1
  _sw_task "❓ [parked] rev: Decompose: migrate the store — need: which fields; rec: split by table" 2
  _sw_task "❓ [parked] rev: drop the legacy table? — A) drop B) keep; no rec: recorded, this one is yours" 3
  _sw_task "❓ [parked] mentions rev: only in prose here; rec: A + why" 4
  [ -z "$(_sw_next)" ]                        # not one of them is eligible
  _sw_task "❓ [parked] rev: wording — options: A) terse B) chatty; rec: A + the voice" 5
  [[ "$(_sw_next)" == *"wording"* ]]
  [[ "$(_sw_next)" != *"production bucket"* ]]
  [[ "$(_sw_next)" != *"migrate the store"* ]]
  [[ "$(_sw_next)" != *"legacy table"* ]]
}
@test "burn-down: HOLD is the default and every unknown resolves to it" {
  _bd_setup
  # OFF is the shipped state. This mode authors work, so arming it must be a deliberate act.
  rm -rf "$BD_STATE/burndown"
  _bd 10; [ "$status" -eq 0 ]; [[ "$output" == HOLD:* ]]; [[ "$output" == *"OFF for this repo"* ]]
  mkdir -p "$BD_STATE/burndown"
  touch "$(_flagpath "$BD_STATE" burndown "$BD_REPO")"
  # No snapshot at all — the status line may simply not be wired. Cannot forecast, so hold.
  rm -f "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"no rate-limit snapshot"* ]]
  # A STALE snapshot is not a forecast — old data would let it burn on a window that already rolled.
  _bd 10 20 99999; [[ "$output" == HOLD:* ]]; [[ "$output" == *"stale data"* ]]
  # Garbage in the snapshot must not become a number.
  printf 'not-a-timestamp junk\n' > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [ "$status" -eq 0 ]; [[ "$output" == HOLD:* ]]
}

@test "burn-down: burns ONLY on a forecast underspend, never when on track" {
  _bd_setup
  # 90% used with one day left projects to 105% — on track, so there is no spare capacity to fill.
  _bd 90; [[ "$output" == HOLD:* ]]; [[ "$output" == *"on track"* ]]
  # 10% with one day left projects to ~11% — a genuine underspend.
  _bd 10; [[ "$output" == BURN:* ]]; [[ "$output" == *"tracking to"* ]]
  # The target is what it stops at, and it is configurable: aim at 10% and the same state is fine.
  run env BURNDOWN_TARGET_PCT=10 CLAUDE_COMPANION_STATE_DIR="$BD_STATE" \
      CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
}

@test "burn-down: in the FINAL STRETCH only actual usage counts, and the branch cap lifts (R82)" {
  _bd_setup
  # snapshot fields: ts · used5 · reset5 · used7 · reset7
  _bd_left() {  # $1=used7 · $2=seconds left in the 7d window
    # Seed the earlier reading DIRECTLY, 600s back (R119). It used to be seeded by running
    # burn-down once and discarding it, which only worked because burn-down wrote its own samples —
    # and that self-writing was the defect being fixed: it meant sampling happened only when
    # evaluating happened. The status line is the sampler now, so the fixture writes what it would.
    printf '%s %s\n' "$(( $(date +%s) - 600 ))" "$1" > "$BD_STATE/burndown-lastsample"
    printf '%s %s %s %s %s\n' "$(date +%s)" 20 "$(( $(date +%s)+7200 ))" "$1" "$(( $(date +%s)+$2 ))" \
      > "$BD_STATE/ratelimit"
    run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
        BURNDOWN_BRANCHES_PER_DAY="${_PERDAY:-3}" \
        BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  }

  # OUTSIDE the stretch, a projection is sound: 90% with a full day left tracks to ~105%, so the
  # sustained rate gets there on its own and there is no spare capacity to fill.
  _bd_left 90 90000; [[ "$output" == HOLD:* ]]; [[ "$output" == *"on track"* ]]   # clear of the boundary

  # INSIDE it, that same projection is exactly what loses budget — it assumes you keep spending at
  # your average, and a night asleep in the last hours is spending that never happens. Only what is
  # ACTUALLY used counts, so the same 90% now burns.
  # 80000s, NOT 3600s: with an hour left the projection collapses to ~= actual usage, so both rules
  # agree and the case proves nothing — it reported "caught" while the stretch test was mutated to
  # `if true`. Just inside the boundary the projection still reads 103% while usage is 90%, which is
  # the only shape where the two rules genuinely disagree.
  _bd_left 90 80000; [[ "$output" == BURN:* ]]
  [[ "$output" =~ needs\ [1-9][0-9]*%/window ]]  # a REAL required rate — `needs 0%` also matched before

  # ...but at or past the target there is genuinely nothing left to burn, in any stretch.
  # 3600 below is SECONDS-LEFT, deep inside the 86400s stretch; it only coincides with FRESH=3600,
  # which measures snapshot AGE, and the age here is 0.
  _bd_left 100 3600; [[ "$output" == HOLD:* ]]; [[ "$output" == *"nothing left"* ]]  # boundary-ok

  # The cap is what actually stops the burn, so it lifts inside the stretch and not outside it.
  git -C "$BD_REPO" checkout -q -b burndown/a && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m a
  git -C "$BD_REPO" checkout -q -b burndown/b && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m b
  git -C "$BD_REPO" checkout -q -b burndown/c && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m c
  git -C "$BD_REPO" checkout -q main
  # 90000s, NOT 86400s: pinning a fixture ON the threshold is the exact trap this repo recorded
  # today, and I walked into it again in the test that DEFINES the threshold. burn-down reads its
  # own clock a beat after the payload is built, so 86400 arrives as 86399 — one second inside the
  # stretch — and the cap had already lifted to 8. Green locally, red on both CI lanes.
  # With growth switched OFF, the base cap of 3 is still the wall — the mechanism is intact.
  _PERDAY=0 _bd_left 50 90000; [[ "$output" == HOLD:* ]]; [[ "$output" == *"max 3"* ]]
  # With growth ON, five elapsed days raise the cap well past three. That is what makes an
  # unattended week possible instead of halting on about day one, and it replaces the old
  # last-day-only lift, which was a special case of the same idea.
  _bd_left 50 90000; [[ "$output" == BURN:* ]]
}

@test "burn-down: a BURN needs TWO agreeing readings, SEPARATED IN TIME (R90/R119)" {
  _bd_setup
  # Timestamps go BACKWARDS from now, never forward: the freshness check rejects a future snapshot
  # ("-1s old") as a bad clock, which silently swallowed the first version of this test.
  _snap() { printf '%s 20 %s %s %s\n' "$1" "$(( $(date +%s)+7200 ))" "$2" "$(( $(date +%s)+172800 ))" \
              > "$BD_STATE/ratelimit"; }
  _run()  { run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
                BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status; }
  local n; n="$(date +%s)"

  # NO earlier reading at all: the forecast says burn, but there is nothing to corroborate it.
  # The message points at the STATUS LINE, because that is what records readings now (R119) — the
  # old text said "only one reading so far", which implied burn-down would accumulate them itself.
  # It did, and that was the defect: it sampled only when it evaluated, so unattended it never got
  # a second reading and never started.
  rm -f "$BD_STATE/burndown-lastsample"
  _snap "$((n-9))" 10; _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"no earlier rate-limit reading"* ]]

  # An earlier reading, genuinely separated in time, that agrees → now it may burn. ONE evaluation.
  printf '%s 10\n' "$((n-600))" > "$BD_STATE/burndown-lastsample"
  _snap "$((n-8))" 10; _run
  [[ "$output" == BURN:* ]]

  # The SAME sample re-read is not a second opinion. Still reachable after R119, and by a REAL
  # path rather than a contrived one: the status line writes the snapshot and the cadenced reading
  # in the same repaint, from the same NOW — so the first cadence write after a repaint carries
  # exactly the snapshot's timestamp. Corroborating a reading against itself is the one thing the
  # two-sample rule exists to forbid.
  printf '%s 10\n' "$((n-8))" > "$BD_STATE/burndown-lastsample"   # == the snapshot's own ts
  _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"not a second opinion"* ]]
  printf '%s 10\n' "$((n-600))" > "$BD_STATE/burndown-lastsample" # restore a genuine earlier one

  # THE MEASURED TRANSIENT: 82 → 61 across a 5h rollover. Both readings are now stated OUTRIGHT —
  # the earlier one in the sample file, the current one in the snapshot — rather than accumulated
  # by re-running burn-down, which is no longer how readings are taken (R119) and which hid WHICH
  # two values were actually being compared. The low reading must not be actioned: a 21-point
  # phantom of headroom is exactly what would start generating work on nothing.
  printf '%s 82\n' "$((n-600))" > "$BD_STATE/burndown-lastsample"
  _snap "$((n-5))" 61; _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"disagree by 21 points"* ]]

  # ...and once the reading settles, two agreeing samples let it proceed again.
  printf '%s 61\n' "$((n-600))" > "$BD_STATE/burndown-lastsample"
  _snap "$((n-4))" 61; _run
  [[ "$output" == BURN:* ]]
}

@test "burn-down: real queued work outranks generated work" {
  _bd_setup
  mkdir -p "$BD_TASKS/sQ"; _stamp_root "$BD_TASKS/sQ" "$BD_REPO"
  jq -n '{id:"1",subject:"something the owner asked for",status:"pending"}' > "$BD_TASKS/sQ/1.json"
  _bd 10
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]
  # Drain it and the capacity becomes available — the meter fills BEHIND the backlog, never ahead.
  jq -n '{id:"1",subject:"something the owner asked for",status:"completed"}' > "$BD_TASKS/sQ/1.json"
  _bd 10; [[ "$output" == BURN:* ]]
}

@test "burn-down: a FRESH FILE carrying STALE WINDOW DATA cannot burn (the write clock is not the data clock)" {
  # Observed live 2026-08-15: the status line rewrites this snapshot every repaint, so `ts` was
  # seconds old while r5/r7 inside it were 4-8 DAYS old and the usage figures disagreed with the
  # owner's own UI. The age check cannot see that — it measures when the file was written.
  # The dangerous shape is the one asserted second: r7 slightly in the FUTURE passes every bounds
  # check, so the forecast runs on days-old usage and BURNS. A 5h window is never more than 5h
  # behind when live, which is what makes the staleness provable rather than guessed.
  _bd_setup
  local n; n="$(date +%s)"
  # file written NOW, 7d reset 2 days out (perfectly plausible), 7d usage low enough to burn —
  # but the 5h reset is 8 days in the past, which no live reading can produce.
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n - 691200 ))" 10 "$(( n + 172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"STALE"* ]]
  [[ "$output" != *"already rolled"* ]]      # named for what it IS, not the incidental symptom
  # …and a 7d reset further out than the window itself is bad data, not "just started"
  # 14 days out — comfortably past a 7d window without PINNING the fixture to its exact value, which
  # is the boundary-flake class the portability lint guards (and duly caught this line's first draft).
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n + 7200 ))" 10 "$(( n + 1209600 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"does not describe the current window"* ]]
  [[ "$output" != *"just started"* ]]
  # …and the bound is SYMMETRIC: a 5h reset cannot be 5h+ in the FUTURE either. The first draft
  # only checked the past, which the pre-ship adversarial pass caught as a half-checked bound.
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n + 90000 ))" 10 "$(( n + 172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"IMPOSSIBLE"* ]]
}

@test "burn-down: an IN-PROGRESS task outranks generated work too — work in flight is the realest work" {
  # R113 regression, caught by hand and not by this suite: giving in_progress its own glyph (▸) made
  # it invisible to a count that had only ever matched ◻, so the one kind of work burn-down would
  # have ignored was the task actively being WORKED ON — it would have spun up speculative branches
  # mid-task. The count must follow the queue's meaning, not one of its two renderings.
  _bd_setup
  mkdir -p "$BD_TASKS/sIP"; _stamp_root "$BD_TASKS/sIP" "$BD_REPO"
  jq -n '{id:"1",subject:"actively being worked on",status:"in_progress"}' > "$BD_TASKS/sIP/1.json"
  _bd 10
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]
  # finished -> the capacity is genuinely free again
  jq -n '{id:"1",subject:"actively being worked on",status:"completed"}' > "$BD_TASKS/sIP/1.json"
  _bd 10; [[ "$output" == BURN:* ]]
}

@test "burn-down: unreviewed branches apply backpressure — the loop is self-limiting" {
  _bd_setup
  # THE anti-waste guarantee. If the owner is not reviewing, generating more output is by
  # definition waste, so the system must notice that about itself and stop.
  local i
  for i in 1 2; do
    git -C "$BD_REPO" checkout -q -b "burndown/p$i" main
    git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "p$i"
    git -C "$BD_REPO" checkout -q main
  done
  _bd 10; [[ "$output" == BURN:* ]]        # 2 of 3 — still room
  git -C "$BD_REPO" checkout -q -b burndown/p3 main
  git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m p3
  git -C "$BD_REPO" checkout -q main
  _PERDAY=0 _bd 10; [[ "$output" == HOLD:* ]]; [[ "$output" == *"review or delete"* ]]   # cap, not calendar
  # An EMPTY branch is nothing to review, so it must not count against the budget.
  git -C "$BD_REPO" branch -D burndown/p3 >/dev/null 2>&1
  git -C "$BD_REPO" branch burndown/empty main
  _bd 10; [[ "$output" == BURN:* ]]
}

@test "burn-down: refuses when the 5h window has no room to actually work" {
  _bd_setup
  _bd 10 95; [[ "$output" == HOLD:* ]]; [[ "$output" == *"headroom"* ]]
  _bd 10 20; [[ "$output" == BURN:* ]]
}

@test "candidates: never invents while a recorded signal remains, and labels it when it does" {
  # The property that makes unattended generation defensible: authorship of "what is worth doing"
  # stays with the owner. Rank order is the mechanism — invention is last and labelled, not first.
  local d; d="$(_tmpd)"; git -C "$d" init -q
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  local tk; tk="$(_tmpd)"
  # REWORK_ROOT must be isolated too (found by a DA pass, 2026-08-07): rank 5 shells out to
  # rework.sh, which without an explicit root falls back to $PWD — the REAL repo this suite runs
  # from, not this test's temp dir. Dormant until the real repo's own rework ledger crossed the
  # rebuild threshold; a real event (recorded honestly) then made THIS test flake.
  _cand() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"; }

  # Nothing recorded at all → says so, out loud, as rank 5.
  _cand; [ "$status" -eq 0 ]; [[ "$output" == 6\|invent\|* ]]; [[ "$output" == *"INVENTED"* ]]

  # A ROADMAP item outranks invention — and a CHECKED item is done, so it must not appear.
  printf '# R\n- [ ] add a dark theme\n- [x] shipped already\n' > "$d/ROADMAP.md"
  _cand; [[ "$output" == 2\|roadmap\|*"dark theme"* ]]; [[ "$output" != *"shipped already"* ]]
  [[ "$output" != *invent* ]]

  # A TODO in tracked source outranks nothing here, but must be found once committed.
  rm "$d/ROADMAP.md"; printf 'x=1  # TODO: cache this\n' > "$d/a.sh"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m add
  _cand; [[ "$output" == 3\|todo\|* ]]

  # A parked decision carrying a recommendation outranks EVERYTHING — the owner already reasoned it.
  mkdir -p "$tk/sP"; _stamp_root "$tk/sP" "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend — options: A) sqlite B) files; rec: sqlite",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' \
    > "$tk/sP/1.json"
  _cand; [[ "$output" == 1\|parked\|* ]]; [[ "$output" == *"rec: sqlite"* ]]
  # A park WITHOUT a recommendation is not a candidate: nothing has been decided, so building
  # against it would be guessing on the owner's behalf.
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sP/1.json"
  _cand; [[ "$output" != 1\|parked\|* ]]
}

@test "burndown-branch: work is containerised — never on main, never pushed, always discardable" {
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  _bb start "4|gap|add a dark theme"
  [ "$status" -eq 0 ]; [ "$output" = "add-a-dark-theme" ]
  [ "$(git -C "$d" rev-parse --abbrev-ref HEAD)" = "burndown/add-a-dark-theme" ]
  # main is untouched: one commit, exactly as before.
  [ "$(git -C "$d" rev-list --count main)" -eq 1 ]
  git -C "$d" checkout -q main
  # The manifest lives OUTSIDE the repo, so reviewing from main still finds it and the tree is clean.
  # .companion/ is plugin state, not the owner's work: since R96 the queue, the modes and now the
  # burn-down manifests live there, so it is legitimately present in `git status`. The product's own
  # dirty-guard draws the same line — asserting a fully clean tree here would assert that plugin
  # state does not exist, which is no longer true.
  [ -z "$(git -C "$d" status --porcelain | grep -vE '^.{2} \.companion/')" ]
  _bb show add-a-dark-theme
  [[ "$output" == *"must default to OFF"* ]]; [[ "$output" == *"gap"* ]]   # the source rides the manifest
  [[ "$output" == *"Deleting is the DEFAULT expectation"* ]]
  _bb list; [[ "$output" == *"burndown/add-a-dark-theme"* ]]; [[ "$output" == *"add a dark theme"* ]]

  # A dirty tree is refused: discarding the branch would otherwise discard the owner's own WIP.
  printf 'wip\n' > "$d/wip.txt"
  _bb start "2|roadmap|another thing"; [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
  rm "$d/wip.txt"
  # Duplicates are refused rather than silently reusing a branch that may hold other work.
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 3 ]

  # You cannot delete the branch you are standing on, and the default branch is never a target.
  git -C "$d" checkout -q burndown/add-a-dark-theme
  _bb discard add-a-dark-theme; [ "$status" -eq 5 ]
  git -C "$d" checkout -q main
  _bb discard main; [ "$status" -eq 6 ]
  # Discard is genuinely one step, and leaves nothing behind.
  _bb discard add-a-dark-theme; [ "$status" -eq 0 ]
  _bb list; [ -z "$output" ]
  [ "$(git -C "$d" rev-list --count main)" -eq 1 ]
}

@test "candidates: a DECISION park is never offered as buildable work (R82 soft spots)" {
  # Two limitations R82 recorded as unsolved, closed by one observation: a park written BY THE
  # ASK-GUARD came from a question, so it is a decision by construction and can be marked as one.
  #   (1) rank 1 stops offering decisions as work — building one would make the owner's choice.
  #   (2) auto-parks stop crowding ranks 2-4 out of the list entirely.
  local d tk; d="$(_tmpd)"; git -C "$d" init -q; tk="$(_tmpd)"
  mkdir -p "$tk/sD"; _stamp_root "$tk/sD" "$d"
  printf '# R\n- [ ] add a dark theme\n' > "$d/ROADMAP.md"
  _cd2() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"; }

  jq -n '{id:"1",subject:"❓ [parked] decision: which cache backend? — options: A) x B) y; rec: A",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sD/1.json"
  _cd2
  [[ "$output" != *"which cache backend"* ]]      # a decision is the owner's to ANSWER, not work
  [[ "$output" == *"dark theme"* ]]               # ...and rank 2 is reachable behind it

  # A park describing WORK still ranks 1 — the exclusion must be narrow, or the strongest signal
  # in the repo is lost with it.
  jq -n '{id:"2",subject:"❓ [parked] add retry backoff — options: A) simple B) jitter; rec: B",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sD/2.json"
  _cd2; [[ "$output" == 1\|parked\|*"retry backoff"* ]]

  # SATURATION: many auto-parks must not fill the list and starve every other signal.
  local i
  for i in 3 4 5 6 7 8; do
    jq -n --arg i "$i" '{id:$i,subject:("❓ [parked] decision: q" + $i + " — options: A) x; rec: A"),status:"pending"}' > "$tk/sD/$i.json"
  done
  _cd2; [[ "$output" == *"dark theme"* ]]
  # decompose: parks stay excluded too (R65 — they exist because context is MISSING).
  jq -n '{id:"9",subject:"❓ [parked] decompose: big thing — need: X; rec: split",status:"pending"}' > "$tk/sD/9.json"
  _cd2; [[ "$output" != *"big thing"* ]]
}

@test "candidates: does not feed on prose ABOUT markers, only real annotations" {
  # The first run of this generator against its own repo returned four candidates that were all
  # documentation EXPLAINING what a TODO signal is — including its own source comments. A
  # generator that reads its own definition as input is a mirror, not a signal.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  printf 'x=1  # TODO: cache this\n'                 > "$d/a.sh"
  printf '# Guide\nWe write TODO: markers like this.\n' > "$d/guide.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.sh"* ]]        # a real annotation in code is still a candidate
  [[ "$output" != *"guide.md"* ]]    # prose about markers is not
  [[ "$output" != *"candidates.sh"* ]]  # and never its own source
}

@test "candidates: a TRACKED vendored tree is suppressed, and the filter is overridable (R9 exception)" {
  # Settled by measurement, not argument: with vendored dirs UNTRACKED the filter is redundant
  # because git grep never sees them; with them COMMITTED it is decisive. This pins the case that
  # actually justifies keeping an ecosystem-shaped name in generic code.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  mkdir -p "$d/src" "$d/node_modules/pkg" "$d/vendor/lib"
  printf 'x  # TODO: real signal in src\n'          > "$d/src/a.sh"
  printf 'y  # TODO: someone else code\n'           > "$d/node_modules/pkg/dep.sh"
  printf 'z  # TODO: also someone else\n'           > "$d/vendor/lib/v.sh"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i   # COMMITTED
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"src/a.sh"* ]]                 # the project's own note-to-self survives
  [[ "$output" != *"node_modules"* ]]             # ...and two thirds of the noise is gone
  [[ "$output" != *"vendor/lib"* ]]
  # The defaults are a starting point, not our guess about your layout.
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" \
    CANDIDATES_VENDOR_RE='(^|/)src/' bash "$ROOT/bin/candidates.sh"
  [[ "$output" != *"src/a.sh"* ]]                 # override replaces the default set
  [[ "$output" == *"node_modules"* ]]
}

@test "candidates: a flow whose tests are ALL judgment-only is not a coverage gap (R82 rank 4)" {
  # Found by REVIEWING the first branch burn-down ever generated. Rank 4's comment has always said
  # it must not propose tests for lines the project marks judgment-only — "someone decided they
  # should not be automated, so proposing tests for them argues with a decision already made" — but
  # the code only grepped for [E], so it could not tell an honest gap from a decision already made.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q; mkdir -p "$d/docs/flows"
  local _c; _c() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"; }

  # (1) genuinely no tests at all -> still an honest gap
  printf '# flow:alpha\nsteps:\n- does a thing\n' > "$d/docs/flows/alpha.md"
  _c; [[ "$output" == *"alpha.md"* ]]

  # (2) tests exist but are ALL judgment -> a decision already made, NOT a gap
  printf '# flow:beta\nsteps:\n- does a thing\ntests:\n- [S] beta is judged by eye — judgment\n' \
    > "$d/docs/flows/beta.md"
  _c; [[ "$output" != *"beta.md"* ]]

  # (3) a real executable test -> not a gap, as before
  printf '# flow:gamma\nsteps:\n- does a thing\ntests:\n- [E] gamma round-trips\n' \
    > "$d/docs/flows/gamma.md"
  _c; [[ "$output" != *"gamma.md"* ]]
}

@test "candidates: rank 1 requires evidence the OWNER SAW the park — a model-authored one is not buildable" {
  # THE SELF-DEALING GUARD. Rank 1 claims "the owner deferred THIS work and a recommendation is
  # already written", which is false for a park the model wrote and nobody has looked at. Caught
  # live 2026-08-15: rank 1 was a park authored minutes earlier recommending the model be given
  # more autonomy — the generator would have built its own unreviewed advice.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  mkdir -p "$d/.companion/tasks"
  # seen-and-deferred: carries the note /companion:review writes when the owner defers
  jq -n '{id:"1",subject:"❓ [parked] rev: pick a cache — options: A) sqlite B) files; rec: A",
          status:"pending",notes:[{ts:"t",text:"deferred pending the storage decision"}]}' \
    > "$d/.companion/tasks/1.json"
  # model-authored, never reviewed: same shape, no deferral note
  jq -n '{id:"2",subject:"❓ [parked] rev: never seen by anyone — rec: B",status:"pending"}' \
    > "$d/.companion/tasks/2.json"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="" REWORK_ROOT="$d" \
    bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pick a cache"* ]]      # deferred by the owner -> still the highest signal
  [[ "$output" != *"never seen by anyone"* ]]
  # and it fails to the SAFE side: strip the evidence and rank 1 empties rather than guessing
  jq -n '{id:"1",subject:"❓ [parked] rev: pick a cache — rec: A",status:"pending"}' \
    > "$d/.companion/tasks/1.json"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="" REWORK_ROOT="$d" \
    bash "$ROOT/bin/candidates.sh"
  [[ "$output" != *"1|parked"* ]]
}

@test "candidates: excludes its own PLUGIN TREE, not just its own file — a sibling describing the ranking is still a mirror" {
  # The live miss (2026-08-15): the self-exclusion was written as "this file", which was too narrow
  # by exactly one directory. mcp-server/index.js describes this very ranking in a string literal
  # ("a TODO/FIXME in tracked source") and duly ranked ABOVE two real signals — same mirror, one
  # file over. Only reachable when the plugin is VENDORED INSIDE the project being scanned, which
  # is exactly the shape of this repo.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  # a real annotation OUTSIDE the vendored plugin — must survive
  printf 'y=2  # FIXME: handle the empty case\n' > "$d/real.sh"
  # the plugin, vendored in-tree, with a sibling that merely DESCRIBES the marker it looks for
  mkdir -p "$d/plugins/companion/bin" "$d/plugins/companion/lib" "$d/plugins/companion/mcp-server"
  cp "$ROOT/bin/candidates.sh" "$d/plugins/companion/bin/"
  cp "$ROOT/lib/companion.sh"  "$d/plugins/companion/lib/"
  printf '%s\n' 'const desc = "ranked: a TODO/FIXME in tracked source beats a coverage gap";' \
    > "$d/plugins/companion/mcp-server/index.js"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i
  # run the VENDORED copy, so PLUGIN_DIR really is inside the scanned repo
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" \
    bash "$d/plugins/companion/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real.sh"* ]]     # signal outside the tool's own tree is untouched
  [[ "$output" != *"index.js"* ]]    # a sibling explaining the ranking is not buildable work

  # AND THE SAME THING THROUGH A SYMLINK. This half exists because the direct case shipped GREEN on
  # Linux and RED on the macOS lane: bash's `pwd` is logical, git reports the physical path, and
  # macOS's /var -> /private/var made the two disagree — so the exclusion silently did nothing and
  # the tool fed on its own source again. Reproducing that here means the cheap lane catches it
  # instead of CI, and it is the trap lib/companion.sh already documents for the task-store scan.
  local link; link="$(_tmpd)/via-symlink"
  ln -s "$d" "$link"
  run env BURNDOWN_ROOT="$link" CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" REWORK_ROOT="$link" \
    bash "$link/plugins/companion/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real.sh"* ]]
  [[ "$output" != *"index.js"* ]]
}

@test "autopilot pause/resume: a review is transparent to the drain (R83)" {
  # Review had to turn autopilot OFF to ask anything (the ask-guard blocks questions), which meant
  # reviewing was a decision to stop working and the owner re-armed by hand every time. Pause
  # records that it WAS armed; resume puts it back.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  _ap() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$repo" "$st" "$ROOT/bin/autopilot.sh" "$@"; }

  _ap pause; [[ "$output" == *"already off"* ]]          # clean no-op when it was never armed
  _ap resume; [[ "$output" == *"not paused"* ]]          # and resume must not arm it from nothing
  _ap status; [ "$output" = off ]

  _ap on >/dev/null; _ap pause; [[ "$output" == *"PAUSED"* ]]
  _ap status; [ "$output" = off ]                        # disarmed, so the ask-guard lets questions through
  _ap resume; [[ "$output" == *"RESUMED"* ]]
  _ap status; [ "$output" = on ]                         # ...and the drain picks back up

  # AN EXPLICIT `off` DURING A REVIEW OUTRANKS A PENDING RESUME. Without this, saying "stop" mid
  # review would be silently undone by the review finishing.
  _ap on >/dev/null; _ap pause >/dev/null; _ap off >/dev/null
  _ap resume; [[ "$output" == *"not paused"* ]]
  _ap status; [ "$output" = off ]
}

@test "autopilot resume: a pause marker from ANOTHER session cannot arm autopilot (R108)" {
  # Reproduced live 2026-08-09, on the owner's own machine, by running /companion:review: a review
  # on 2026-08-08 paused and never resumed, leaving the marker behind. The next day a review found
  # autopilot already OFF — so its own `pause` was a correct no-op writing nothing — and `resume`
  # then honoured the DAY-OLD marker and armed a mode the owner had never turned on. Transient
  # state outliving its session. A marker is now only honoured by the session that wrote it.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  _aps() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_SESSION_ID="$3" bash "$4" "${@:5}"' _ "$repo" "$st" "$1" "$ROOT/bin/autopilot.sh" "${@:2}"; }

  # A genuine same-session round trip still works — the fix must not cost R83 its whole point.
  _aps sA on >/dev/null; _aps sA pause; [[ "$output" == *"PAUSED"* ]]
  _aps sA resume; [[ "$output" == *"RESUMED"* ]]
  _aps sA status; [ "$output" = on ]

  # THE DEFECT: session A pauses and never resumes; session B must NOT inherit that promise.
  _aps sA pause >/dev/null
  _aps sB resume; [[ "$output" == *"NOT resumed"* ]]
  _aps sB status; [ "$output" = off ]
  # ...and the marker is DISCARDED, not left to mis-fire on the session after that.
  _aps sB resume; [[ "$output" == *"not paused"* ]]

  # An UNSTAMPED marker — written by a pre-fix version still in the plugin cache — is refused too,
  # which is the case that actually fires during an upgrade.
  mkdir -p "$repo/.companion/modes"; : > "$repo/.companion/modes/autopilot-paused"
  _aps sC resume; [[ "$output" == *"NOT resumed"* ]]
  _aps sC status; [ "$output" = off ]
}

@test "burn-down: the buildable TIER is earned by acceptance, not granted by spare capacity (R82)" {
  # The owner asked for the ladder to climb toward auto-authored features when tokens are going
  # unspent. Utilization is a fine answer to WHETHER there is spare capacity and a terrible one to
  # WHAT may be built: it measures spending, never value, and the real constraint is the owner's
  # review throughput, which does not grow with the token budget. So the tier is gated on the share
  # of generated branches actually KEPT — self-correcting in both directions.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local _bb; _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  # NO HISTORY -> debt paydown only. Verifiable against the suite that already exists, which is what
  # makes it safe unattended.
  _bb start "4|gap|add a golden test for checkout"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 12 ]   # a FEATURE is not yet earned
  [[ "$output" == *"earned tier"* ]]
  _bb start "5|rework|rebuild the parser"; [ "$status" -eq 12 ]  # nor a large rebuild

  # INVENTED work is never automatic at ANY rate — nothing recorded asked for it.
  _bb start "6|invent|something nobody asked for"; [ "$status" -eq 13 ]
  [[ "$output" == *"never built unattended"* ]]

  # Two judged outcomes at 50% (one kept, one discarded) -> the feature tier opens.
  _bb start "4|gap|a second debt item"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main
  _bb discard add-a-golden-test-for-checkout; [ "$status" -eq 0 ]
  git -C "$d" branch -D burndown/a-second-debt-item >/dev/null 2>&1   # merged then pruned = kept
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main

  # ...and it FALLS BACK. Discard enough and the ceiling drops to debt again, with no new judgement
  # from anyone — which is the half a utilization clock can never do.
  _bb discard add-a-dark-theme; [ "$status" -eq 0 ]
  _bb start "2|roadmap|another feature"; [ "$status" -eq 12 ]
}

@test "burn-down: a branch can NEVER exist without a manifest, even with the mode ARMED (R82)" {
  # THE GAP THAT HID THIS: every earlier test used a state dir where the burn-down flag was never
  # set — so the suite only ever exercised the one state the feature cannot really run in. The ON
  # flag is a FILE at $STATE/burndown/<enc>; the manifest dir was a DIRECTORY at the same path, so
  # armed, mkdir failed, no manifest was written, and start still exited 0 with a branch created.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  ( cd "$d" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" burndown on ) >/dev/null
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" start "4|gap|add retry backoff"
  [ "$status" -eq 0 ]
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" show add-retry-backoff
  [ "$status" -eq 0 ]; [[ "$output" == *"must default to OFF"* ]]
  # ...and arming still works afterwards — the two must not fight over one path.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" burndown status' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$output" = on ]
  # An unwritable manifest dir must abort BEFORE the branch exists, not after.
  local d2 st2; d2="$(_tmpd)"; st2="$(_tmpd)"
  git -C "$d2" init -q -b main; git -C "$d2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  # Manifests are REPO state since R96 stage 3, so making the STATE dir unwritable no longer blocks
  # anything — the fault has to be injected where the code actually writes, or this guard silently
  # stops being exercised while still reading green.
  mkdir -p "$d2/.companion"; chmod 555 "$d2/.companion"
  run env BURNDOWN_ROOT="$d2" CLAUDE_COMPANION_STATE_DIR="$st2" bash "$ROOT/bin/burndown-branch.sh" start "4|gap|thing"
  chmod 755 "$d2/.companion"
  [ "$status" -eq 7 ]
  [ "$(git -C "$d2" branch --list 'burndown/*' | wc -l)" -eq 0 ]
}

@test "burn-down: parks and blocked items are NOT buildable work and must not block it (R82)" {
  # Counting ❓/⏳ as "queued work" made rank 1 — the highest-signal source — unreachable, stopped
  # the documented loop after one iteration (step 6 parks a ❓, which blocked step 1), and made the
  # 3-branch backpressure unreachable. One long-lived ⏳ disabled the mode permanently.
  local d st tk; d="$(_tmpd)"; st="$(_tmpd)"; tk="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$st/burndown" "$tk/s1"; _stamp_root "$tk/s1" "$d"
  touch "$(_flagpath "$st" burndown "$d")"
  local n; n="$(date +%s)"
  printf '%s 20 %s 10 %s\n' "$((n-5))" "$((n+7200))" "$((n+172800))" > "$st/ratelimit"
  # The corroborating earlier reading, written the way the STATUS LINE writes it (R119) — 600s
  # back, past SAMPLE_MIN. burn-down no longer records its own samples; doing so is what starved it.
  printf '%s 10\n' "$((n-600))" > "$st/burndown-lastsample"
  printf '%s 20 %s 10 %s\n' "$n" "$((n+7200))" "$((n+172800))" > "$st/ratelimit"
  _bd2() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" bash "$ROOT/bin/burn-down.sh" status; }
  jq -n '{id:"1",subject:"❓ [parked] a decision; rec: A",status:"pending"}'    > "$tk/s1/1.json"
  jq -n '{id:"2",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$tk/s1/2.json"
  _bd2; [[ "$output" == BURN:* ]]                      # neither is work this loop could pick up
  jq -n '{id:"3",subject:"actual buildable work",status:"pending"}' > "$tk/s1/3.json"
  _bd2; [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]   # real work still wins
}

@test "autopilot pause: refuses to disarm when it cannot record the paused state (R83)" {
  # The first version cleared the flag unconditionally, so an unwritable state dir silently and
  # PERMANENTLY lost autopilot while printing a message promising it would come back — destroying
  # the exact state this verb exists to protect.
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  _ap2() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$d" "$st" "$ROOT/bin/autopilot.sh" "$@"; }
  _ap2 on >/dev/null
  # Modes are REPO state since R96, so the fault has to be injected where the marker actually goes:
  # making $HOME read-only no longer blocks anything, and a test that kept doing so would assert a
  # guarantee that had quietly stopped being exercised.
  chmod 555 "$d/.companion/modes"
  _ap2 pause
  chmod 755 "$d/.companion/modes"
  [ "$status" -ne 0 ]; [[ "$output" == *"NOT paused"* ]]
  _ap2 status; [ "$output" = on ]        # still ARMED — failing loud beats losing it silently
}

@test "burndown-branch: a slug cannot escape the manifest dir (R82)" {
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  printf 'keep me\n' > "$st/victim.md"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" discard '../../victim'
  [ "$status" -eq 8 ]
  [ -f "$st/victim.md" ]                 # discard reached OUTSIDE the state dir before this guard
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" show '../../victim'
  [ "$status" -eq 8 ]
}

@test "autopilot resume: refuses and KEEPS the marker when it cannot re-arm (R83)" {
  # The mirror of the pause fix, and it was missed: resume deleted the marker FIRST, then tried to
  # arm without checking, then printed "RESUMED" unconditionally — leaving autopilot off, the marker
  # gone, and no way back. A half-corrected defect class is worse than an uncorrected one, because
  # the ledger says it is handled.
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  _ar() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$d" "$st" "$ROOT/bin/autopilot.sh" "$@"; }
  _ar on >/dev/null; _ar pause >/dev/null
  rm -f "$d/.companion/modes/autopilot"; chmod 555 "$d/.companion/modes"
  _ar resume
  chmod 755 "$d/.companion/modes"
  [ "$status" -ne 0 ]; [[ "$output" == *"NOT resumed"* ]]
  [ -f "$d/.companion/modes/autopilot-paused" ]   # marker KEPT — recoverable
  _ar resume; [[ "$output" == *"RESUMED"* ]]                    # and the retry works
  _ar status; [ "$output" = on ]
}

@test "burndown-branch: refuses a slug that collides with the default branch (R82)" {
  # `discard` refuses anything named like the default branch, so minting one created a branch that
  # could never be removed and counted against the backpressure cap forever.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" start "1|parked|Main!"
  [ "$status" -eq 9 ]
  [ "$(git -C "$d" branch --list 'burndown/*' | wc -l)" -eq 0 ]
}
@test "ask-guard: autopilot OFF silently allows — no denial, no park" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"q\",options:[{label:\"A\"}]}]}}" | "$3"' \
    _ "$repo" "off1" "$AG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                    # no output at all -> Claude Code's default allow
}

@test "ask-guard: autopilot ON denies AND auto-parks the question with its real options + a recommendation (R84)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  _ag_ask "$repo" "on1"
  [ "$status" -eq 0 ]
  [[ "$output" == deny\|* ]]
  [[ "$output" == *"ALREADY PARKED FOR YOU as #"* ]]   # a batch parks several, so ids are listed
  run env CLAUDE_COMPANION_SESSION_ID=on1 "$TQ" list
  [[ "$output" == *"❓ [parked] decision: pick A or B"* ]]
  [[ "$output" == *"A (faster)"* ]] && [[ "$output" == *"B (safer)"* ]]
  [[ "$output" == *"rec: A"* ]]                        # first option is the recommendation
  [[ "$output" != *"rev:"* ]]                           # NEVER auto-marks reversible (R77)
}

@test "ask-guard: a RETRIED identical question dedups instead of parking twice" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  _ag_ask "$repo" "dup1"
  _ag_ask "$repo" "dup1"
  [[ "$output" == *"ALREADY PARKED"* ]]
  run env CLAUDE_COMPANION_SESSION_ID=dup1 "$TQ" list
  local n; n="$(printf '%s\n' "$output" | grep -c "pick A or B")"
  [ "$n" -eq 1 ]                                        # exactly one park, not two
}

@test "ask-guard: DECISIVE mode swaps the guidance from park-every-decision to decide-if-reversible (R59)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on && "$AP" decisive on ) >/dev/null
  _ag_ask "$repo" "dec1"
  [[ "$output" == *"DECISIVE mode"* ]]
  [[ "$output" == *"DECIDE it yourself"* ]]
  [[ "$output" != *"park it even when trivially reversible"* ]]
}

@test "ask-guard: a parked question keeps its option COSTS — no silent truncation (R109·b)" {
  # MEASURED DEFECT, 2026-08-10. Descriptions were cut to 80 chars and the payload to 900 bytes,
  # both silently. On a real 4-option park every COST clause — a byte-budget raise, per-project
  # setup, a staleness risk — landed mid-word, and what reached the queue read like a complete
  # thought. STEERING says a thin park "makes the review a rubber-stamp"; the BACKSTOP was
  # manufacturing exactly that. A cut that cannot be seen is worse than a cut.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local long="raise the cap by 154B which is about 38 tokens per session forever in every installed repo and overrides a recorded pre-commitment"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" --arg d "$3" "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"pick\",options:[{label:\"A\",description:\$d},{label:\"B\",description:\$d}]}]}}" | "$4"' \
    _ "$repo" "trunc1" "$long" "$AG"
  [ "$status" -eq 0 ]

  run env CLAUDE_COMPANION_SESSION_ID=trunc1 "$TQ" list
  # The TAIL of the description is the assertion that matters: the old 80-char cut kept the head,
  # so a head-only check passed while every cost clause was gone.
  [[ "$output" == *"overrides a recorded pre-commitment"* ]]
  # Both options, not just the first — the 900-byte payload cap ate later ones.
  local n; n="$(printf '%s\n' "$output" | grep -c "overrides a recorded pre-commitment")"
  [ "$n" -ge 1 ]
  [[ "$output" == *"rec: A"* ]]
}

# ── R26 restored: autopilot's "keep going" guarantee is a hook again ──────────────────────────
# Retired in R100/Pass 4, declined twice (R105 2026-08-08, R107 2026-08-09), restored 2026-08-12
# because the prose lost: STEERING said "keep draining" and the model stopped with startable work
# in the queue. A nudge the model can skip is not a mode (R36).

@test "stop-autopilot: armed + a startable task BLOCKS the stop; a drained queue allows it (R26 restored)" {
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  [ -x "$SA" ]
  repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run env CLAUDE_COMPANION_SESSION_ID=sa1 "$TQ" add "real startable work"
  [ "$status" -eq 0 ]

  # ARMED + STARTABLE -> block, naming the task so the continuation is actionable rather than a nag.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa1\"}" | "$2"' _ "$repo" "$SA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"real startable work"* ]]

  # DRAINED -> allow (empty output = Claude Code's default allow). This is the terminator that
  # stops the mode being a trap: a queue with nothing startable must never block the session.
  run env CLAUDE_COMPANION_SESSION_ID=sa1 "$TQ" done 1
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa1\"}" | "$2"' _ "$repo" "$SA"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # AUTOPILOT OFF -> allow, even with work queued. The flag is the whole gate.
  run env CLAUDE_COMPANION_SESSION_ID=sa2 "$TQ" add "work with autopilot off"
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa2\"}" | "$2"' _ "$repo" "$SA"
  [ -z "$output" ]
}

@test "stop-autopilot: a DRY queue with burn-down armed and a BURN verdict refuses the stop (R82 hand-off restored)" {
  # The gap this closes: burn-down was documented as automatic but nothing ever fired it — the
  # dry-queue path just ended the turn and STEERING asked the model to remember. Continuing a turn
  # is control-flow, which is the one thing a hook can actually guarantee (R28).
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  ( cd "$repo" && "$AP" on ) >/dev/null
  local _stop; _stop() { run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sBD\"}" | "$2"' _ "$repo" "$SA"; }

  # DRY queue, burn-down OFF -> the turn ends, exactly as before. Proves the new branch is opt-in.
  _stop; [ -z "$output" ]

  # Arm burn-down, but give it NO usable snapshot: should-burn HOLDs, so the turn must still end.
  # Hold is the safe direction and every unknown resolves to it.
  ( cd "$repo" && "$AP" burndown on ) >/dev/null
  _stop; [ -z "$output" ]

  # Now a snapshot that genuinely forecasts underspend, with the corroborating earlier reading
  # written the way the STATUS LINE writes it (R119). It used to be seeded by running burn-down
  # once — which only worked while burn-down recorded its own samples, and that self-writing is
  # exactly what stopped an unattended session ever taking a second reading.
  local n; n="$(date +%s)"
  printf '%s 5\n' "$(( n - 600 ))" > "$CLAUDE_COMPANION_STATE_DIR/burndown-lastsample"
  printf '%s %s %s %s %s\n' "$n" 10 "$(( n + 7200 ))" 5 "$(( n + 172800 ))" \
    > "$CLAUDE_COMPANION_STATE_DIR/ratelimit"
  _stop
  [[ "$output" == *'"decision":"block"'* ]]     # the stop is REFUSED — the hand-off fired
  [[ "$output" == *"burn-down says BURN"* ]]
  [[ "$output" == *"candidates"* ]]             # ...and it names what to do next
  [[ "$output" == *"burndown-branch"* ]]
}

@test "stop-autopilot: the kill switch and its bounds all yield; ship-mode stays dead, burn-down hands off (R26/R81/R82)" {
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run env CLAUDE_COMPANION_SESSION_ID=sb1 "$TQ" add "work"

  # Control: it really would block without the switch, or the assertions below prove nothing.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | "$2"' _ "$repo" "$SA"
  [[ "$output" == *'"decision":"block"'* ]]

  # KILL SWITCH.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0 "$2"' _ "$repo" "$SA"
  [ -z "$output" ]

  # RUN BOUNDS (R81). Restoring the continuation without its terminators is the one genuinely
  # dangerous version of this change, so each bound is pinned. `1` is the tightest non-disabling
  # value; a run that has taken any turn at all is already at it.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | CLAUDE_COMPANION_AUTOPILOT_TURNS=1 "$2"' _ "$repo" "$SA"
  [ -z "$output" ]

  # THE OMISSIONS ARE PART OF THE CONTRACT, not an accident of the splice: both concerns acquired
  # another owner while this file was gone, and a second owner is how a checkpoint path silently
  # re-automates itself.
  run grep -cE "git commit|git add -A" "$SA"
  [ "$output" -eq 0 ]                                  # ship-mode belongs to ship-checkpoint.sh
  # BURN-DOWN IS THE EXCEPTION, reversed 2026-08-15 by owner decision: the hook now makes the CHEAP
  # call (should-burn) and hands the expensive ranking to the model. It must NOT rank candidates
  # itself — `candidates.sh` git-greps the whole repo, which is unbounded in repo size on a hook
  # that fires at every stop (R81). So: burn-down.sh yes, candidates.sh no.
  # Assert on INVOCATION, not mention: the hook names candidates.sh in the instruction it hands
  # back to the model, which is the whole point of the hand-off — what must not happen is the hook
  # RUNNING it.
  run grep -c "should-burn" "$SA"
  [ "$output" -ge 1 ]                                  # the CHEAP verdict is wired again
  # ...but the repo-wide scan stays OUT of the hook. Assert on execution shapes, not on the name:
  # the hook names candidates.sh in the instruction it hands back to the model, which is the point
  # of the hand-off. Running it is what R81 forbids (git grep is unbounded in repo size).
  run grep -cE '[$][(][^)]*candidates[.]sh|(bash|exec) [^|]*candidates[.]sh' "$SA"
  [ "$output" -eq 0 ]
  # ...and it must still READ the selection from tq rather than re-deriving it: the recorded drift
  # bug had this hook offering a task blocked on an unanswered park four turns running.
  run grep -c "stopfields" "$SA"
  [ "$output" -ge 1 ]
}

@test "burn-down --scheduled: the SCHEDULE is the trigger, and it bypasses ONLY the forecast (R116)" {
  # A scheduled/headless run has no status line, so no rate-limit snapshot exists and the forecast
  # can only ever say "no snapshot yet" — burn-down would HOLD forever in exactly the substrate
  # chosen to run it. The forecast answers "is there idle capacity nobody claimed?"; a cron entry
  # answers that in advance. What must NOT be bypassed is everything that bounds the damage.
  _bd_setup
  local _s; _s() { run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" "$@"; }
  rm -f "$BD_STATE/ratelimit"

  # unscheduled with no snapshot behaves EXACTLY as before — the bypass is opt-in
  _s status; [[ "$output" == HOLD:* ]]; [[ "$output" == *"no rate-limit snapshot"* ]]

  # scheduled proceeds, and SAYS which path it took rather than implying a forecast happened
  _s status --scheduled
  [[ "$output" == BURN:* ]]; [[ "$output" == *"SCHEDULED"* ]]; [[ "$output" == *"no forecast consulted"* ]]
  _s should-burn --scheduled; [ "$status" -eq 0 ]

  # ARMING is not bypassable — the mode that authors work stays a deliberate act
  ( cd "$BD_REPO" && CLAUDE_COMPANION_STATE_DIR="$BD_STATE" bash "$ROOT/bin/autopilot.sh" burndown off ) >/dev/null
  _s status --scheduled; [[ "$output" == HOLD:* ]]; [[ "$output" == *"OFF for this repo"* ]]
  ( cd "$BD_REPO" && CLAUDE_COMPANION_STATE_DIR="$BD_STATE" bash "$ROOT/bin/autopilot.sh" burndown on ) >/dev/null

  # REAL QUEUED WORK still outranks generated work
  mkdir -p "$BD_TASKS/sSch"; _stamp_root "$BD_TASKS/sSch" "$BD_REPO"
  jq -n '{id:"1",subject:"something the owner asked for",status:"pending"}' > "$BD_TASKS/sSch/1.json"
  _s status --scheduled; [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]
  rm -rf "$BD_TASKS/sSch"

  # and the unreviewed-branch cap still stops generation outrunning review. No time-based lift is
  # granted without a snapshot: we cannot know how much of the window elapsed, so the cap stays low.
  local i
  for i in 1 2 3; do
    git -C "$BD_REPO" checkout -q -b "burndown/s$i" main
    git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "s$i"
    git -C "$BD_REPO" checkout -q main
  done
  _s status --scheduled; [[ "$output" == HOLD:* ]]; [[ "$output" == *"unreviewed"* ]]
  _s should-burn --scheduled; [ "$status" -eq 1 ]
}

@test "burn-down: HARDENING outranks features, and feature-shaped work is capped far below it (R116)" {
  # Owner-decided direction 2026-08-20, and it follows the project's OWN ordered values — keep it
  # self-describing · contain blast radius · verify and stay aligned · subtract as you add. Shipping
  # features is not among them. The asymmetry: hardening is verifiable without the owner ("did the
  # suite go red"), a feature costs review attention that does not scale with the token budget.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q -b main
  mkdir -p "$d/docs/flows"
  printf '# R\n- [ ] add a dark theme\n'            > "$d/ROADMAP.md"
  printf 'x  # TODO: cache this\n'                  > "$d/a.sh"
  printf '# flow:x\nsteps:\n- does a thing\n'       > "$d/docs/flows/untested.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -qm i

  # ORDERING: the two hardening signals come before the roadmap feature
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  local first; first="$(printf '%s\n' "$output" | head -1)"
  [[ "$first" == 3\|todo\|* ]] || [[ "$first" == 4\|gap\|* ]]
  # the roadmap line is still OFFERED — demoted, not dropped
  [[ "$output" == *"2|roadmap|add a dark theme"* ]]
  # ...and it appears AFTER both hardening ranks
  local rn hn
  rn="$(printf '%s\n' "$output" | grep -n '^2|roadmap' | cut -d: -f1)"
  hn="$(printf '%s\n' "$output" | grep -n '^[34]|' | tail -1 | cut -d: -f1)"
  [ "$rn" -gt "$hn" ]

  # THE FEATURE CAP. Earn the feature tier first (2 judged outcomes at >=50%).
  local BB="$ROOT/bin/burndown-branch.sh"
  ( cd "$d" && bash "$BB" start "4|gap|first debt item" >/dev/null 2>&1; git checkout -q main
    bash "$BB" start "4|gap|second debt item" >/dev/null 2>&1; git checkout -q main
    bash "$BB" discard first-debt-item >/dev/null 2>&1
    git branch -D burndown/second-debt-item >/dev/null 2>&1 )   # merged+pruned = kept

  run bash -c 'cd "$1" && bash "$2" start "2|roadmap|dark theme" && git checkout -q main' _ "$d" "$BB"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && bash "$2" start "2|roadmap|export to csv" && git checkout -q main' _ "$d" "$BB"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && bash "$2" start "2|roadmap|a third feature"' _ "$d" "$BB"
  [ "$status" -eq 14 ]; [[ "$output" == *"feature-shaped"* ]]

  # ...while HARDENING is still buildable with features capped — that is the whole point
  run bash -c 'cd "$1" && bash "$2" start "4|gap|another coverage gap" && git checkout -q main' _ "$d" "$BB"
  [ "$status" -eq 0 ]
}

@test "burn-down: a branch records WHY it was chosen, and says so loudly when it does not (R116)" {
  # Owner-decided 2026-08-20: rank by recorded judgment against the project's ordered core values,
  # not by a numeric formula whose inputs would be invented. The rationale must be WRITTEN DOWN
  # before building, so the owner can correct the loop's PRIORITIES and not merely its output.
  # Structural, not advisory: the manifest cannot exist without either a rationale or a bold
  # admission that none was given — the same rule that already forbids a branch with no stated
  # reason at all.
  local d; d="$(_tmpd)"; git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local BB="$ROOT/bin/burndown-branch.sh"

  run bash -c 'cd "$1" && bash "$2" start "4|gap|add a golden test for checkout" --why "Serves core value 2 (verify + stay aligned): widest blast radius, no automated net. Cost ~1 test file. Chosen over a cosmetic TODO." && git checkout -q main' _ "$d" "$BB"
  [ "$status" -eq 0 ]
  run cat "$d/.companion/burndown-manifests/add-a-golden-test-for-checkout.md"
  [[ "$output" == *"Why this, now"* ]]
  [[ "$output" == *"core value 2"* ]]
  [[ "$output" == *"Chosen over"* ]]
  [[ "$output" != *"NO RATIONALE"* ]]

  # ABSENCE IS LOUD. A priority nobody can read back is indistinguishable from one nobody made.
  run bash -c 'cd "$1" && bash "$2" start "4|gap|second thing" && git checkout -q main' _ "$d" "$BB"
  [ "$status" -eq 0 ]
  run cat "$d/.companion/burndown-manifests/second-thing.md"
  [[ "$output" == *"NO RATIONALE WAS RECORDED"* ]]
  [[ "$output" == *"extra scepticism"* ]]
}

@test "ask-guard: a BATCHED ask parks EVERY question, and dedup is per-question (R109·b)" {
  # Hit live 2026-08-22. The park was built from questions[0] and then ANNOUNCED the loss
  # ("[+2 more question(s) in the same ask]"), which is worse than silence in one specific way: it
  # reads like the payload was handled. It was not — the other questions' options and
  # recommendations were gone and had to be rebuilt from the transcript by hand.
  # Not an edge case: review.md BATCHES up to 4 questions per call, and batching is the RECOMMENDED
  # shape precisely so the owner is interrupted once instead of four times.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local q3='{"cwd":"'"$repo"'","session_id":"sAG","tool_input":{"questions":[
    {"question":"First: pick a cache","options":[{"label":"sqlite","description":"one file"},{"label":"files"}]},
    {"question":"Second: pick a theme","options":[{"label":"dark"},{"label":"light"}]},
    {"question":"Third: pick a port","options":[{"label":"8080"},{"label":"3000"}]}]}}'

  run bash -c 'printf "%s" "$1" | "$2"' _ "$q3" "$AG"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"deny"'* ]]
  [ "$(ls "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json 2>/dev/null | wc -l)" -eq 3 ]
  run grep -l "pick a theme" "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json
  [ "$status" -eq 0 ]                                   # the SECOND question survived
  run grep -l "pick a port" "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json
  [ "$status" -eq 0 ]                                   # and the third

  # a retry of the same batch must not stack duplicates
  run bash -c 'printf "%s" "$1" | "$2"' _ "$q3" "$AG"
  [ "$(ls "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json | wc -l)" -eq 3 ]

  # ...but dedup is PER QUESTION: a batch mixing an old question with a new one captures the new one
  local qmix='{"cwd":"'"$repo"'","session_id":"sAG","tool_input":{"questions":[
    {"question":"First: pick a cache","options":[{"label":"sqlite","description":"one file"},{"label":"files"}]},
    {"question":"FOURTH: brand new","options":[{"label":"yes"},{"label":"no"}]}]}}'
  run bash -c 'printf "%s" "$1" | "$2"' _ "$qmix" "$AG"
  [ "$(ls "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json | wc -l)" -eq 4 ]
  run grep -l "brand new" "$CLAUDE_COMPANION_TASKS_DIR/sAG"/*.json
  [ "$status" -eq 0 ]
}

@test "ask-close: an ANSWERED question's park closes; a missed or dismissed one SURVIVES (R116)" {
  # Owner-asked 2026-08-22: "I often am working on another prompt and miss the recommendations."
  # ask-guard now parks EVERY question, not only the ones autopilot denies — otherwise the capture
  # existed only in the state the owner is least likely to be watching from. That fix creates a
  # second risk (stale parks for answered questions), and a pile of stale parks trains you to ignore
  # the pile, which is the same as having no pile. This closes that loop.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local AC="$ROOT/bin/ask-close.sh"
  local qs='"questions":[{"question":"pick a cache","options":[{"label":"sqlite"},{"label":"files"}]},{"question":"pick a theme","options":[{"label":"dark"},{"label":"light"}]}]'
  local payload='{"cwd":"'"$repo"'","session_id":"sC","tool_input":{'"$qs"'}}'

  # AUTOPILOT OFF: the question is ALLOWED through (silent) but parked anyway
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$AG"
  [ "$status" -eq 0 ]; [ -z "$output" ]                       # silence = allowed, owner still sees it
  [ "$(ls "$CLAUDE_COMPANION_TASKS_DIR/sC"/*.json | wc -l)" -eq 2 ]

  # NO tool_response — dismissed, missed, or the terminal closed. The parks MUST survive: this is
  # the entire point, and "cannot tell" must read as "leave it parked".
  run bash -c 'printf "%s" "$1" | "$2"' _ "$payload" "$AC"
  [ "$status" -eq 0 ]
  [ "$(jq -rs '[.[]|select(.status=="pending")]|length' "$CLAUDE_COMPANION_TASKS_DIR/sC"/*.json)" -eq 2 ]

  # an ANSWER closes them, so an answered question leaves nothing behind
  local answered='{"cwd":"'"$repo"'","session_id":"sC","tool_input":{'"$qs"'},"tool_response":{"pick a cache":"sqlite","pick a theme":"dark"}}'
  run bash -c 'printf "%s" "$1" | "$2"' _ "$answered" "$AC"
  [ "$(jq -rs '[.[]|select(.status=="pending")]|length' "$CLAUDE_COMPANION_TASKS_DIR/sC"/*.json)" -eq 0 ]
  # ...and it says WHY it closed, so the audit trail survives the closing
  run grep -l "park closed by ask-close" "$CLAUDE_COMPANION_TASKS_DIR/sC"/*.json
  [ "$status" -eq 0 ]

  # an empty response object is not evidence of an answer either
  local repo2; repo2="$(_tmpd)"; git -C "$repo2" init -q
  local p2='{"cwd":"'"$repo2"'","session_id":"sD","tool_input":{'"$qs"'}}'
  run bash -c 'printf "%s" "$1" | "$2"' _ "$p2" "$AG"
  run bash -c 'printf "%s" "$1" | "$2"' _ '{"cwd":"'"$repo2"'","session_id":"sD","tool_input":{'"$qs"'},"tool_response":{}}' "$AC"
  [ "$(jq -rs '[.[]|select(.status=="pending")]|length' "$CLAUDE_COMPANION_TASKS_DIR/sD"/*.json)" -eq 2 ]
}

# ── the sampler is the STATUS LINE, not burn-down itself (R119) ───────────────────────────────

@test "burn-down: it must NOT write the sample itself — that is what starved it (R119)" {
  _bd_setup
  # Structural, and deliberately so: if burn-down ever records its own reading again, the
  # self-starvation and the rapid-call bypass both come straight back, and BOTH are invisible in
  # any single-run assertion. The file must be untouched by an evaluation.
  printf '%s %s\n' "$(( $(date +%s) - 600 ))" 10 > "$BD_STATE/burndown-lastsample"
  printf '%s %s %s %s %s\n' "$(date +%s)" 20 "$(( $(date +%s)+7200 ))" 10 "$(( $(date +%s)+172800 ))" \
    > "$BD_STATE/ratelimit"
  local before; before="$(cat "$BD_STATE/burndown-lastsample")"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [ "$(cat "$BD_STATE/burndown-lastsample")" = "$before" ]
}

@test "burn-down: two readings SECONDS apart are one sample twice, and are refused (R119b)" {
  _bd_setup
  # The half that made the old guard theatre. Two evaluations 30s apart used to satisfy it — but at
  # a 5h rollover both land on the same side of it, so they agree perfectly and prove nothing. It
  # blocked the honest single-call path while being trivially bypassable by running twice.
  printf '%s %s\n' "$(( $(date +%s) - 5 ))" 10 > "$BD_STATE/burndown-lastsample"
  printf '%s %s %s %s %s\n' "$(date +%s)" 20 "$(( $(date +%s)+7200 ))" 10 "$(( $(date +%s)+172800 ))" \
    > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"one sample written twice"* ]]
}

@test "rl sample: the recorder THROTTLES, so the two readings are genuinely apart (R119)" {
  # The cadence is the whole mechanism: without throttling, a status line repainting every 10s
  # would overwrite the history constantly and the previous reading would never be old enough to
  # corroborate anything — the same "one sample twice" failure, arriving from the other side.
  local sd; sd="$(_tmpd)"
  run env CLAUDE_COMPANION_STATE_DIR="$sd" bash -c \
    '. "$1/lib/companion.sh"; companion_rl_sample_record 1000 42 600 && echo FIRST-WROTE' _ "$ROOT"
  [[ "$output" == *"FIRST-WROTE"* ]]
  # 60s later, well inside the 600s cadence → refused, and the ORIGINAL reading survives
  run env CLAUDE_COMPANION_STATE_DIR="$sd" bash -c \
    '. "$1/lib/companion.sh"; companion_rl_sample_record 1060 99 600 || echo THROTTLED' _ "$ROOT"
  [[ "$output" == *"THROTTLED"* ]]
  [ "$(cat "$sd/burndown-lastsample")" = "1000 42" ]
  # ...and past the cadence it does write, or the history would freeze forever
  run env CLAUDE_COMPANION_STATE_DIR="$sd" bash -c \
    '. "$1/lib/companion.sh"; companion_rl_sample_record 1700 51 600 && echo WROTE' _ "$ROOT"
  [[ "$output" == *"WROTE"* ]]
  [ "$(cat "$sd/burndown-lastsample")" = "1700 51" ]
}

@test "burn-down: the FIRST branch bootstraps the ladder, and exactly one (R121)" {
  # MEASURED LIVE, and it is what made burn-down inert on a healthy repo. Ranks 1/2/5 all require a
  # MERGE RATE; the merge rate comes from branches the owner has judged; a branch can only be judged
  # if it was built. With no TODOs and no untested flows there is no rank 3/4 work either — so a
  # WELL-MAINTAINED repo could never build a first branch, never earn a merge, and never climb.
  # Burn-down returned BURN and then refused its only candidate, holding an empty ledger it had no
  # way to fill. Owner-decided from a 4-option menu 2026-08-23.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local _bb; _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  # Nothing judged, nothing present: rank 5 — normally needing 4 judged at 75% — is permitted ONCE.
  _bb start "5|rework|rebuild the flaky gate suite"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main

  # SELF-LIMITING, and this is the whole safety argument: the exception requires that no burndown
  # branch is PRESENT, so creating one closes it. There can never be two unjudged bootstrap
  # branches piling up unreviewed — the ceiling reopens only once the owner has judged this one.
  _bb start "5|rework|and another rebuild"; [ "$status" -eq 12 ]
  [[ "$output" == *"earned tier"* ]]
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 12 ]

  # Judge it — discard counts as judgement just as merge does — and the normal maths resumes:
  # one judged, zero merged, 0% kept, so the feature tier stays shut. The bootstrap grants a first
  # BRANCH, never a first pass mark.
  _bb discard rebuild-the-flaky-gate-suite; [ "$status" -eq 0 ]
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 12 ]
}

@test "burn-down: bootstrap NEVER reaches rank 6 — a first act of autonomy is not invention (R121)" {
  # The line that keeps the exception honest. Rank 6 means "nothing recorded remains, invent
  # something"; it is refused before the bootstrap is even considered. Widening the first branch to
  # cover invented work would turn "let it start" into "let it make things up", which is a
  # different decision entirely and not the one that was taken.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" \
      start "6|invent|something nobody asked for"
  [ "$status" -eq 13 ]
  [[ "$output" == *"never built unattended"* ]]
}
