#!/usr/bin/env bats
#
# THE QUEUE - tq itself, the board, and task/dependency semantics.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper


# ---- tq (THE queue, companion-owned store) ----

@test "tq: add/doing/done write the companion store + stamp the repo root; report groups by state" {
  ( cd "$ROOT" && "$TQ" add "build it" "❓ pick a backend" ) >/dev/null
  [ -f "$CLAUDE_COMPANION_TASKS_DIR/s1/.root" ]                # session dir stamped with the repo root
  run jq -r '.subject + "|" + .status' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json"
  [ "$output" = "build it|pending" ]
  "$TQ" doing 1 >/dev/null
  [ "$(jq -r .status "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "in_progress" ]
  run "$TQ" done 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"#1 → completed"* ]]        # the state transition (behavioral, format-agnostic)
  [[ "$output" == *"📋"* ]]                     # a report is printed
  [[ "$output" == *"pick a backend"* ]]        # the parked sibling is surfaced (leading ❓ stripped)
  [[ "$output" != *"build it"* ]]              # completed task is count-only, not a full line (Design D, R47)
}

@test "tq: cancel retracts a task — cancelled, excluded from report counts, file kept (R32)" {
  ( cd "$ROOT" && "$TQ" add "wrong task" "keep me" ) >/dev/null
  run "$TQ" cancel 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled"* ]]
  [ "$(jq -r .status "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "cancelled" ]   # file kept for audit
  run "$TQ" report
  [[ "$output" != *"wrong task"* ]]        # retracted → not shown (no false ✔, no lingering ◻)
  [[ "$output" == *"keep me"* ]]           # the sibling remains
  # cancelled excluded from open — asserted at the store, not the header string (format-agnostic)
  [ "$(jq -s '[.[]|select(.status=="pending")]|length' "$CLAUDE_COMPANION_TASKS_DIR/s1"/*.json)" -eq 1 ]
}

@test "tq: writes go temp-file + mv, never in-place jq (R44 crash-safety)" {
  # Guards the atomic write idiom against a 'simplify to jq > $f' refactor that breaks crash-resume.
  [ "$(grep -Fc 'mv "$t" "$f"' "$ROOT/bin/tq")" -ge 2 ]         # set_task/append_note/done-when rename
  grep -Fq 'mv "$DIR/.$id.tmp" "$DIR/$id.json"' "$ROOT/bin/tq"  # add() renames too
}

@test "tq: no session id errors cleanly" {
  run env -u CLAUDE_COMPANION_SESSION_ID -u CLAUDE_CODE_SESSION_ID "$TQ" add x
  [ "$status" -ne 0 ]
  [[ "$output" == *"session id"* ]]
}

@test "tq: done-when — --done on add + the done-when subcommand STORE it; report omits it (D/R47, resurfaced on resume)" {
  ( cd "$ROOT" && "$TQ" add "wire export" --done "downloads a .csv" ) >/dev/null
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "downloads a .csv" ]   # stored in the task
  run "$TQ" report
  [[ "$output" == *"#1"*"wire export"* ]]                # the task is listed
  [[ "$output" != *"done when"* ]]                       # …but the compact report does NOT render done-when (Design D)
  ( cd "$ROOT" && "$TQ" add "plain" ) >/dev/null          # no --done → empty, no done-when line
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "" ]
  "$TQ" done-when 2 "no errors on load" >/dev/null         # set it after the fact
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "no errors on load" ]
}

# ---- R56 P2: characterization tests for beacon-class gaps the coverage audit found ----
# (intended, load-bearing behaviors a green from-scratch regen would silently drop)

