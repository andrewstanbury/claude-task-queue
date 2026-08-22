#!/usr/bin/env bats
#
# CROSS-CUTTING INVARIANTS - the properties that belong to no single subsystem: self-containment,
# foreign-repo behaviour, prefix-views over status, repo-state ledgers, and the advisory-vs-enforced
# boundaries. Subject-specific cases live in the sibling companion-*.bats files (split 2026-08-16).

load helper


@test "bin/lib scripts use no bash-4-only builtins — macOS CI runs bash 3.2 (regression guard)" {
  # mapfile/readarray are Bash 4+; macOS CI's /bin/bash is 3.2, but a dev on bash 5 won't see the
  # failure locally — it shipped red once (R60 used mapfile in tq). Grep the enforced-core scripts
  # for the builtins as invoked; if any appears, CI on macOS will `command not found`.
  run grep -rnE '(mapfile|readarray)' "$ROOT/bin" "$ROOT/lib"
  [ "$status" -ne 0 ]                                # no match → grep exits non-zero → clean
}

@test "command prompts retain their critical gate steps (R56 P3 — structural guard for prose)" {
  # Prose behavior can't be tested behaviorally (it's Claude's judgment, R28); the ceiling is a
  # structural guard that a command's non-negotiable gate INSTRUCTION wasn't deleted (like a regen
  # of a .md might do). Catches deletion, not a subtler regression — the honest best for prose.
  local C="$ROOT/commands"
  grep -q "invariant net covers the app"   "$C/redesign.md"     # D0 coverage gate
  grep -qE "bounded, check-gated|never.*unbounded" "$C/redesign.md"  # D2/D3 bounded passes
  grep -q 'autopilot_toggle'               "$C/redesign.md"     # step-0 autopilot clear (R100/Pass 5b: MCP tool, not raw script)
  grep -q "auto-revert"                    "$C/redesign.md"     # R5 rollback-on-red (inlined regen engine)
  grep -qE "Refuse to (regenerate|proceed)" "$C/redesign.md"    # R3 checks-first + D1 document gate
  grep -q "REQUIRED first step"            "$C/redesign.md"     # D1 document-first requirement (R55)
  grep -q "Verify FIRST"                   "$C/ship-it.md"      # verify before commit
  grep -q "Never force-push"               "$C/ship-it.md"      # never rewrite published history
  grep -q "Sync the contract"              "$C/ship-it.md"      # R57 contract-sync step
  grep -q "Propose the flow-page update"   "$C/ship-it.md"      # R57/R62 flow-page proposal (owner-governed, not silent)
  grep -q "anti-laundering"                "$C/docs.md"     # only the owner's pick records a 🔒
  grep -q "autopilot"                      "$C/resume.md"       # resume respects/clears autopilot
  grep -qF 'resume`** MCP tool'            "$C/resume.md"       # resume runs the session-pickup re-surface (R39, R100/Pass 5b)
  grep -q "companion:review"               "$C/resume.md"       # pickup hands off to review (R39 re-split)
  grep -qE "parked|❓"                       "$C/review.md"       # review walks the parked pile (R38)
  # R83: review PAUSES rather than kills — it must disarm to ask, then put autopilot back. Both
  # halves are load-bearing: pause without resume is the old behaviour with extra steps, and the
  # guard has to pin the pair or the resume can quietly disappear.
  grep -q 'autopilot_toggle.*action: "pause"' "$C/review.md"    # review disarms to ask (R83, R100/Pass 5b)
  grep -q 'action: "resume"'               "$C/review.md"       # ...and re-arms when done (R83, R100/Pass 5b)
  grep -qiE "up front|upfront"             "$C/review.md"       # the whole pile at once, not drip-fed
  grep -qiE "before .*new work"            "$C/review.md"       # R38 write-back-before-new-work
  # R112 accept sweep (owner-asked 2026-08-12). The FEATURE is the multiSelect batch; the SAFETY
  # is that an unticked box is not a decision. A multiSelect returns only the PRESENCE of a yes,
  # so a review that read absence as "no" would silently invent rejections across the whole pile —
  # which is worse than the drip-feed it replaces. Both halves pinned, and the exclusions with
  # them: ⏳ is an owner ACTION (nothing to "accept"), and a decompose-park has no options yet.
  grep -q 'multiSelect: true'              "$C/review.md"       # the sweep exists at all
  grep -qE "Unselected is NOT rejected|not ticked is not a no" "$C/review.md"   # absence != rejection
  grep -qiE "NOT eligible for the sweep"   "$C/review.md"       # ⏳ + decompose-park stay out (R65)
  grep -qiE "asks before it writes|buy-in still comes first|recommendation-first" "$C/cover.md"  # R58·d amended by R61/R62: cover SCAFFOLDS, but buy-in (owner picks) still precedes any write
  grep -q 'autopilot_toggle'               "$C/cover.md"        # cover clears autopilot (it asks) — R100/Pass 5b: MCP tool, not raw script
}

