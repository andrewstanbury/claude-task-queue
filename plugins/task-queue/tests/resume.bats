#!/usr/bin/env bats
#
# Tests for bin/tq-restore.sh — the on-demand "put me back where I was" that backs
# /task-queue:resume. It re-surfaces an earlier session's open tasks on request and
# is honest that it cannot reload the conversation. Faked via CLAUDE_TQ_* overrides
# + a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  RESTORE="$ROOT/bin/tq-restore.sh"

  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"

  REPO="$(mktemp -d)/proj"
  mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  printf 'v1\n' > "$REPO/tracked.txt"
  git -C "$REPO" add -A; git -C "$REPO" commit -qm init
  REPO="$(git -C "$REPO" rev-parse --show-toplevel)"   # canonical root the libs resolve to
}

teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$(dirname "$REPO")"
}

# Register a fake session -> project (cwd) mapping so its tasks map to this repo.
make_session() {
  local sid="$1" cwd="$2" encoded
  encoded="$(printf '%s' "$cwd" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$encoded"
  printf '{"cwd":"%s","type":"session"}\n' "$cwd" \
    > "$CLAUDE_TQ_PROJECTS_DIR/$encoded/$sid.jsonl"
}

make_task() {
  local sid="$1" id="$2" status="$3" subject="$4"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$sid"
  jq -n --arg id "$id" --arg s "$status" --arg subj "$subject" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$sid/$id.json"
}

run_restore() { bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$RESTORE"; }

@test "no carryover: friendly no-op, and the honest conversation note" {
  run run_restore
  [ "$status" -eq 0 ]
  [[ "$output" == *"No open tasks carry over"* ]]
  [[ "$output" == *"claude --resume"* ]]           # never implies it reloaded context
}

@test "surfaces an earlier session's open task for reinstatement" {
  # An open task from an earlier session for THIS repo.
  make_session "sOld" "$REPO"
  make_task "sOld" 1 in_progress "Wire up the resume command"

  run run_restore
  [ "$status" -eq 0 ]
  [[ "$output" == *"Wire up the resume command"* ]]
  [[ "$output" == *"carry over from an earlier session"* ]]
}

# ---- lib/tasks.sh tq_resume_context (characterization) ----------------------
# Pin the awk ranking / age-cutoff / cap+tail logic directly. Characterization only —
# these assert what the code does TODAY, not a desired change. `set +e` mirrors how
# tq-restore.sh actually calls it (best-effort readout).

resume_ctx() { bash -c '. "$1/lib/tasks.sh"; set +e; tq_resume_context "$2" ""' _ "$ROOT" "$REPO"; }
line_of() { printf '%s\n' "$1" | grep -n -- "$2" | head -n1 | cut -d: -f1; }

@test "resume_context: in-progress tasks rank before pending todos" {
  make_session sA "$REPO"
  make_task sA 1 pending     "pending thing"
  make_task sA 2 in_progress "doing thing"
  run resume_ctx
  [ "$status" -eq 0 ]
  # ⏳ in-progress bullet is emitted above the ◻ pending bullet
  [[ "$output" == *"⏳ doing thing"* ]]
  [[ "$output" == *"◻ pending thing"* ]]
  [ "$(line_of "$output" "doing thing")" -lt "$(line_of "$output" "pending thing")" ]
}

@test "resume_context: newer tasks rank before older among todos" {
  make_session sNew "$REPO"
  make_session sOld "$REPO"
  make_task sNew 1 pending "newer task"
  make_task sOld 1 pending "older task"
  touch -d "@$(( $(date +%s) - 5000 ))" "$CLAUDE_TQ_TASKS_DIR/sOld/1.json"
  touch -d "@$(date +%s)"               "$CLAUDE_TQ_TASKS_DIR/sNew/1.json"
  run resume_ctx
  [ "$status" -eq 0 ]
  [ "$(line_of "$output" "newer task")" -lt "$(line_of "$output" "older task")" ]
}

@test "resume_context: CLAUDE_TQ_RESUME_MAX_AGE_DAYS skips a too-old session" {
  make_session sFresh "$REPO"
  make_session sStale "$REPO"
  make_task sFresh 1 pending "fresh work"
  make_task sStale 1 pending "stale work"
  touch -d "@$(( $(date +%s) - 30*86400 ))" "$CLAUDE_TQ_TASKS_DIR/sStale/1.json"
  export CLAUDE_TQ_RESUME_MAX_AGE_DAYS=14
  run resume_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *"fresh work"* ]]
  [[ "$output" != *"stale work"* ]]     # 30d-old session is past the 14d cutoff
}

@test "resume_context: CLAUDE_TQ_RESUME_MAX caps the todo list and emits an '…and N more' tail" {
  make_session sB "$REPO"
  make_task sB 1 pending "todo one"
  make_task sB 2 pending "todo two"
  make_task sB 3 pending "todo three"
  make_task sB 4 pending "todo four"
  make_task sB 5 pending "todo five"
  export CLAUDE_TQ_RESUME_MAX=2
  run resume_ctx
  [ "$status" -eq 0 ]
  [[ "$output" == *"and 3 more todos."* ]]                    # 5 todos, cap 2 → 3 trimmed
  [ "$(printf '%s\n' "$output" | grep -c '◻ ')" -eq 2 ]      # only the cap is shown as bullets
}