@test "tq stopfields: the pointer is the first STARTABLE task, and every blocker counts (R87)" {
  # R87's real claim ("the selection exists in exactly one place") lives in tq stopfields itself —
  # stop-autopilot.sh only ever READ it. That hook is retired (R100/Pass 4); stopfields is not, so
  # this now drives the CLI directly instead of through the deleted Stop-hook wrapper.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=depT d="$CLAUDE_COMPANION_TASKS_DIR/depT"
  mkdir -p "$d"; _stamp_root "$d" "$repo"
  # field 5 is the bare next-id (no leading '#' — that's report's rendering, not stopfields' data).
  _nextid() { CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f5; }

  # The id it names must be the first STARTABLE task, not merely the first open one. A subject
  # saying "after #N" is not startable while #N is live — the same rule `tq report` applies.
  jq -n '{id:"38",subject:"❓ [parked] pick one",status:"pending"}'    > "$d/38.json"
  jq -n '{id:"50",subject:"sharpen it (after #38)",status:"pending"}' > "$d/50.json"
  [ -z "$(_nextid)" ]                          # blocker live → nothing startable
  jq -n '{id:"38",subject:"❓ [parked] pick one",status:"completed"}'  > "$d/38.json"
  [ "$(_nextid)" = "50" ]                       # answered → #50 is offered

  # Only a queue whose waiting task sorts BEFORE its blocker separates "first startable" from
  # "first open": with #10 waiting on #90, an $o[0] pointer would offer the blocked #10.
  rm "$d/50.json"
  jq -n '{id:"10",subject:"needs the other first (after #90)",status:"pending"}' > "$d/10.json"
  jq -n '{id:"90",subject:"the prerequisite",status:"pending"}'                  > "$d/90.json"
  [ "$(_nextid)" = "90" ]

  # A dangling reference must not strand work forever.
  rm "$d/10.json" "$d/90.json"
  jq -n '{id:"60",subject:"orphan ref (after #999)",status:"pending"}' > "$d/60.json"
  [ "$(_nextid)" = "60" ]

  # EVERY blocker counts, not just the first.
  rm "$d/60.json"
  jq -n '{id:"40",subject:"two blockers (after #50) and (after #60)",status:"pending"}' > "$d/40.json"
  jq -n '{id:"50",subject:"first blocker",status:"completed"}'                          > "$d/50.json"
  jq -n '{id:"60",subject:"second blocker",status:"pending"}'                           > "$d/60.json"
  [ "$(_nextid)" != "40" ]      # still held: #60 is open
  jq -n '{id:"60",subject:"second blocker",status:"completed"}'                         > "$d/60.json"
  [ "$(_nextid)" = "40" ]       # both closed → startable
}

@test "the QUEUE is repo state: it survives into a fresh clone with no home state (R96 stage 2)" {
  # The queue IS the product, so a cloud agent starting with an empty one has nothing to drain.
  # env -u is load-bearing: the suite exports CLAUDE_COMPANION_TASKS_DIR to isolate, and that
  # variable deliberately WINS over the repo store — so a test that left it set would be asserting
  # the old behaviour while believing it tested the new one.
  # HOME is overridden for EVERY step, not just the clone one. Without that this test reads the
  # REAL home store, and a session id that happens to exist there triggers the legacy fallback —
  # which is exactly how it passed alone and failed inside the suite.
  local r hbase; r="$(_tmpd)"; git -C "$r" init -q; hbase="$(_tmpd)"
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s1 "$3" add "ship the widget"' _ "$r" "$hbase" "$TQ"
  [ "$status" -eq 0 ]
  [ -f "$r/.companion/tasks/1.json" ]             # stored IN the repo, FLAT — no session subdir

  # THE POINT OF FLATTENING: a DIFFERENT session must see the queue. A clone or container always
  # has a new session id, and while the store was session-partitioned the tasks travelled with the
  # repo while the drain read an empty directory — the data was there and the system could not use
  # it. This assertion is the one that was missing when that shipped.
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=OTHER "$3" stopfields false' _ "$r" "$hbase" "$TQ"
  [[ "$output" == *"ship the widget"* ]]

  # ...and the RESUME path must read the flat store too, or a carried queue drains but never gets
  # re-surfaced after a compaction. The mutation gate reported exactly this branch as a hole.
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" "$3"' _ "$r" "$hbase" "$RESUME"
  [[ "$output" == *"ship the widget"* ]]

  # a fresh container: a copy of the repo, and a home directory with nothing in it
  local c h; c="$(_tmpd)"; h="$(_tmpd)"
  cp -r "$r/.git" "$c/.git"; cp -r "$r/.companion" "$c/.companion"
  git -C "$c" checkout -q -- . 2>/dev/null || true
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s1 "$3" report' _ "$c" "$h" "$TQ"
  [[ "$output" == *"ship the widget"* ]]

  # an explicit store still wins absolutely — that is how every other test isolates
  local ext; ext="$(_tmpd)"; mkdir -p "$ext/s2"
  run bash -c 'cd "$1" && HOME="$4" CLAUDE_COMPANION_TASKS_DIR="$2" CLAUDE_COMPANION_SESSION_ID=s2 "$3" add "elsewhere"' _ "$r" "$ext" "$TQ" "$hbase"
  [ -f "$ext/s2/1.json" ]
  [ ! -f "$ext/s2/2.json" ]                       # ...and did not land in the repo store either

  # a session ALREADY in the legacy home store keeps working there — upgrading orphans nothing
  local h2; h2="$(_tmpd)"; mkdir -p "$h2/.claude/companion/tasks/s3"
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s3 "$3" add "legacy work"' _ "$r" "$h2" "$TQ"
  [ -f "$h2/.claude/companion/tasks/s3/1.json" ]
  [ ! -f "$r/.companion/tasks/2.json" ]           # legacy session kept its own store
}