@test "manual resume: lists THIS repo's open tasks on demand (and says so when none)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sM"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sM" "$repo"
  jq -n '{id:"1",subject:"pick me up",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/1.json"
  jq -n '{id:"2",subject:"already shipped",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pick me up"* ]]          # open task surfaced
  [[ "$output" != *"already shipped"* ]]     # completed excluded
  # a repo with nothing says so
  local empty; empty="$(_tmpd)"; git -C "$empty" init -q
  run bash -c 'cd "$1" && "$2"' _ "$empty" "$RESUME"
  [[ "$output" == *"No carried-over"* ]]
}

@test "manual resume: turns autopilot OFF first, announced when on and quiet when off (R39)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "on" ]                  # armed
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"autopilot was ON"* ]]                     # the flip is announced, not silent
  [ "$(cd "$repo" && "$AP" status)" = "off" ]                 # flag for THIS root actually cleared
  # second run: already off → quiet no-op, no autopilot notice
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"autopilot was ON"* ]]
}

@test "UN-6 foreign repos: the plugin works in ecosystems and paths it has never seen (R91)" {
  # UN-6 is "it works on other people's projects, in whatever language and shape they use", and it
  # was the LEAST verified need in the matrix — 2 requirements to UN-4's twelve, with zero fixtures
  # carrying a package.json, pyproject.toml, go.mod or Cargo.toml. Every fixture was a bare git
  # init, i.e. a repo shaped like this one. Probing found no defect; this keeps it that way.
  local base; base="$(_tmpd)"
  local st tk; st="$(_tmpd)"; tk="$(_tmpd)"

  # 1. TODO detection must be GENERIC (R9: no ecosystem allowlists). One marker, four languages.
  _eco() {  # $1 dir · $2 file · $3 marker line · $4 manifest name · $5 manifest body
    local r="$base/$1"; mkdir -p "$r/src"; git -C "$r" init -q
    printf '%s\n' "$3" > "$r/src/$2"; printf '%s\n' "$5" > "$r/$4"
    git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m i
    run env CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" \
        bash -c 'cd "$1" && "$2"' _ "$r" "$ROOT/bin/candidates.sh"
    [[ "$output" == *"3|todo|"* ]]
  }
  _eco js "app.js"   "// TODO: retry the upload"      package.json   '{"name":"w"}'
  _eco py "app.py"   "# TODO: handle the timeout"     pyproject.toml '[project]'
  _eco go "main.go"  "// TODO: bound the retry loop"  go.mod         'module w'
  _eco rs "main.rs"  "// FIXME: unwrap can panic"     Cargo.toml     '[package]'

  # 2. The per-repo flag must round-trip through paths the encoder has to escape.
  local d
  for d in "with space" "ünïcodé" "quo'te"; do
    mkdir -p "$base/$d"; git -C "$base/$d" init -q
    run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" on >/dev/null && cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" status' _ "$base/$d" "$st" "$AP"
    [ "$output" = "on" ]
    run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" off >/dev/null && cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" status' _ "$base/$d" "$st" "$AP"
    [ "$output" = "off" ]
  done

  # 3. The status line renders in a directory that is not a git repo at all.
  mkdir -p "$base/nogit"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"f\",model:{display_name:\"Opus\"}}" | NO_COLOR=1 "$2"' _ "$base/nogit" "$SL"
  [ "$status" -eq 0 ]; [ -n "$output" ]
}

