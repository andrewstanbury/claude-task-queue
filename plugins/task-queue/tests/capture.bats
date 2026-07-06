#!/usr/bin/env bats
#
# Tests for the interpret→decompose→queue hook (bin/tq-capture.sh). It injects a loop
# instruction on EVERY prompt (owner decision 2026-06-26 — all prompts route through
# the queue), but SPLIT from the interrupt (2026-06-27): the DEFAULT path is a LEAN
# re-anchor (interpret + queue + run-in-auto, sign-off delegated to the model) while
# the deterministic high-stakes signal — consequential/design — gets the HEAVY
# present-and-approve + critique variant. The full procedure it re-anchors to rides
# the SessionStart policy. Only slash/bang/empty and solo-mode repos stay silent.
# Faked via CLAUDE_TQ_*.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  CAPTURE="$ROOT/bin/tq-capture.sh"
  VERIFY="$ROOT/bin/tq-verify.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"          # isolate intent-of-record writes
  # Isolated repo for cwd so the alignment clause keys off fixture docs, not this
  # repo's own ROADMAP/decisions. Tests that want the clause drop docs into REPO.
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  unset CLAUDE_TQ_CAPTURE_DISABLED
  MULTI="Add the login form and then wire the auth endpoint and update the tests"
}

teardown() { rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$(dirname "$REPO")"; }

intent_file() { printf '%s/intent-%s' "$CLAUDE_TQ_STATE_DIR" "${1:-sess}"; }
# Feed the Stop hook a payload; echo its stdout.
run_verify() {
  local sid="${1:-sess}" json
  json="$(jq -nc --arg s "$sid" --arg c "$REPO" '{session_id:$s, cwd:$c, hook_event_name:"Stop"}')"
  printf '%s' "$json" | "$VERIFY"
}

make_task() {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" '{id:$id, subject:"x", status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$1/$2.json"
}

run_capture() {
  local prompt="$1" sid="${2:-sess}" json
  json="$(jq -nc --arg p "$prompt" --arg s "$sid" --arg c "$REPO" '{prompt:$p, session_id:$s, cwd:$c}')"
  printf '%s' "$json" | "$CAPTURE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "multi-step prompt gets the LEAN re-anchor (default path, no heavy procedure)" {
  run run_capture "$MULTI"
  [[ "$output" == *"interpret it"* ]]              # interpret + decompose + queue…
  [[ "$output" == *"IN AUTO"* ]]                   # …and run in auto (no forced round-trip)
  [[ "$output" == *"AskUserQuestion sign-off ONLY on real signal"* ]]
  [[ "$output" != *"interpret→present→approve"* ]] # heavy procedure stays on the SessionStart policy
  [[ "$output" != *"steelman"* ]]                  # critique preamble does NOT ride the default path
  [[ "$output" != *"CONSEQUENTIAL"* ]]             # benign multi-step is not consequential
}

@test "default path delegates the interrupt decision but keeps the selective cue" {
  run run_capture "$MULTI"
  [[ "$output" == *"high blast-radius"* ]]         # model-judged escalation criteria…
  [[ "$output" == *"recommend against it"* ]]      # …incl. pushing back on the ask
  [[ "$output" == *"Be selective"* ]]              # anti-theater survives in lean form
  [[ "$output" == *"don't manufacture pushback"* ]]
}

@test "documented repo: default path collapses to the terse CLAUDE.md pointer" {
  printf 'guide <!-- claude-companion -->\n' > "$REPO/CLAUDE.md"   # policy lives in the manual
  run run_capture "$MULTI"
  [[ "$output" == *"Per CLAUDE.md policy"* ]]              # terse pointer…
  [[ "$output" == *"work in auto"* ]]                      # …still cues the queue loop
  [[ "$output" != *"interpret it (one plain line)"* ]]     # full re-anchor suppressed
  [[ "$output" != *"First weigh it against"* ]]            # no alignment clause on the lean path
}

@test "documented repo: a CONSEQUENTIAL prompt still gets the heavy procedure (not leaned)" {
  printf 'guide <!-- claude-companion -->\n' > "$REPO/CLAUDE.md"
  run run_capture "drop the users table"
  [[ "$output" == *"CONSEQUENTIAL"* ]]                     # documentation does NOT lean the high-stakes path
  [[ "$output" == *"interpret→present→approve"* ]]
}

@test "trivial prompt stays lean too — no critique preamble (split-from-interrupt)" {
  run run_capture "fix the typo"
  [[ "$output" == *"IN AUTO"* ]]                   # lean re-anchor fires…
  [[ "$output" != *"steelman"* ]]                  # …but the heavy critique does NOT (2026-06-27)
  [[ "$output" != *"interpret→present→approve"* ]]
}

@test "consequential prompt also carries the critique posture" {
  run run_capture "delete the user accounts table"
  [[ "$output" == *"steelman"* ]]
  [[ "$output" == *"CONSEQUENTIAL"* ]]
}

@test "fires regardless of an existing queue — new work is always interpreted" {
  make_task sess 1 pending
  run run_capture "$MULTI"
  [[ "$output" == *"interpret it"* ]]
}

@test "no alignment clause when the project records no direction" {
  run run_capture "$MULTI"
  [[ "$output" == *"interpret it"* ]]
  [[ "$output" != *"weigh it against"* ]]   # bare repo → nothing to align to
}

@test "alignment clause names decisions + backlog when the project records them" {
  printf '# Decisions\n- chose X over Y\n' > "$REPO/DECISIONS.md"
  mkdir -p "$REPO/docs"; printf '# ROADMAP\n' > "$REPO/docs/ROADMAP.md"
  run run_capture "$MULTI"
  [[ "$output" == *"weigh it against recorded decisions (DECISIONS.md)"* ]]
  [[ "$output" == *"backlog (docs/ROADMAP.md)"* ]]
  [[ "$output" == *"neither the old nor the new wins silently"* ]]
}

@test "alignment clause covers ADR dirs and a backlog-only project" {
  mkdir -p "$REPO/docs/adr"; : > "$REPO/docs/adr/0001-x.md"
  run run_capture "$MULTI"
  [[ "$output" == *"recorded decisions (docs/adr/)"* ]]
  # backlog-only (decisions absent): the clause still fires, naming just the backlog
  rm -r "$REPO/docs/adr"; printf '# BACKLOG\n' > "$REPO/BACKLOG.md"
  run run_capture "$MULTI"
  [[ "$output" == *"weigh it against the backlog (BACKLOG.md)"* ]]
  [[ "$output" != *"recorded decisions"* ]]
}

@test "consequential prompt gets the loop with extra CONSEQUENTIAL scrutiny" {
  run run_capture "delete the user accounts table"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
  [[ "$output" == *"interpret→present→approve"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  # a conflicting option must name the recorded requirement it would retire
  [[ "$output" == *"recorded requirement it would retire"* ]]
}

@test "consequential fires even on a short single-step prompt" {
  run run_capture "rm -rf build"          # too short for the multi-step path, still consequential
  [[ "$output" == *"CONSEQUENTIAL"* ]]
}

@test "consequential fires on migrations, paid deps, and destructive history ops" {
  run run_capture "run the database migration for the new schema"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
  run run_capture "subscribe to the paid plan for the email service"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
  run run_capture "force push the rebased branch to origin main"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
}

@test "consequential prompt appends the alignment clause" {
  printf '# Decisions\n' > "$REPO/DECISIONS.md"
  mkdir -p "$REPO/docs"; printf '# ROADMAP\n' > "$REPO/docs/ROADMAP.md"
  run run_capture "run the data migration for the legacy auth records"
  [[ "$output" == *"weigh it against recorded decisions (DECISIONS.md)"* ]]
  [[ "$output" == *"neither the old nor the new wins silently"* ]]
}

@test "routine deletions are not consequential (precision over recall)" {
  # bare delete/remove/drop are deliberately NOT consequential — they'd tax every
  # prompt with the extra scrutiny; native permissions are the destructive backstop.
  run run_capture "remove the unused import and delete the temp file"
  [[ "$output" != *"CONSEQUENTIAL"* ]]
}

@test "a short trivial prompt still fires the lean re-anchor (all prompts route through the queue)" {
  run run_capture "fix the typo"
  [[ "$output" == *"interpret it"* ]]
  [[ "$output" == *"IN AUTO"* ]]
  [[ "$output" != *"interpret→present→approve"* ]]   # but lean, not the heavy procedure
}

@test "silent on a slash command even if long and multi-versed" {
  run run_capture "/refactor add build and update everything and then test it"
  [ -z "$output" ]
}

@test "silent on a bang command" {
  run run_capture "!rm -rf build and then redeploy to production"
  [ -z "$output" ]
}

@test "can be disabled with CLAUDE_TQ_CAPTURE_DISABLED" {
  export CLAUDE_TQ_CAPTURE_DISABLED=1
  run run_capture "Add X and then build Y and update Z and refactor W"
  [ -z "$output" ]
}

@test "skips slash commands even when consequential" {
  run run_capture "/db drop the table and migrate the schema"
  [ -z "$output" ]
}

@test "consequential heuristic: fires only on high-signal forms, silent on routine work" {
  src='. "$1/lib/tasks.sh"; . "$1/lib/capture.sh";'
  # high-signal: destructive shell/VCS, DB-targeted drop/delete/truncate, SQL DML,
  # migrations, paid deps, deploy-to-prod.
  for p in "drop the production database" "delete the users table" \
           "truncate the events table" "delete from sessions where expired" \
           "run a data migration" "add the paid subscription" \
           "rm -rf node_modules" "git reset --hard origin/main" \
           "force push the rebased branch" "deploy the new build to production"; do
    run bash -c "$src"' tq_looks_consequential "$2" && echo Y' bash "$ROOT" "$p"
    [ "$output" = "Y" ]
  done
  # routine work that bare-verb matching would WRONGLY flag — must stay silent.
  for p in "delete the temp file" "remove the old auth module" \
           "drop the feature flag" "add a dropdown menu to the navbar" \
           "reproduce the bug that only happens in production" \
           "update the product page copy" "implement the login form and add tests"; do
    run bash -c "$src"' tq_looks_consequential "$2" || echo N' bash "$ROOT" "$p"
    [ "$output" = "N" ]
  done
}

# ---- intent of record (capture side) ----------------------------------------

@test "intent: a substantive prompt records the owner's words for the outcome gate" {
  run run_capture "$MULTI"
  [ -f "$(intent_file)" ]
  [ "$(cat "$(intent_file)")" = "$MULTI" ]
}

@test "intent: even a trivial prompt now records the owner's words (all-prompts policy)" {
  run run_capture "fix the typo"
  [ -f "$(intent_file)" ]
  [ "$(cat "$(intent_file)")" = "fix the typo" ]
}

@test "intent: solo + owner present (fresh prompt) records; lights-out (window=0) does not" {
  export CLAUDE_TQ_AWAY_DIR="$CLAUDE_TQ_STATE_DIR/away"; mkdir -p "$CLAUDE_TQ_AWAY_DIR"
  : > "$CLAUDE_TQ_AWAY_DIR/$(printf '%s' "$REPO" | sed 's:/:-:g')"
  # a prompt is proof the owner is at the keyboard → the interactive loop records intent
  run run_capture "$MULTI"
  [ -f "$(intent_file)" ]
  rm -f "$(intent_file)"
  # lights-out autopilot: even the owner's own prompt stays autonomous → nothing recorded
  CLAUDE_TQ_PRESENT_WINDOW=0 run run_capture "$MULTI"
  [ ! -f "$(intent_file)" ]
}

@test "intent: capture is disabled via CLAUDE_TQ_INTENT_GATE=0" {
  CLAUDE_TQ_INTENT_GATE=0 run run_capture "$MULTI"
  [ ! -f "$(intent_file)" ]
}

# ---- intent→outcome gate (tq-verify, Stop) ----------------------------------

@test "intent gate: blocks on a dirty tree, replaying the ask and the change" {
  printf '%s' "$MULTI" > "$(intent_file)"
  printf 'form\n' > "$REPO/login.js"                 # a change landed (untracked → dirty)
  run run_verify
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"owner asked"* ]]
  [[ "$output" == *"login form"* ]]                  # replays their words
  [[ "$output" == *"login.js"* ]]                    # shows what changed
  [ ! -f "$(intent_file)" ]                          # consumed → fires once
}

@test "intent gate: silent on a clean tree, intent kept for a later stop" {
  printf '%s' "$MULTI" > "$(intent_file)"
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  run run_verify
  [ -z "$output" ]
  [ -f "$(intent_file)" ]                            # not consumed
}

@test "intent gate: silent when there is no captured intent" {
  printf 'x\n' > "$REPO/x.txt"                       # dirty, but nothing was captured
  run run_verify
  [ -z "$output" ]
}

@test "intent gate: fires once — a second dirty stop allows (no loop)" {
  printf '%s' "$MULTI" > "$(intent_file)"
  printf 'form\n' > "$REPO/login.js"
  run run_verify; [[ "$output" == *block* ]]
  run run_verify; [ -z "$output" ]                   # intent consumed → silent
}

@test "intent gate: disabled via CLAUDE_TQ_INTENT_GATE=0" {
  printf '%s' "$MULTI" > "$(intent_file)"
  printf 'form\n' > "$REPO/login.js"
  CLAUDE_TQ_INTENT_GATE=0 run run_verify
  [ -z "$output" ]
}

# ---- design-change preview (ASCII mockups via AskUserQuestion) ---------------

@test "design heuristic: fires on visual/UI changes, silent on architecture/functional" {
  src='. "$1/lib/tasks.sh"; . "$1/lib/capture.sh";'
  for p in "redesign the login page" "make the dashboard cleaner" "move the sidebar to the right" \
           "restyle the navbar" "lay out the settings screen" "show me a wireframe for the hero" \
           "center the modal and make it look modern" "change the layout of the pricing cards" \
           "redesign the homepage" "redesign the client homepage" "reskin the app" \
           "prettify the profile page" "update the colour palette" "redesign the settings page" \
           "make the onboarding feel cleaner"; do
    run bash -c "$src"' tq_looks_design "$2" && echo Y' bash "$ROOT" "$p"
    [ "$output" = "Y" ]
  done
  # architecture/API "design" + functional edits must NOT fire (precision) — the
  # noun gate must hold even for the strong verb "redesign".
  for p in "design the database schema" "design the public API surface" "add a logout button" \
           "fix the slow report page" "move the auth module to a new package" \
           "redesign the API" "redesign how we handle error retries" \
           "format the JSON output" "update the user table"; do
    run bash -c "$src"' tq_looks_design "$2" || echo N' bash "$ROOT" "$p"
    [ "$output" = "N" ]
  done
}

@test "design change triggers the wireframe-preview present loop, even when short" {
  run run_capture "make the login page look cleaner"   # 6 words: not multi-step, still fires
  [[ "$output" == *"Design change"* ]]
  [[ "$output" == *"WIREFRAME mockup"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  [[ "$output" == *"(Recommended)"* ]]
  [[ "$output" == *"arrow keys"* ]]
  [[ "$output" == *"Enter"* ]]
  # the chosen wireframe convention is specified (weight via shading/fill/border)
  [[ "$output" == *"▒"* ]]
  [[ "$output" == *"█"* ]]
  [[ "$output" == *"heavy box border"* ]]
}

@test "design change is substantive → its intent is recorded for the outcome gate" {
  run run_capture "redesign the dashboard layout"
  [ -f "$(intent_file)" ]
}

@test "a consequential design change keeps CONSEQUENTIAL scrutiny + a design-preview note" {
  run run_capture "redesign and migrate the checkout to the paid stripe widget"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
  [[ "$output" == *"WIREFRAME mockups"* ]]        # design note appended to the consequential path
}

@test "a plain non-visual substantive prompt still uses the generic lean loop (no wireframe)" {
  run run_capture "$MULTI"
  [[ "$output" == *"interpret it"* ]]
  [[ "$output" != *"WIREFRAME"* ]]
}

@test "Godot project: the wireframe design-preview fires (suppression removed at owner's request)" {
  : > "$REPO/project.godot"                        # mark the repo as a Godot project
  run run_capture "make the main menu look cleaner" # a visual change
  [[ "$output" == *"Design change"* ]]             # routed to the design loop, same as a web project
  [[ "$output" == *"WIREFRAME mockup"* ]]          # wireframe demonstrate-before-build
}

@test "Godot project: a multi-step visual prompt routes to the design preview (design wins over multi-step)" {
  : > "$REPO/project.godot"
  run run_capture "redesign the HUD and then wire the pause menu and update the tests"
  [[ "$output" == *"Design change"* ]]
  [[ "$output" == *"WIREFRAME"* ]]
}

@test "design preview still fires on a non-Godot project (no project.godot)" {
  run run_capture "make the main menu look cleaner" # same prompt, but REPO has no project.godot
  [[ "$output" == *"Design change"* ]]
  [[ "$output" == *"WIREFRAME mockup"* ]]
}

# ---- open-questions reminder (don't let answers get buried) ------------------

make_question() {   # $1=session $2=id $3=subject
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" '{id:$id, subject:$s, status:"pending", blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$1/$2.json"
}

@test "open questions: a lingering ❓ is re-surfaced (rides alongside the loop)" {
  make_question sess q1 "❓ Should the gate block or warn?"
  run run_capture "fix the typo"
  [[ "$output" == *"unanswered question"* ]]
  [[ "$output" == *"block or warn"* ]]
}

@test "open questions: the reminder rides ALONGSIDE the review loop on substantive work" {
  make_question sess q1 "❓ Which design did you want?"
  run run_capture "$MULTI"
  [[ "$output" == *"unanswered question"* ]]
  [[ "$output" == *"interpret it"* ]]            # lean loop instruction still present
}

@test "open questions: no reminder when there are none (loop still fires)" {
  run run_capture "fix the typo"
  [[ "$output" != *"unanswered question"* ]]      # loop fires, but no open-Q reminder
}

@test "open questions: a completed ❓ does not count" {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/sess"
  jq -n '{id:"q",subject:"❓ already answered",status:"completed",blocks:[],blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/sess/q.json"
  run run_capture "fix the typo"
  [[ "$output" != *"unanswered question"* ]]
}

@test "open questions: disabled via CLAUDE_TQ_OPEN_Q=0" {
  make_question sess q1 "❓ x"
  CLAUDE_TQ_OPEN_Q=0 run run_capture "fix the typo"
  [[ "$output" != *"unanswered question"* ]]      # reminder suppressed (loop may still fire)
}

@test "open questions: a large pile is CAPPED (first few + overflow count), not listed in full" {
  local i; for i in 1 2 3 4 5 6; do make_question sess "q$i" "❓ question number $i"; done
  run run_capture "fix the typo"
  [[ "$output" == *"6 unanswered question"* ]]          # header still counts them all
  [[ "$output" == *"…and 2 more"* ]]                    # only the first 4 are listed
  [ "$(printf '%s\n' "$output" | grep -c '  • ')" -eq 4 ]
}