@test "tq orphans: state kinds are DERIVED from source, so dead state cannot hide (R96)" {
  # Deleting a feature used to leave its state behind forever — captures/, review/, intent-* and
  # reminded-* all outlived the code that wrote them, and only a hand grep could tell. The known
  # kinds are derived from the shipped source rather than listed, because a list is a second thing
  # to update whenever a kind is added.
  local sd; sd="$(_tmpd)"
  mkdir -p "$sd/autopilot" "$sd/tasks" "$sd/slcache" "$sd/somethingdead" "$sd/intent-abc"
  : > "$sd/ratelimit"
  _orph() { run env CLAUDE_COMPANION_STATE_DIR="$sd" CLAUDE_COMPANION_SESSION_ID=o "$TQ" orphans "$@"; }

  _orph
  [ "$status" -eq 0 ]
  [[ "$output" == *"somethingdead"* ]]      # no shipped code builds this path
  [[ "$output" == *"intent-abc"* ]]
  [[ "$output" != *"orphan: autopilot"* ]]  # ...but a real mode kind is NOT flagged
  [[ "$output" != *"orphan: tasks"* ]]
  [[ "$output" != *"orphan: ratelimit"* ]]
  [[ "$output" != *"orphan: slcache"* ]]

  # report is the default — nothing is removed without asking
  [ -d "$sd/somethingdead" ]

  _orph --orphans
  [ ! -d "$sd/somethingdead" ]; [ ! -d "$sd/intent-abc" ]
  [ -d "$sd/autopilot" ]; [ -d "$sd/tasks" ]   # the live ones survive

  _orph
  [[ "$output" == *"none"* ]]
}

@test "tq report: glyph-count header + → next pointer (R56 G3/G4 — R47 spec)" {
  ( cd "$ROOT" && "$TQ" add "task one" ) >/dev/null
  ( cd "$ROOT" && "$TQ" add "task two" ) >/dev/null
  run bash -c 'cd "$1" && "$2" report' _ "$ROOT" "$TQ"
  [[ "$output" == *"📋"* ]]                 # the glyph-count header line
  [[ "$output" == *"◻2"* ]]                 # 2 open, counted in the header
  [[ "$output" == *"→ next: #1"* ]]         # pointer = head of the open queue
  ( cd "$ROOT" && "$TQ" doing 2 ) >/dev/null
  run bash -c 'cd "$1" && "$2" report' _ "$ROOT" "$TQ"
  [[ "$output" == *"▸1"* ]]                 # 1 in-progress, counted
  [[ "$output" == *"→ next: #2"* ]]         # the in-progress task becomes next
}

@test "tq delta (R69): add/doing print a one-line counts delta, NOT the full queue; done prints the full report" {
  run bash -c 'cd "$1" && "$2" add "first task" "second task"' _ "$ROOT" "$TQ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added #1"* ]] && [[ "$output" == *"added #2"* ]]   # per-add lines stay
  [[ "$output" == *"📋"* ]] && [[ "$output" == *"◻2"* ]]              # counts delta present…
  [[ "$output" == *"→ next: #1"* ]]                                    # …with the next pointer
  # delta ≠ full report: subjects are NOT read back on a mutation (the token-spend R69 removes)
  last="$(printf '%s\n' "$output" | tail -1)"
  [[ "$last" != *"first task"* ]] && [[ "$last" != *"second task"* ]]
  run bash -c 'cd "$1" && "$2" doing 1' _ "$ROOT" "$TQ"
  [[ "$output" == *"▸1"* ]] && [[ "$output" != *"first task"* ]]       # doing: delta only
  run bash -c 'cd "$1" && "$2" done 1' _ "$ROOT" "$TQ"
  [[ "$output" == *"second task"* ]]                                    # done: FULL report (boundary)
}