@test "UN-6 foreign repos: tq stopfields and the burn loop work there too (R91)" {
  # The gap named when R91 shipped: the matrix covered candidates, flags and the status line, but
  # nothing drove the selection logic or burn-down through a foreign repo. A path WITH A SPACE is
  # the shape most likely to break an unquoted expansion, so every repo here has one. (R100/Pass 4:
  # this used to drive the Stop hook, now retired; tq stopfields carries the selection logic itself.)
  local base st tk; base="$(_tmpd)"; st="$(_tmpd)"; tk="$(_tmpd)"
  local r="$base/my app"; mkdir -p "$r"; git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  printf '{"name":"widget"}\n' > "$r/package.json"

  # --- the selection logic, in a repo it has never seen ---
  local sid=fgn d="$tk/fgn"; mkdir -p "$d"; _stamp_root "$d" "$r"
  jq -n '{id:"1",subject:"ship the widget",status:"pending"}' > "$d/1.json"
  local nid; nid="$(CLAUDE_COMPANION_TASKS_DIR="$tk" CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f5)"
  [ "$nid" = "1" ]                                 # it selects a task in a repo it has never seen
  jq -n '{id:"1",subject:"ship the widget",status:"completed"}' > "$d/1.json"   # done, so it doesn't outrank the burn loop below

  # --- the burn loop: two agreeing samples, then a real branch ---
  mkdir -p "$st/burndown"; touch "$(_flagpath "$st" burndown "$r")"
  local n; n="$(date +%s)"
  _fsnap() { printf '%s 20 %s %s %s\n' "$1" "$((n+7200))" "$2" "$((n+172800))" > "$st/ratelimit"; }
  _fbd()   { run env CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" \
                 BURNDOWN_ROOT="$r" bash "$ROOT/bin/burn-down.sh" status; }
  _fsnap "$((n-9))" 10; _fbd; [[ "$output" == HOLD:* ]]
  _fsnap "$((n-8))" 10; _fbd; [[ "$output" == BURN:* ]]

  # The dirty-tree refusal must hold in a foreign repo too — package.json is untracked here, and
  # starting autonomous work on top of someone else's uncommitted changes is the one thing this
  # guard exists to stop. (Found by this test: the first version left it untracked and got exit 4.)
  run env CLAUDE_COMPANION_STATE_DIR="$st" BURNDOWN_ROOT="$r" \
      bash "$ROOT/bin/burndown-branch.sh" start '3|todo|add offline mode'
  [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
  git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m manifest

  # a NON-ASCII candidate must still yield a usable branch and a manifest, in a spaced path
  run env CLAUDE_COMPANION_STATE_DIR="$st" BURNDOWN_ROOT="$r" \
      bash "$ROOT/bin/burndown-branch.sh" start '3|todo|añadir modo sin conexión'
  [ "$status" -eq 0 ]
  git -C "$r" branch | grep -q 'burndown/'
  [ -n "$(ls "$r/.companion/burndown-manifests" 2>/dev/null)" ]   # manifests are REPO state (R96)
}


@test "boundary lint: derives thresholds from SOURCE and catches a pinned fixture (R92)" {
  # A lint nobody invokes is a hole, and one that derives nothing passes vacuously — both failure
  # modes have happened in this repo, so this pins the real script rather than a re-implementation.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/bin" "$d/dev"
  printf 'FINAL="${BURNDOWN_FINAL_STRETCH:-86400}"\nTARGET="${T:-100}"\n' > "$d/plugins/companion/bin/x.sh"  # boundary-ok: this IS the lint's fixture
  cp "$ROOT/../../dev/portability-lint.sh" "$d/dev/" 2>/dev/null || cp dev/portability-lint.sh "$d/dev/"

  # a fixture pinned to the derived 86400 threshold → caught
  printf 'run _bd_left 50 86400\n' > "$d/t.bats"   # boundary-ok: sample input for the lint under test
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"86400s threshold"* ]]   # boundary-ok: sample input for the lint under test

  # the same line marked as a reviewed exemption → allowed
  printf 'run _bd_left 50 86400   # boundary-ok\n' > "$d/t.bats"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -eq 0 ]

  # a PERCENTAGE-sized constant must NOT be flagged — the first cut used >=60 and buried the real
  # hits under six innocent "100%" assertions
  printf 'assert "$out" = "100%%"\n' > "$d/t.bats"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -eq 0 ]

  # deriving NOTHING must FAIL loudly rather than pass vacuously
  rm "$d/plugins/companion/bin/x.sh"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"vacuously"* ]]
}

