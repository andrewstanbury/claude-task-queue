#!/usr/bin/env bats
#
# The status line (the glance surface): the animated beacon, the 🛡 secret-gate indicator, the
# ◻/❓/⏳ task split, and git branch + ahead/behind. Read-only; renders from the JSON Claude Code
# pipes on stdin plus the companion's own state.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"; TOUCH="$ROOT/bin/touch.sh"
  AP="$ROOT/bin/autopilot.sh"; ASK="$ROOT/bin/ask-guard.sh"; STOP="$ROOT/bin/stop-autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

@test "status line: renders 🛡 · model · tokens · task count · project · branch" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sBar"
  jq -n '{id:"1",subject:"a",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sBar/1.json"
  jq -n '{id:"2",subject:"b",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sBar/2.json"
  jq -n '{id:"3",subject:"c",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/sBar/3.json"
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"claude-opus-4-8"},session_id:"sBar",cwd:$c,context_window:{total_input_tokens:45200,total_output_tokens:1300}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"●"* ]]             # health beacon (static ● with color off)
  [[ "$output" == *"🛡"* ]]            # secret gate on
  [[ "$output" == *" 🛡 "* ]]          # shield has breathing room (│ 🛡 │), not jammed
  [[ "$output" == *"opus-4-8"* ]]      # model, claude- prefix + date stripped
  [[ "$output" == *"⇡45.2k"* ]]        # up tokens
  [[ "$output" == *"⇣1.3k"* ]]         # down tokens
  [[ "$output" == *"📋 2"* ]]            # 2 open (completed excluded)
  [[ "$output" == *"⎇"* ]]             # branch
}

@test "status line: task split (◻ open · ❓ parked · ⏳ blocked) and git ahead/behind" {
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sSplit"
  jq -n '{id:"1",subject:"do it",status:"in_progress"}'          > "$CLAUDE_COMPANION_TASKS_DIR/sSplit/1.json"
  jq -n '{id:"2",subject:"and this",status:"pending"}'           > "$CLAUDE_COMPANION_TASKS_DIR/sSplit/2.json"
  jq -n '{id:"3",subject:"❓ [parked] pick a backend",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sSplit/3.json"
  jq -n '{id:"4",subject:"⏳ [blocked] owner deploys",status:"pending"}'  > "$CLAUDE_COMPANION_TASKS_DIR/sSplit/4.json"
  jq -n '{id:"5",subject:"shipped",status:"completed"}'          > "$CLAUDE_COMPANION_TASKS_DIR/sSplit/5.json"
  # a repo one commit ahead of its upstream
  local repo up; repo="$(mktemp -d)"; up="$(mktemp -d)"
  git -C "$repo" init -q; git -C "$up" init -q --bare
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  git -C "$repo" remote add origin "$up"; git -C "$repo" push -q -u origin HEAD 2>/dev/null
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m ahead
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sSplit",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"📋 2"* ]]            # 2 plain-open (parked/blocked excluded)
  [[ "$output" == *"❓ 1"* ]]            # 1 parked
  [[ "$output" == *"⏳ 1"* ]]            # 1 blocked
  [[ "$output" == *"↑1"* ]]            # 1 commit ahead of upstream
  [[ "$output" != *"↓"* ]]             # not behind
}

@test "status line: 🛡✗ when the secret gate is disabled" {
  run bash -c 'printf "{}" | CLAUDE_COMPANION_SECSCAN=0 NO_COLOR=1 "$1"' _ "$SL"
  [[ "$output" == *"🛡✗"* ]]
}

@test "status line: a space in the model name / project path doesn't corrupt the parse (R32·1)" {
  # spaced project path (routine on macOS) + spaced model name — both would mis-split under
  # default IFS, breaking the session-id (→ task counts 0) and the cwd (→ branch/project).
  local base repo; base="$(mktemp -d)"; repo="$base/My Project"; mkdir -p "$repo"
  git -C "$repo" init -q; git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sSpace"
  jq -n '{id:"1",subject:"a",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sSpace/1.json"
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus 4.8"},session_id:"sSpace",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"📋 1"* ]]             # session id parsed whole → store found → 1 open task
  [[ "$output" == *"Opus 4.8"* ]]       # model name kept whole
  [[ "$output" == *"⎇"* ]]              # cwd parsed whole → git branch resolves
}

@test "status line: beacon animates only on activity (static ● when idle, spins on in-progress)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  # idle: a pending task, no autopilot, nothing in-progress → static ● even with color on
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sIdle"
  jq -n '{id:"1",subject:"later",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sIdle/1.json"
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sIdle",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm "$2"' _ "$p" "$SL"
  [[ "$output" == *"●"* ]]              # idle → static dot
  # active: a task in-progress → the beacon spins (a braille frame, never the static ●)
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sBusy"
  jq -n '{id:"1",subject:"working",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sBusy/1.json"
  p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sBusy",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm "$2"' _ "$p" "$SL"
  [[ "$output" != *"●"* ]]              # in-progress → animated braille, no static dot
}