@test "tq note: appends to .notes[] cumulatively, never overwrites (R56 G4 — PR #126)" {
  ( cd "$ROOT" && "$TQ" add "with notes" ) >/dev/null
  ( cd "$ROOT" && "$TQ" note 1 "first" ) >/dev/null
  ( cd "$ROOT" && "$TQ" note 1 "second" ) >/dev/null
  local f; f="$(ls "$CLAUDE_COMPANION_TASKS_DIR"/*/1.json | head -1)"
  [ "$(jq '.notes | length' "$f")" -eq 2 ]            # both breadcrumbs kept (not overwritten)
  [ "$(jq -r '.notes[0].text' "$f")" = "first" ]      # first preserved
  [ "$(jq -r '.notes[1].text' "$f")" = "second" ]     # second appended after it
}

@test "tq: stamps the session .root with the actual git toplevel (R56 G8 — cross-session scope)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$TQ" add "scoped" ) >/dev/null
  # not just that .root exists (already pinned) — that it holds the CORRECT root, else resume mis-scopes
  [ "$(cat "$CLAUDE_COMPANION_TASKS_DIR/s1/.root")" = "$(git -C "$repo" rev-parse --show-toplevel)" ]
}

@test "tq prune: removes FINISHED old stores, never one with open/parked/blocked work (R81)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  _mk() {  # $1=dirname  $2=status  $3=subject
    mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$1"
    printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/$1/.repo"
    jq -n --arg s "$3" --arg st "$2" '{id:"1",subject:$s,status:$st}' > "$CLAUDE_COMPANION_TASKS_DIR/$1/1.json"
    # backdate everything so the age window can't be what saves it
    find "$CLAUDE_COMPANION_TASKS_DIR/$1" -exec touch -t 202001010000 {} + 2>/dev/null || true
  }
  _mk done1   completed   "shipped"
  _mk done2   cancelled   "dropped"
  _mk open1   pending     "still open"
  _mk doing1  in_progress "mid-flight"
  _mk park1   pending     "❓ [parked] a decision"
  _mk block1  pending     "⏳ [blocked] owner action"
  # another repo's finished store must be invisible to this repo's prune (no cross-project bleed)
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/other"; printf '/somewhere/else' > "$CLAUDE_COMPANION_TASKS_DIR/other/.root"
  jq -n '{id:"1",subject:"theirs",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/other/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/other" -exec touch -t 202001010000 {} + 2>/dev/null || true

  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  # finished stores gone
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/done1" ]
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/done2" ]
  # every flavour of unfinished work survives
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/open1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/doing1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/park1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/block1" ]
  # and another project's store is untouched
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/other" ]
}

@test "tq prune: age protects a RECENT finished store, and --dry-run deletes nothing" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/fresh"; printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/fresh/.repo"
  jq -n '{id:"1",subject:"just finished",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/fresh/1.json"
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/fresh" ]        # recent → kept despite being finished
  # old + finished, but dry-run must not remove it
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/old"; printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/old/.repo"
  jq -n '{id:"1",subject:"ancient",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/old/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/old" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30 --dry-run' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"* ]]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/old" ]          # dry run: still there
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/old" ]        # real run: gone
}

@test "tq prune: an UNREADABLE task file means KEEP, never delete (jq exit status, not stdout)" {
  # `jq -s` prints 0 AND exits 2 when it cannot OPEN a file, so reading stdout alone turned
  # "unreadable" into "zero open tasks" and destroyed a store holding a parked decision.
  [ "$(id -u)" -ne 0 ] || skip "running as root: chmod 000 is not enforced"
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/locked"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/locked/.repo"
  jq -n '{id:"1",subject:"❓ [parked] owner decision",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json"
  chmod 000 "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/locked" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  chmod 644 "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json" 2>/dev/null || true
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/locked" ]
}

@test "tq prune: a SYMLINKED session dir is skipped — rm -rf must not recurse through the link" {
  # The glob yields a trailing slash, which makes rm -rf follow the link and empty the TARGET:
  # an archived session dir outside the store was destroyed while the link itself survived.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  local arch; arch="$(_tmpd)"; mkdir -p "$arch/real"
  printf 'IRREPLACEABLE\n' > "$arch/real/notes.md"
  printf '%s' "$rid" > "$arch/real/.repo"
  jq -n '{id:"1",subject:"long done",status:"completed"}' > "$arch/real/1.json"
  ln -s "$arch/real" "$CLAUDE_COMPANION_TASKS_DIR/archived"
  find "$arch" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  [ -f "$arch/real/notes.md" ]     # the target survived
  rm -rf "$arch"
}