@test "⛔ ruled-out is a prefix-view that PERSISTS but is never work (R95)" {
  # The Apple/AWS incident: "the owner confirmed this twice" lived only in a context window, and
  # compaction destroyed it, so the innocent component kept being re-investigated. A closure has to
  # outlive the conversation that produced it. Like ❓/⏳ this is a PREFIX over pending (R42), never
  # a status value, so it rides the same resume path that already survives compaction.
  local sid=rlT d="$CLAUDE_COMPANION_TASKS_DIR/rlT"; mkdir -p "$d"
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" add "real buildable work"
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" add "⛔ [ruled out] Apple login config — owner confirmed twice"

  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" report
  [[ "$output" == *"⛔1"* ]]                       # counted in its own class...
  [[ "$output" == *"[ruled out] Apple login"* ]]   # ...rendered without doubling the glyph
  [[ "$output" == *"→ next: #1"* ]]                # ...and the pointer ignores it

  # the drain must not see it as startable, or a closure becomes a task
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false
  [[ "$output" == "1"* ]]                          # OPEN counts the real work only
  [[ "$output" == *"real buildable work"* ]]
  [[ "$output" != *"Apple login"* ]]

  # ...and with ONLY a ruled-out entry left, there is nothing to do at all
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" done 1
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false
  [[ "$output" == "0"* ]]
}

@test "the LEDGERS are repo state: a defect rate that resets with the container measures nothing (R96 stage 3)" {
  local r h; r="$(_tmpd)"; git -C "$r" init -q; h="$(_tmpd)"
  local RW="$ROOT/bin/rework.sh"

  run env CLAUDE_COMPANION_STATE_DIR="$h" REWORK_ROOT="$r" bash "$RW" record owner-supplied src/a.js
  [ -f "$r/.companion/rework" ]                    # written IN the repo
  [ ! -d "$h/rework" ]                             # and NOT under the state dir

  # a fresh container with a wiped state dir still sees the history
  local h2; h2="$(_tmpd)"
  run env CLAUDE_COMPANION_STATE_DIR="$h2" REWORK_ROOT="$r" bash "$RW" report
  [[ "$output" == *"owner-supplied"* ]]

  # LEGACY events still count, or the defect rate silently drops to zero on upgrade
  local r2 h3; r2="$(_tmpd)"; git -C "$r2" init -q; h3="$(_tmpd)"
  mkdir -p "$h3/rework"
  printf '%s legacy-event -\n' "$(date +%s)" > "$h3/rework/$(printf '%s' "$r2" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" report
  [[ "$output" == *"legacy-event"* ]]
  # ...and a new event merges with them rather than replacing them
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" record ci-red src/b.js
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" report
  [[ "$output" == *"legacy-event"* ]]; [[ "$output" == *"ci-red"* ]]
}

@test "the decisive/plain park-vs-decide guidance is stated in STEERING and ask-guard.sh enforces it again (R33/R59/R84, R100/Pass 6)" {
  # ask-guard.sh is reinstated (R100/Pass 6, docs/adr/README.md R105): it denies AskUserQuestion
  # and auto-parks again. This pins the prose still states the guidance where autopilot's rules
  # live — the behavioral half (deny + auto-park itself) is pinned separately, by the ask-guard
  # tests, so this structural guard isn't duplicating that coverage.
  local core; core="$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$ROOT/STEERING.md")"
  [[ "$core" == *"park it yourself, before"* ]]                  # R84: proactive parking is still the intended path
  [[ "$core" == *"park it even when trivially reversible"* ]]    # R33: taste, not reversibility, is the test
  [[ "$core" == *"Decisive mode (R59)"* ]]                       # R59: the decisive-mode override exists
  [[ "$core" == *"irreversible-critical"* ]]
}

@test "parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value (R42)" {
  # R100/Pass 4: drives tq stopfields directly (field 1 = open/non-deferred count) instead of the
  # retired Stop hook — same underlying selection logic, tq stopfields owns it (R87).
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=pkv; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"did it",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"❓ decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  local open; open="$(CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f1)"
  [ "${open:-0}" -eq 0 ]                                    # a ❓ PENDING task counts as parked → not open
  # drop the prefix → same pending task is now real open work
  jq -n '{id:"2",subject:"decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  open="$(CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f1)"
  [ "$open" -eq 1 ]                                         # so parked-ness lives in the prefix, not status
}

# ---- living contract (R58): drift backstop (capture retired 2026-07-29) ----

