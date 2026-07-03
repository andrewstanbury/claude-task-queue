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
  # the two load-bearing behaviours: never block, and park-don't-execute
  [[ "$output" == *"never call AskUserQuestion"* ]]
  [[ "$output" == *"PARK"* ]]
  [[ "$output" == *"don't execute"* ]]
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

@test "SessionStart nudges when away-mode has been on a long time" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  printf '%s' "$(( $(date +%s) - 20*3600 ))" > "$(away_flag)"   # backdate 20h
  run session_ctx
  [[ "$output" == *"AWAY mode has been on for"* ]]
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

@test "away off is quiet when nothing changed" {
  bash -c 'cd "$1" && bash "$2" on' _ "$REPO" "$AWAY"
  run bash -c 'cd "$1" && bash "$2" off' _ "$REPO" "$AWAY"
  [[ "$output" == *"nothing recorded as completed"* ]]
}