@test "tq report: a park shows its rec:, and 'next' names the decision when nothing is buildable" {
  # A park is REQUIRED to carry `options:`/`rec:` so the review is a decision and not a rubber
  # stamp — and the 72-char truncation cut at exactly the point where `rec:` begins, so the
  # convention was stored and then hidden in the one place anyone reads it.
  export CLAUDE_COMPANION_SESSION_ID=sRec
  local d="$CLAUDE_COMPANION_TASKS_DIR/sRec"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend — options: A) sqlite (one file, needs a dep) B) plain files (no dep, slower); rec: A — the dep is already vendored",status:"pending"}' > "$d/1.json"
  run "$TQ" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"└ rec: A — the dep is already vendored"* ]]   # the deciding half survives
  # With nothing buildable, "next" must not point at a task — it must name the decision.
  [[ "$output" == *"nothing left to build"* ]]
  [[ "$output" != *"→ next: #1"* ]]

  # A park WITHOUT a rec has no continuation line to show — and must not invent one.
  jq -n '{id:"2",subject:"❓ [parked] something undecided",status:"pending"}' > "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"something undecided"* ]]
  [ "$(printf '%s' "$output" | grep -c '└ rec:')" -eq 1 ]

  # Buildable work still wins: `next` stays mechanical and points at the open task, not the park.
  jq -n '{id:"3",subject:"do the actual thing",status:"pending"}' > "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #3"* ]]
  [[ "$output" != *"nothing left to build"* ]]
}

@test "tq report: a parks-only queue names the next action, not just the counts" {
  # Asked to "continue" with nothing buildable, the honest answer is not silence — it is which
  # command clears the pile. Mechanical, so it survives a compaction without costing injected prose.
  export CLAUDE_COMPANION_SESSION_ID=sNx
  local d="$CLAUDE_COMPANION_TASKS_DIR/sNx"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] a decision; rec: A",status:"pending"}'    > "$d/1.json"
  jq -n '{id:"2",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"decision(s) for you"* ]]
  [[ "$output" == *"manual job(s) only you can do"* ]]   # ⏳ is the owner's to-do list
  [[ "$output" == *"/companion:review"* ]]
  [[ "$output" == *"resumes autopilot if it was on"* ]]
}

@test "tq: concurrent adds cannot lose a task — a HOOK is now a writer (R84)" {
  # tq's header said id allocation needed no locking because "one model drives tq serially". The
  # ask-guard made that false: two writers computed the same id and the second mv silently
  # overwrote the first, so parked DECISIONS disappeared while the model was told they were saved.
  export CLAUDE_COMPANION_SESSION_ID=sRace
  local i
  for i in 1 2 3 4 5 6; do "$TQ" add "concurrent subject $i" >/dev/null 2>&1 & done
  wait
  local dir="$CLAUDE_COMPANION_TASKS_DIR/sRace"
  [ "$(ls "$dir"/*.json | wc -l)" -eq 6 ]
  [ "$(cat "$dir"/*.json | jq -r .subject | sort -u | wc -l)" -eq 6 ]   # none lost
  [ "$(cat "$dir"/*.json | jq -r .id | sort | uniq -d | wc -l)" -eq 0 ] # no duplicate ids
}

@test "tq report: next skips work that waits on an unanswered item (R47)" {
  # The drain loop offered the same blocked task four times in a row, because the queue could not
  # express "waiting on #N" — work blocked by an unanswered park looked identical to work that was
  # ready. Convention: the subject names `after #N`.
  export CLAUDE_COMPANION_SESSION_ID=sWait
  local d="$CLAUDE_COMPANION_TASKS_DIR/sWait"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick the source of truth; rec: A",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"sharpen the prose (after #1)",status:"pending"}'                 > "$d/2.json"
  jq -n '{id:"3",subject:"an unrelated ready task",status:"pending"}'                      > "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #3"* ]]        # the READY task, not the blocked one
  [[ "$output" != *"→ next: #2"* ]]

  # With only the blocked task left, say so rather than pointing at work that cannot start.
  rm "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"nothing STARTABLE"* ]]
  [[ "$output" != *"→ next: #2"* ]]

  # Answering the dependency makes it startable — the block must lift on its own.
  jq -n '{id:"1",subject:"picked",status:"completed"}' > "$d/1.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #2"* ]]

  # A task waiting on something that never existed is not blocked forever.
  jq -n '{id:"4",subject:"waits on a ghost (after #999)",status:"pending"}' > "$d/4.json"
  rm "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #4"* ]]
}

