#!/usr/bin/env bats
#
# Tests for away-mode: bin/tq-away.sh (the per-repo toggle) and the SessionStart
# AWAY block it drives. Away-mode = owner stepped away → run autonomous, never
# block, PARK anything needing the owner as a ❓ task. Everything faked via
# CLAUDE_TQ_* overrides and a temp git repo — no model calls.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  AWAY="$ROOT/bin/tq-away.sh"
  RESUME="$ROOT/bin/tq-resume.sh"
  VERIFY="$ROOT/bin/tq-verify.sh"
  GUARD="$ROOT/bin/tq-ask-guard.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"

  REPO="$(mktemp -d)/proj"
  mkdir -p "$REPO" && git -C "$REPO" init -q
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_AWAY_DIR" "$(dirname "$REPO")"
}

session_ctx() {
  local json; json="$(jq -nc --arg c "$REPO" '{session_id:"s2", cwd:$c, source:"startup"}')"
  printf '%s' "$json" | "$RESUME" | jq -r '.hookSpecificOutput.additionalContext'
}

# The away flag file for $REPO (its repo-root maps to itself since it's a git repo).
away_flag() { printf '%s/%s' "$CLAUDE_TQ_AWAY_DIR" "$(printf '%s' "$REPO" | sed 's:/:-:g')"; }

# Register a fake session -> $REPO mapping so the digest can resolve tasks to this repo.
make_session() {
  local sid="$1" encoded; encoded="$(printf '%s' "$REPO" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$encoded"
  printf '{"cwd":"%s","type":"session"}\n' "$REPO" > "$CLAUDE_TQ_PROJECTS_DIR/$encoded/$sid.jsonl"
}
make_task() {
  local sid="$1" id="$2" status="$3" subject="$4"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" --arg subj "$subject" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

# ---- tq-away.sh -------------------------------------------------------------

@test "tq-away.sh reports off by default, on after on, off after off" {
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$AWAY"
  [[ "$output" == off* ]]

  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$AWAY"
  [[ "$output" == on* ]]

  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$AWAY"
  [[ "$output" == off* ]]
}

@test "tq-away.sh rejects an unknown action" {
  run bash -c 'cd "$1" && bash "$2" wat' _ "$REPO" "$AWAY"
  [ "$status" -eq 2 ]
}

@test "away flag is scoped to the repo root (subdir resolves to the same flag)" {
  mkdir -p "$REPO/a/b"
  bash -c 'cd "$1/a/b" && bash "$2" on' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" status' _ "$REPO" "$AWAY"
  [[ "$output" == on* ]]
}

# ---- SessionStart surfacing -------------------------------------------------

@test "SessionStart is silent about AWAY when the repo is not away (control)" {
  run session_ctx
  [[ "$output" != *"AWAY mode is ON"* ]]
}

@test "SessionStart surfaces the AWAY block when the repo is away" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run session_ctx
  [[ "$output" == *"AWAY mode is ON"* ]]
  # the load-bearing behaviours: never block; park the important, decide the routine
  [[ "$output" == *"never call AskUserQuestion"* ]]
  [[ "$output" == *"PARK"* ]]
  [[ "$output" == *"decide the routine"* ]]
  # parked items land in the existing ❓ open-questions bucket (reused, not new)
  [[ "$output" == *"❓ [parked]"* ]]
}

@test "turning away off drops the AWAY block again" {
  bash -c 'cd "$1" && bash "$2" on'  _ "$REPO" "$AWAY"
  bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  run session_ctx
  [[ "$output" != *"AWAY mode is ON"* ]]
}

# ---- on-time stamp + staleness nudge ---------------------------------------

@test "turning away on stamps an epoch into the flag file" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run cat "$(away_flag)"
  [[ "$output" =~ ^[0-9]+$ ]]      # a plain epoch
  [ "$output" -gt 0 ]
}

@test "SessionStart nudges when solo mode has been on a long time" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  printf '%s' "$(( $(date +%s) - 20*3600 ))" > "$(away_flag)"   # backdate 20h
  run session_ctx
  [[ "$output" == *"SOLO mode has been on for"* ]]
}

@test "SessionStart does not nudge for a fresh away-mode toggle" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run session_ctx
  [[ "$output" == *"AWAY mode is ON"* ]]
  [[ "$output" != *"has been on for"* ]]
}

# ---- return-digest on off --------------------------------------------------

@test "away off prints a digest of completed + parked work" {
  make_session "sess1"
  make_task "sess1" 1 completed   "Wire the payment engine"
  make_task "sess1" 2 in_progress "❓ [parked] Confirm Postgres over MySQL?"
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  printf '%s' "$(( $(date +%s) - 3600 ))" > "$(away_flag)"   # away since 1h ago
  run bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  [[ "$output" == *"While you were away"* ]]
  [[ "$output" == *"1 task(s) completed"* ]]
  [[ "$output" == *"1 ❓ parked"* ]]
  [[ "$output" == *"✓ Wire the payment engine"* ]]
}