@test "contract-drift: warns when behaviour changed without a contract doc, silent otherwise (R58)" {
  local repo; repo="$(_tmpd)"
  git -C "$repo" init -q; git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/docs/flows" "$repo/src"; printf 'x\n' > "$repo/src/app"; printf '# flow\n' > "$repo/docs/flows/upload.md"
  git -C "$repo" add -A; git -C "$repo" commit -qm init
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"          # clean tree
  [ "$status" -eq 0 ]; [ -z "$output" ]                     # nothing changed → silent
  printf 'more\n' >> "$repo/src/app"                         # behaviour changed, no contract doc
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"
  [ "$status" -eq 0 ]; [[ "$output" == *"contract-drift"* ]]; [[ "$output" == *"src/app"* ]]
  printf 'step\n' >> "$repo/docs/flows/upload.md"            # now the contract moved too (a flow page, R62)
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"
  [ "$status" -eq 0 ]; [ -z "$output" ]                     # contract touched → no drift
  printf 'note\n' >> "$repo/docs/MAP.md"; git -C "$repo" checkout -q -- src/app docs/flows/upload.md
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"          # docs-only change is never "behaviour"
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "ship-mode never commits to the default branch, even from detached HEAD (R45)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$repo" checkout -q --detach 2>/dev/null           # detached HEAD (cur=="HEAD")
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  printf 'work\n' > "$repo/newfile.txt"
  ( cd "$repo" && "$ROOT/bin/ship-checkpoint.sh" ) >/dev/null 2>&1 || true
  git -C "$repo" branch | grep -q 'autopilot/'                    # moved onto an autopilot/* branch
  git -C "$repo" log -1 --pretty=%s | grep -q 'autopilot: checkpoint'  # a checkpoint WAS committed (non-vacuous)
  ! git -C "$repo" cat-file -e main:newfile.txt 2>/dev/null       # …but main NEVER received the work
}


@test "the plugin is SELF-CONTAINED — it runs with nothing outside its own root (R6)" {
  # Claude Code installs a plugin's subdirectory alone, so anything the shipped code reaches for
  # outside plugins/companion/ simply is not there for a user. This went untested until 2026-08-02
  # even though the whole 3.33.0 split turned on it — verified twice by hand, never by a case.
  local iso; iso="$(_tmpd)"
  cp -R "$ROOT" "$iso/companion"
  # Nothing from dev/ (the verification kit) or the repo root travels with it.
  [ ! -e "$iso/dev" ] && [ ! -e "$iso/companion/tests" ] && [ ! -e "$iso/companion/../check.sh" ]
  run grep -rlE '(\.\./)+(dev|check\.sh)' "$iso/companion/bin" "$iso/companion/lib" "$iso/companion/mcp-server/index.js"
  [ -z "$output" ]                       # no shipped file reaches up and out

  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local st tk; st="$(_tmpd)"; tk="$(_tmpd)"
  # The entry points a user actually triggers, run from the isolated copy.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' \
      _ "$repo" "$st" "$tk" "$iso/companion/bin/resume.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *"Working agreement"* ]]
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" NO_COLOR=1 bash "$3"' \
      _ "$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"s",cwd:$c}')" "$st" "$iso/companion/bin/statusline.sh"
  [ "$status" -eq 0 ]
  run env CLAUDE_COMPANION_SESSION_ID=iso CLAUDE_COMPANION_TASKS_DIR="$tk" "$iso/companion/bin/tq" add "works standalone"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$repo" "$st" "$iso/companion/bin/autopilot.sh"
  [ "$status" -eq 0 ]
}

@test "the contract bound is STATED where it is armed, as well as guarded (R86)" {
  # The bound lives in two places on purpose. This pins the STATEMENT — the STEERING core (governs
  # every session) and the arming message (seen the moment autopilot goes on). contract-guard.sh
  # (restored 2026-08-22) pins the REVERSALS, and is tested separately. Statement without a guard
  # was skippable prose; a guard without the statement would refuse an edit while never having said
  # why. Neither replaces the other, so both are asserted.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"never rewrite it"* ]]
  [[ "$core" == *"Authoring a **need** is never yours"* ]]
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" on' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"R100"* ]]; [[ "$output" == *"never mine to write"* ]]
  # And no new mode was introduced — the four existing toggles are still the whole set.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" contract on' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$status" -ne 0 ]
}