@test "board: groups tasks into the same typed lanes as tq report, done rendered as a real list" {
  # tq report/delta collapse DONE to a count on purpose (R69 — injected every mutation); board is
  # explicitly invoked and never injected, so it can afford to list completed tasks individually.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"do the actual thing",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"❓ [parked] pick a cache backend — options: A) sqlite B) files; rec: sqlite — vendored already",status:"pending"}' > "$d/2.json"
  jq -n '{id:"3",subject:"first finished thing",status:"completed"}' > "$d/3.json"
  jq -n '{id:"4",subject:"second finished thing",status:"completed"}' > "$d/4.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"◻ OPEN"* ]]; [[ "$output" == *"do the actual thing"* ]]
  [[ "$output" == *"❓ PARKED"* ]]; [[ "$output" == *"└ rec: sqlite — vendored already"* ]]
  # Both completed tasks are listed BY ID, not folded into a bare "✔2" count.
  [[ "$output" == *"✔ #3  first finished thing"* ]]
  [[ "$output" == *"✔ #4  second finished thing"* ]]
}

@test "board: an open task waiting on a live after #N shows the wait, not just silence" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"first thing",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"second thing after #1",status:"pending"}' > "$d/2.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"#2  second thing after #1   ⧗ waiting on #1"* ]]
  # #1 has nothing blocking it, so it carries no wait note.
  [[ "$output" == *"#1  first thing"$'\n'* ]] || [[ "$output" == *"#1  first thing" ]]
}

@test "board: the beyond-the-queue section reflects candidates.sh, read-only" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  printf '# R\n- [ ] add a dark theme\n' > "$repo/ROADMAP.md"
  git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m r
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(queue empty)"* ]]
  [[ "$output" == *"beyond the queue"* ]]; [[ "$output" == *"display only"* ]]
  [[ "$output" == *"[roadmap] add a dark theme"* ]]
}

@test "tq add --context / tq context: sets and updates a task's context pointer (R99)" {
  run "$TQ" add "wire the retry logic" --done "429 retried with backoff" --context "lib/http.go"
  [ "$status" -eq 0 ]; [[ "$output" == *"context: lib/http.go"* ]]
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "lib/http.go" ]

  run "$TQ" context 1 "lib/http.go, lib/backoff.go"
  [ "$status" -eq 0 ]; [[ "$output" == *"context set"* ]]
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "lib/http.go, lib/backoff.go" ]

  # Adding with no --context leaves the field empty, not absent — same convention as done_when.
  run "$TQ" add "an unscoped task"
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "" ]
}

@test "board: context and done_when render as continuation lines when present (R99)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"wire the retry logic",status:"pending",done_when:"429 retried with backoff",context:"lib/http.go"}' > "$d/1.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"└ done when: 429 retried with backoff"* ]]
  [[ "$output" == *"└ context: lib/http.go"* ]]
}

@test "board: one corrupt task file is skipped, not a blank board (DA-caught)" {
  # jq -rs ABORTS on the first unparseable file — companion_open_tasks was already burned by
  # this exact shape (7 open tasks silently rendered as 0). board must not repeat it.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"a fine task",status:"pending"}' > "$d/1.json"
  printf '{not valid json' > "$d/2.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a fine task"* ]]                       # the good task still renders
  [[ "$output" == *"1 task file(s) unreadable"* ]]          # and the bad one is named, not silent
  [[ "$output" != *"(queue empty)"* ]]
}

@test "board: waiting-on clears once the blocker is done, not forever (DA-caught)" {
  # dep()'s select used \$live|index(.) — inside select, . rebinds to \$live itself, so it matched
  # EVERY id regardless of liveness. #2 named two blockers; both are done here, so neither should show.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"first thing",status:"completed"}' > "$d/1.json"
  jq -n '{id:"2",subject:"second thing after #1 and after #3",status:"pending"}' > "$d/2.json"
  jq -n '{id:"3",subject:"third thing",status:"completed"}' > "$d/3.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"#2  second thing after #1 and after #3"* ]]
  [[ "$output" != *"waiting on"* ]]

  # A genuinely LIVE blocker still shows — and #1 (done) must not be named as a wait target,
  # even though "#1" itself still legitimately appears in the subject text ("after #1").
  jq -n '{id:"3",subject:"third thing",status:"pending"}' > "$d/3.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"⧗ waiting on #3"* ]]
  [[ "$output" != *"waiting on #1"* ]]; [[ "$output" != *"waiting on #1, #3"* ]]
}

