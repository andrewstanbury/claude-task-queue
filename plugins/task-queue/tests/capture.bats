#!/usr/bin/env bats
#
# Tests for the interpret→present→approve hook (bin/tq-capture.sh). On a
# SUBSTANTIVE prompt (multi-step, or consequential/irreversible) it injects the
# review-loop instruction; trivial prompts stay silent. Faked via CLAUDE_TQ_*.

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

@test "multi-step prompt triggers the interpret→present→approve loop" {
  run run_capture "$MULTI"
  [[ "$output" == *"interpret→present→approve"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  [[ "$output" == *"New substantive work"* ]]
  [[ "$output" != *"CONSEQUENTIAL"* ]]      # benign multi-step is not consequential
}

@test "fires regardless of an existing queue — new substantive work is always reviewed" {
  make_task sess 1 pending
  run run_capture "$MULTI"
  [[ "$output" == *"interpret→present→approve"* ]]
}

@test "no alignment clause when the project records no direction" {
  run run_capture "$MULTI"
  [[ "$output" == *"interpret→present→approve"* ]]
  [[ "$output" != *"weigh it against"* ]]   # bare repo → nothing to align to
}

@test "alignment clause names decisions + backlog when the project records them" {
  printf '# Decisions\n- chose X over Y\n' > "$REPO/DECISIONS.md"
  mkdir -p "$REPO/docs"; printf '# ROADMAP\n' > "$REPO/docs/ROADMAP.md"
  run run_capture "$MULTI"
  [[ "$output" == *"weigh it against recorded decisions (DECISIONS.md)"* ]]
  [[ "$output" == *"backlog (docs/ROADMAP.md)"* ]]
  [[ "$output" == *"don't reverse a recorded decision"* ]]
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
  [[ "$output" == *"don't reverse a recorded decision"* ]]
}

@test "routine deletions are not consequential (precision over recall)" {
  # bare delete/remove/drop are deliberately NOT consequential — they'd tax every
  # prompt with the extra scrutiny; native permissions are the destructive backstop.
  run run_capture "remove the unused import and delete the temp file"
  [[ "$output" != *"CONSEQUENTIAL"* ]]
}

@test "silent on a short trivial prompt (runs untouched under auto mode)" {
  run run_capture "fix the typo"
  [ -z "$output" ]
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

@test "multi-step heuristic fires on connectives, lists, and 2+ verbs; not on a single short action" {
  src='. "$1/lib/tasks.sh"; . "$1/lib/capture.sh";'
  run bash -c "$src"' tq_looks_multistep "please add the thing and then remove the other thing" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "1. parse the input 2. validate it across the module" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "implement the parser and add tests for it" && echo Y' bash "$ROOT"
  [ "$output" = "Y" ]
  run bash -c "$src"' tq_looks_multistep "rename the file" || echo N' bash "$ROOT"
  [ "$output" = "N" ]
}

# ---- intent of record (capture side) ----------------------------------------

@test "intent: a substantive prompt records the owner's words for the outcome gate" {
  run run_capture "$MULTI"
  [ -f "$(intent_file)" ]
  [ "$(cat "$(intent_file)")" = "$MULTI" ]
}

@test "intent: a trivial prompt records nothing" {
  run run_capture "fix the typo"
  [ ! -f "$(intent_file)" ]
}

@test "intent: a paused repo records nothing (opted out of the loop)" {
  export CLAUDE_TQ_PAUSE_DIR="$CLAUDE_TQ_STATE_DIR/paused"; mkdir -p "$CLAUDE_TQ_PAUSE_DIR"
  : > "$CLAUDE_TQ_PAUSE_DIR/$(printf '%s' "$REPO" | sed 's:/:-:g')"
  run run_capture "$MULTI"
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
           "center the modal and make it look modern" "change the layout of the pricing cards"; do
    run bash -c "$src"' tq_looks_design "$2" && echo Y' bash "$ROOT" "$p"
    [ "$output" = "Y" ]
  done
  # architecture/API "design" + functional edits must NOT fire (precision)
  for p in "design the database schema" "design the public API surface" "add a logout button" \
           "fix the slow report page" "move the auth module to a new package" \
           "format the JSON output" "update the user table"; do
    run bash -c "$src"' tq_looks_design "$2" || echo N' bash "$ROOT" "$p"
    [ "$output" = "N" ]
  done
}

@test "design change triggers the ASCII-preview present loop, even when short" {
  run run_capture "make the login page look cleaner"   # 6 words: not multi-step, still fires
  [[ "$output" == *"Design change"* ]]
  [[ "$output" == *"ASCII mockup"* ]]
  [[ "$output" == *"AskUserQuestion"* ]]
  [[ "$output" == *"(Recommended)"* ]]
  [[ "$output" == *"arrow keys"* ]]
  [[ "$output" == *"Enter"* ]]
}

@test "design change is substantive → its intent is recorded for the outcome gate" {
  run run_capture "redesign the dashboard layout"
  [ -f "$(intent_file)" ]
}

@test "a consequential design change keeps CONSEQUENTIAL scrutiny + a design-preview note" {
  run run_capture "redesign and migrate the checkout to the paid stripe widget"
  [[ "$output" == *"CONSEQUENTIAL"* ]]
  [[ "$output" == *"ASCII mockups"* ]]            # design note appended to the consequential path
}

@test "a plain non-visual substantive prompt still uses the generic loop (no ASCII)" {
  run run_capture "$MULTI"
  [[ "$output" == *"New substantive work"* ]]
  [[ "$output" != *"ASCII"* ]]
}
