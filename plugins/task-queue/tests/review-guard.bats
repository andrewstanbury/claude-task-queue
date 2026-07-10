#!/usr/bin/env bats
#
# Tests for the RETURN-REVIEW gate: bin/tq-review-guard.sh + the tq-away.sh wiring.
# When autopilot turns off with a parked ❓ pile, a per-repo marker is armed and the
# PreToolUse guard denies edits until the pile is cleared. Faked via CLAUDE_TQ_*
# overrides + a temp git repo — no model calls.

setup() {
  unset CLAUDE_TQ_AGENT_MODE
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  AWAY="$ROOT/bin/tq-away.sh"
  GUARD="$ROOT/bin/tq-review-guard.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_PROJECTS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  printf 'v1\n' > "$REPO/f.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -qm init
  REPO="$(git -C "$REPO" rev-parse --show-toplevel)"   # canonical root the libs resolve to
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_PROJECTS_DIR" "$CLAUDE_TQ_STATE_DIR" \
         "$CLAUDE_TQ_AWAY_DIR" "$(dirname "$REPO")"
}

# Map a fake session to $REPO so its tasks resolve to this repo.
make_session() {
  local sid="$1" enc; enc="$(printf '%s' "$REPO" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$enc"
  printf '{"cwd":"%s","type":"session"}\n' "$REPO" > "$CLAUDE_TQ_PROJECTS_DIR/$enc/$sid.jsonl"
}
make_task() {
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/$1"
  jq -n --arg id "$2" --arg s "$3" --arg subj "$4" \
    '{id:$id, subject:$subj, status:$s, blocks:[], blockedBy:[]}' \
    > "$CLAUDE_TQ_TASKS_DIR/$1/$2.json"
}
review_flag() { printf '%s/review-%s' "$CLAUDE_TQ_AWAY_DIR" "$(printf '%s' "$REPO" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"; }
at()    { bash -c 'cd "$1" && shift && bash "$@"' _ "$REPO" "$@"; }
guard() { bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | bash "$2"' _ "$REPO" "$GUARD"; }

@test "away off with a parked ❓ arms the review gate" {
  make_session sA; make_task sA 1 pending "❓ [parked] pick a color"
  at "$AWAY" on
  at "$AWAY" off
  [ -f "$(review_flag)" ]
}

@test "away off with no parked pile does NOT arm the gate" {
  make_session sA; make_task sA 1 pending "build the settings page"
  at "$AWAY" on
  at "$AWAY" off
  [ ! -f "$(review_flag)" ]
}

@test "guard denies an edit while a review is pending and a ❓ remains" {
  make_session sA; make_task sA 1 pending "❓ [parked] pick a color"
  : > "$(review_flag)"
  run guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
  [[ "$output" == *"Parked-review pending"* ]]
}

@test "guard self-clears and allows once the parked pile is empty" {
  make_session sA; make_task sA 1 completed "❓ [parked] pick a color"   # resolved
  : > "$(review_flag)"
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]                 # silent allow
  [ ! -f "$(review_flag)" ]        # marker retired
}

@test "an ABANDONED parked pile ages out — the gate self-heals (no permanent repo-wide edit lock)" {
  # Regression: a session that armed the marker on `autopilot off` and then crashed/quit
  # with an unresolved ❓ used to hold the gate FOREVER for every future session in this
  # repo (the ❓ lives in the dead session's folder, unreachable by TaskUpdate). The
  # staleness cutoff must let that abandoned pile age out so editing isn't locked forever.
  make_session sA; make_task sA 1 pending "❓ [parked] pick a color"
  touch -d '90 days ago' "$CLAUDE_TQ_TASKS_DIR/sA/1.json"   # long past the age cutoff
  : > "$(review_flag)"                     # marker armed on the old `autopilot off`
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]                         # ALLOWED, not denied — the lock released
  [ ! -f "$(review_flag)" ]                # and the stale gate self-healed
}

@test "guard is silent when no review is pending" {
  make_session sA; make_task sA 1 pending "❓ [parked] pick a color"   # parked, but no marker
  run guard
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "guard allows when disabled via CLAUDE_TQ_REVIEW_GATE=0" {
  make_session sA; make_task sA 1 pending "❓ [parked] pick a color"
  : > "$(review_flag)"
  run bash -c 'printf "{\"cwd\":\"%s\"}" "$1" | CLAUDE_TQ_REVIEW_GATE=0 bash "$2"' _ "$REPO" "$GUARD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "re-enabling autopilot clears a pending review gate" {
  : > "$(review_flag)"
  at "$AWAY" on
  [ ! -f "$(review_flag)" ]
}