@test "tq add: --context and --done cannot swallow each other as a value (DA-caught)" {
  # tq add "s" --context --done "x" silently parsed --context's value as the literal "--done",
  # then treated "x" as a SECOND bogus task subject instead of --done's value.
  run "$TQ" add "subject" --context --done "x"
  [ "$status" -ne 0 ]; [[ "$output" == *"--context needs a value"* ]]
  [ ! -f "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json" ]   # nothing was added on the refused call

  run "$TQ" add "subject2" --done --context "y"
  [ "$status" -ne 0 ]; [[ "$output" == *"--done needs a value"* ]]
}

# ── R109: evidence at the completion boundary ────────────────────────────────────────────────
# The recorded failure (owner, 2026-08-10): completion declared at the boundary of what a shell can
# observe, when the owner's experience of the work lived one layer further out. `--seen` cannot
# verify an observation happened (R28 ceiling, same as da-gate.sh's own pass) — it makes the claim
# WRITTEN and READABLE at the moment of closing.

@test "tq done --seen: a rubber stamp leaves the task OPEN; a real observation closes it and renders in list (R109)" {
  run "$TQ" add "ship the media fix"
  [ "$status" -eq 0 ]

  # THE LOAD-BEARING HALF. A gate that complains about a task it has ALREADY closed is decorative:
  # the refusal must happen before the state change, or the queue records a completion the gate
  # rejected. This assertion is why the guard runs before set_task, not after.
  run "$TQ" done 1 --seen "tests pass"
  [ "$status" -eq 2 ]
  run "$TQ" list
  [[ "$output" == *"[pending]"* ]]

  run "$TQ" done 1 --seen "opened the review screen in Expo Go on the device; media thumbnails loaded"
  [ "$status" -eq 0 ]
  # THE READER. A field nobody prints is pure cost — that is R58·a's retired capture hook (456KB
  # banked, zero readers). If this assertion is deleted, the field should be deleted with it.
  run "$TQ" list
  [[ "$output" == *"[completed]"* ]]
  [[ "$output" == *"seen: opened the review screen in Expo Go"* ]]

  # OPTIONAL BY DESIGN. Mandatory evidence would gate every routine close behind prose and train
  # the exact rubber-stamping the gate exists to refuse.
  run "$TQ" add "routine cleanup"
  run "$TQ" done 2
  [ "$status" -eq 0 ]
}

@test "tq dependencies: ONLY 'after #<id>' blocks, and the syntax is documented where the author looks (R87)" {
  # MEASURED FAILURE, 2026-08-12. The owner reported autopilot not draining the backlog. `stopfields`
  # said STARTABLE=4 while every one of those tasks was in fact waiting on an unanswered park — the
  # dependencies existed only in prose. Root cause: `after #<id>` is the ONLY syntax stopfields()
  # reads, and it was documented NOWHERE. The author (me) had written "(after 1/2)" intending a
  # dependency; it parsed as nothing, so the task looked perfectly startable. A dependency that
  # silently fails to parse is worse than one that errors: the queue reports confident nonsense.
  export CLAUDE_COMPANION_SESSION_ID=deps1
  run "$TQ" add "first"
  run "$TQ" add "second (after 1/2)"          # the near-miss syntax — must NOT block
  run "$TQ" add "third after #1"              # the real syntax — must block

  run bash -c '"$1" stopfields false | tr "\037" "|"' _ "$TQ"
  local startable; startable="$(printf '%s' "$output" | awk -F'|' '{print $7}')"
  [ "$startable" -eq 2 ] || { echo "expected 2 startable (#3 blocked by #1), got $startable" >&2; false; }

  # Close the blocker: the dependent becomes startable. Without this the test would pass on a
  # stopfields that simply never counted #3 at all.
  run "$TQ" done 1
  run bash -c '"$1" stopfields false | tr "\037" "|"' _ "$TQ"
  startable="$(printf '%s' "$output" | awk -F'|' '{print $7}')"
  [ "$startable" -eq 2 ] || { echo "expected 2 startable after unblocking, got $startable" >&2; false; }

  # DISCOVERABILITY is the fix, not the parser. The behaviour was always correct; nothing told the
  # author the syntax existed, so it was never used. If this line goes, the trap comes back.
  run bash -c '"$1" --help 2>&1' _ "$TQ"
  [[ "$output" == *"after #<id>"* ]]
  [[ "$output" == *"silently ignored"* ]]
}

