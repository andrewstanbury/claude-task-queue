#!/usr/bin/env bats
#
# The status line (the glance surface): the animated beacon, the 🛡 secret-gate indicator, the
# ◻/❓/⏳ task split, and git branch + ahead/behind. Read-only; renders from the JSON Claude Code
# pipes on stdin plus the companion's own state.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"
  AP="$ROOT/bin/autopilot.sh"; ASK="$ROOT/bin/ask-guard.sh"; STOP="$ROOT/bin/stop-autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

# Write a per-repo feature OFF flag directly (the `/companion:features` CLI was removed 2026-07-18,
# R50; the flag mechanism + the statusline's read of it are unchanged).
_feature_off() {  # $1=feature  $2=repo-dir
  local root enc; root="$(git -C "$2" rev-parse --show-toplevel)"
  enc="$(printf '%s' "$root" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  mkdir -p "$CLAUDE_COMPANION_STATE_DIR/features"
  printf '%s=off\n' "$1" >> "$CLAUDE_COMPANION_STATE_DIR/features/$enc"
}

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
  [[ "$output" == *"🛡️"* ]]           # shield carries U+FE0F → full emoji width, matching ✈️/📦 (even spacing, owner-reported 2026-07-19)
  local pv; pv="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  [[ "$output" == *"v$pv"* ]]          # plugin version shown (from the manifest, not hardcoded)
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
  [[ "$output" == *"🛡"*"✗"* ]]
}

@test "status line: 🛡✗ when the secret gate is off per-repo via the secret=off flag (R50)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"s",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" != *"✗"* ]]                       # on → plain shield
  _feature_off secret "$repo"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" == *"🛡"*"✗"* ]]                    # off for this repo → ✗
}

@test "status line: 📦 ship-mode icon shows only when ship-mode is armed (R34)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"s",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" != *"📦"* ]]                 # ship-mode off → no icon
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" == *"📦"* ]]                 # armed → icon shows
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

@test "status line: beacon animates under autopilot even with no in-progress task (R55 dogfood gap)" {
  # Activity = autopilot DRAINING or in-progress — not in-progress alone. The regen dogfood on
  # statusline.sh silently dropped this because nothing pinned it; this closes that gap.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ( cd "$repo" && "$AP" on ) >/dev/null                 # autopilot armed for this repo
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sAP"
  jq -n '{id:"1",subject:"later",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sAP/1.json"   # pending, NOT in-progress
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sAP",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm "$2"' _ "$p" "$SL"
  [[ "$output" == *"✈️"* ]]              # autopilot armed → ✈️ shows
  [[ "$output" != *"●"* ]]              # and the beacon spins (braille frame), NOT the static idle dot
}

@test "status line: ⚡ decisive indicator shows only when autopilot AND decisive are on (R59)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sDec",cwd:$c}')"
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" == *"✈️"* ]]; [[ "$output" != *"⚡"* ]]   # autopilot on, decisive off → ✈️ but no ⚡
  ( cd "$repo" && "$AP" decisive on ) >/dev/null
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" == *"✈️⚡"* ]]                            # decisive on → ✈️⚡
  ( cd "$repo" && "$AP" off ) >/dev/null                 # decisive is a no-op without autopilot
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" != *"⚡"* ]]; [[ "$output" != *"✈️"* ]]
}

@test "status line: sections render in R34 plugin-relevance order — beacon → features → queue → git (R56 #24)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOrd"
  jq -n '{id:"1",subject:"x",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOrd/1.json"
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sOrd",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [ "$status" -eq 0 ]
  # beacon → 🛡 (features) → 📋 (queue) → ⎇ (git): the R34 order. A reordered bar fails this.
  printf '%s' "$output" | grep -qE '●.*🛡.*📋.*⎇'
}

@test "status line: semantic colors — red shield when gate off, yellow beacon under autopilot (R56 #24)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sClr",cwd:$c}')"
  # gate OFF → the shield carries the RED code (\033[31m is used ONLY by the off-shield)
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm CLAUDE_COMPANION_SECSCAN=0 "$2"' _ "$p" "$SL"
  [[ "$output" == *$'\033[31m'* ]]         # red present → shield-off is red (a semantic signal, not decoration)
  # gate ON → no red anywhere
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm "$2"' _ "$p" "$SL"
  [[ "$output" != *$'\033[31m'* ]]
  # autopilot ON → the beacon LEADS yellow (\033[33m at the very start)
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm "$2"' _ "$p" "$SL"
  [[ "$output" == $'\033[33m'* ]]          # output starts yellow → the beacon is yellow-tinted under autopilot
}