@test "away off lists every parked decision in full and gates the queue behind them" {
  make_session "sess1"
  make_task "sess1" 1 in_progress "❓ [parked] Confirm Postgres over MySQL?"
  make_task "sess1" 2 pending     "❓ [parked] Pick the auth library"
  make_task "sess1" 3 pending     "❓ [parked] Approve the new webhooks dependency"
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  [[ "$output" == *"3 ❓ parked"* ]]
  # the FULL list is printed (not a first-N cap) so "off" is the review point
  [[ "$output" == *"Confirm Postgres over MySQL?"* ]]
  [[ "$output" == *"Pick the auth library"* ]]
  [[ "$output" == *"Approve the new webhooks dependency"* ]]
  # soft-block: resolve parked items BEFORE pulling new queue work
  [[ "$output" == *"BEFORE pulling any new queue work"* ]]
  # design-preview posture: each parked decision is a pick-from-options review
  [[ "$output" == *"AskUserQuestion"* ]]
  [[ "$output" == *"2-3 concrete options"* ]]
}

@test "away off is quiet when nothing changed" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  [[ "$output" == *"nothing recorded as completed"* ]]
}

# ---- away auto-continue: the Stop hook drains the queue (Rec A) --------------

# Run tq-verify (the Stop hook) for a session rooted at $REPO.
run_verify() {
  local sid="$1" j
  j="$(jq -nc --arg c "$REPO" --arg s "$sid" '{cwd:$c, session_id:$s}')"
  printf '%s' "$j" | "$VERIFY"
}
continue_file() { printf '%s/away-continue-%s' "$CLAUDE_TQ_STATE_DIR" "$1"; }

@test "away OFF: a Stop is allowed even with open queue work (no auto-continue)" {
  make_task sV 1 pending "wire the login form"
  run run_verify sV
  [ "$status" -eq 0 ]
  [[ "$output" != *"Away-mode"* ]]           # no block reason emitted
}

@test "away ON + open non-❓ work: the Stop is BLOCKED to keep draining the queue" {
  date +%s > "$(away_flag)"
  make_task sV 1 pending "wire the login form"
  run run_verify sV
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"Away-mode"* ]]
  [[ "$output" == *"still open in the queue"* ]]
  [[ "$output" == *"wire the login form"* ]]  # names the next task
}

@test "away ON auto-continue increments a per-prompt safety counter" {
  date +%s > "$(away_flag)"
  make_task sV 1 pending "do the thing"
  run_verify sV >/dev/null
  [ "$(cat "$(continue_file sV)")" = "1" ]
  run_verify sV >/dev/null
  [ "$(cat "$(continue_file sV)")" = "2" ]
}

@test "away ON but counter at the cap: YIELDS (allows the stop, no runaway loop)" {
  date +%s > "$(away_flag)"
  make_task sV 1 pending "do the thing"
  printf '40' > "$(continue_file sV)"          # default CLAUDE_TQ_AWAY_MAX_CONTINUE
  run run_verify sV
  [ "$status" -eq 0 ]
  [[ "$output" != *"Away-mode"* ]]             # yielded, not blocked
}

@test "away ON but only ❓ parked items left: the queue is drained → Stop allowed" {
  date +%s > "$(away_flag)"
  make_task sV 1 in_progress "❓ [parked] pick a color"
  run run_verify sV
  [ "$status" -eq 0 ]
  [[ "$output" != *"Away-mode"* ]]
}

@test "CLAUDE_TQ_AWAY_CONTINUE=0 disables auto-continue even when away" {
  date +%s > "$(away_flag)"
  make_task sV 1 pending "do the thing"
  run env CLAUDE_TQ_AWAY_CONTINUE=0 bash -c \
    'printf "%s" "$(jq -nc --arg c "$1" --arg s sV "{cwd:\$c,session_id:\$s}")" | "$2"' _ "$REPO" "$VERIFY"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Away-mode"* ]]
}

# ---- ask-guard: AskUserQuestion is hard-blocked while away (Rec B) -----------

run_guard() {
  local j; j="$(jq -nc --arg c "$REPO" '{cwd:$c, tool_name:"AskUserQuestion"}')"
  printf '%s' "$j" | "$GUARD"
}

@test "away ON: AskUserQuestion is DENIED (owner can't answer)" {
  date +%s > "$(away_flag)"
  run run_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
  [[ "$output" == *"Away-mode"* ]]
  [[ "$output" == *"❓ [parked]"* ]]           # tells the model to park instead
}

@test "away OFF: AskUserQuestion is allowed (guard is silent)" {
  run run_guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "CLAUDE_TQ_AWAY_ASK_GUARD=0 lets the question through even when away" {
  date +%s > "$(away_flag)"
  run env CLAUDE_TQ_AWAY_ASK_GUARD=0 bash -c \
    'printf "%s" "$(jq -nc --arg c "$1" "{cwd:\$c,tool_name:\"AskUserQuestion\"}")" | "$2"' _ "$REPO" "$GUARD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ---- solo folds pause: away suppresses the capture approval-loop (Rec 3) -----

run_capture() {
  local j; j="$(jq -nc --arg p "$1" --arg c "$REPO" --arg s sC '{prompt:$p, cwd:$c, session_id:$s}')"
  printf '%s' "$j" | "$ROOT/bin/tq-capture.sh"
}

@test "away OFF: a substantive prompt gets the interpret→queue re-anchor (control)" {
  run run_capture "add a login form and wire it and test it"
  [[ "$output" == *"New work"* ]]
}

@test "away ON: the approval-loop injection is suppressed (folded pause)" {
  date +%s > "$(away_flag)"
  run run_capture "add a login form and wire it and test it"
  [ "$status" -eq 0 ]
  [[ "$output" != *"New work — interpret it"* ]]
}