@test "board: names the work in flight by CLASS, and stays quiet on a clean tree (R116·b)" {
  # The state lanes answer "what is queued"; this answers "what SHAPE is the change you are building
  # right now" — specifically whether ship will demand a branch for it. Deliberately on the BOARD and
  # not the status line: class is a property of a CHANGE, not of a task, and the bar already carries
  # ten segments answering "what needs me now".
  local d; d="$(_tmpd)"; git -C "$d" init -q -b main
  mkdir -p "$d/docs/flows" "$d/src"
  echo x > "$d/src/a.sh"; { echo '# flow:f'; echo 'steps:'; echo '- a'; } > "$d/docs/flows/f.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -qm base
  local _b; _b() { run bash -c 'cd "$1" && "$2"' _ "$d" "$BOARD"; }

  _b; [[ "$output" != *"work in flight"* ]]        # clean tree -> nothing to say

  echo y >> "$d/src/a.sh"
  _b; [[ "$output" == *"work in flight: ordinary"* ]]
  [[ "$output" != *"FEATURE-CLASS"* ]]

  echo '- b' >> "$d/docs/flows/f.md"               # now a flow page moved WITH implementation
  _b
  [[ "$output" == *"FEATURE-CLASS"* ]]
  [[ "$output" == *"merges on your say-so"* ]]     # it says what will happen at ship, not just a label
}

@test "review_pile: classifies the owner's pile by HOW it must be asked, and is silent when clear" {
  # Extracted from commands/review.md so a non-Claude client can drive a review at all (R100).
  # The class is not cosmetic — it decides the interaction: a ⏳ is an owner ACTION and must never be
  # offered as a recommendation to accept; a decompose-park carries QUESTIONS, so a menu would be
  # premature; a park with no rec: is owed a full menu, because batch-accepting it is a rubber stamp.
  local d; d="$(_tmpd)"; git -C "$d" init -q; mkdir -p "$d/.companion/tasks"
  local RP="$ROOT/bin/review-pile.sh"
  _rp() { run env REVIEW_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="" bash "$RP"; }

  _rp; [ "$status" -eq 0 ]; [ -z "$output" ]        # clear pile -> silent, a clean no-op

  jq -n '{id:"1",subject:"⏳ [blocked] owner deploys it",status:"pending"}'                    > "$d/.companion/tasks/1.json"
  jq -n '{id:"2",subject:"❓ [parked] decompose: big thing — need: which store?",status:"pending"}' > "$d/.companion/tasks/2.json"
  jq -n '{id:"3",subject:"❓ [parked] rev: pick a cache — options: A) x B) y; rec: A",status:"pending"}' > "$d/.companion/tasks/3.json"
  jq -n '{id:"4",subject:"❓ [parked] pick a colour",status:"pending"}'                        > "$d/.companion/tasks/4.json"
  jq -n '{id:"5",subject:"plain open work",status:"pending"}'                                 > "$d/.companion/tasks/5.json"
  jq -n '{id:"6",subject:"❓ [parked] already handled",status:"completed"}'                     > "$d/.companion/tasks/6.json"

  _rp; [ "$status" -eq 0 ]
  [[ "$output" == *"blocked"$'\t'"1"* ]]
  [[ "$output" == *"decompose"$'\t'"2"* ]]
  [[ "$output" == *"options-rec"$'\t'"3"* ]]
  [[ "$output" == *"options"$'\t'"4"* ]]
  [[ "$output" != *"plain open work"* ]]           # doing, not deciding — a menu here is noise
  [[ "$output" != *"already handled"* ]]           # finished items are not the owner's problem
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 4 ]

  # a decompose park that ALSO carries rec: is still decompose — questions outrank a stray pick
  jq -n '{id:"7",subject:"❓ [parked] decompose: x — need: y; rec: z",status:"pending"}' > "$d/.companion/tasks/7.json"
  _rp; [[ "$output" == *"decompose"$'\t'"7"* ]]
}