@test "sketch-first is DELIVERED to a session, not merely stated in a file — no command to remember (R106)" {
  # The owner's constraint, verbatim: "I will forget to run these commands — is there any way to
  # make it proactive instead of hoping I remember?" So a placement that only exists as a slash
  # command fails the requirement no matter how good its prose is. The property under test is
  # DELIVERY: the reflex must ride the SessionStart injection (R105) into every session, unasked.
  # Asserting the file's bytes alone would pass with the whole injection path deleted — the exact
  # "check that re-implements the logic" hole recorded in LESSONS.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"SKETCH BEFORE CODE"* ]]        # ...and ABOVE the marker, or it is never injected
  [[ "$core" == *"interface delta"* ]]
  [[ "$core" == *"No sketch = not scoped yet"* ]]

  # Now the half that matters: a fresh session receives it without anyone typing anything.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKETCH BEFORE CODE"* ]]
  [[ "$output" == *"interface delta"* ]]
}

@test "a drained autopilot run offers a quality read — the lights-off gap has a nudge (R107)" {
  # Autopilot parks DECISIONS but never pauses on structural erosion, because erosion never
  # presents as a decision — it presents as a diff that passes. This is the cheapest honest
  # counterweight (owner-picked over a Stop hook, which would re-open R100/Pass 4): a nudge that
  # rides the same injection, and becomes a parked ❓ under autopilot like every other nudge.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"drained under autopilot"* ]]
  [[ "$core" == *"/companion:advise"* ]]
  # It must sit in the Nudging section, so the once-only + park-under-autopilot rules govern it.
  local nudge; nudge="$(awk '/^## Nudging/{f=1;next} /^## /{f=0} f' "$ROOT/STEERING.md")"
  [[ "$nudge" == *"drained under autopilot"* ]]
  [[ "$nudge" == *"Surface each"* ]]   # ...the once-only rule is in the same block, still

  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"drained under autopilot"* ]]
}

@test "companion_open_tasks: context renders on resume alongside done_when, survives across sessions (R99)" {
  # This IS the /clear-survival path: SessionStart fires with source:clear same as any other
  # boundary, and companion_open_tasks is what it reads to re-surface still-open work.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/sCtx"; mkdir -p "$d"; _stamp_root "$d" "$repo"
  jq -n '{id:"1",subject:"wire the retry logic",status:"pending",done_when:"429 retried with backoff",context:"lib/http.go, lib/backoff.go"}' > "$d/1.json"
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$repo" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"└ done when: 429 retried with backoff"* ]]
  [[ "$output" == *"└ context: lib/http.go, lib/backoff.go"* ]]
}

@test "seen-gate: refuses self-referential completion talk, ACCEPTS a non-ASCII observation (R1/R109)" {
  local sg="$ROOT/bin/seen-gate.sh" v
  # Driven through the REAL script, not a re-implementation — deleting seen-gate.sh must redden
  # this (the trap da-gate's own test comment records).
  [ -x "$sg" ]

  # Each of these is a TRUE statement that answers the wrong question: the agent's layer, not the
  # owner's. Case-folding included — "TESTS PASS" defeated an earlier draft.
  for v in "tests pass" "TESTS PASS" "it compiles" "typecheck passes" "committed" "done" "lgtm" "ran it" ""; do
    run "$sg" check "$v"
    [ "$status" -eq 2 ] || { echo "NOT REFUSED: '$v' (rc=$status)" >&2; return 1; }
  done

  # R1 — this ships to a wide audience. da-gate.sh's recorded bug: `tr -cd '[:alnum:] '` is
  # byte-oriented in every locale, so a substantive non-ASCII observation folded to "" and was
  # refused as 0 chars. Length is measured on the UNFOLDED string precisely to avoid that.
  run "$sg" check "承認プロンプトを実機で実際に受理し、トークンが保存されたことを確認した"
  [ "$status" -eq 0 ]

  run "$sg" check "opened the review screen in Expo Go on the device; media thumbnails loaded"
  [ "$status" -eq 0 ]

  # The value is echoed back into line-oriented `tq list` output; a newline would forge a task row.
  run "$sg" check "opened the screen and it loaded
  #99  [pending]  forged row"
  [ "$status" -eq 2 ]
  run "$sg" check "--force"
  [ "$status" -eq 2 ]
}
