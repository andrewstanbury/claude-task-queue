#!/usr/bin/env bats
#
# Tests for the hud status line: the read-only accessors and a render smoke
# test. Faked via CLAUDE_HUD_* overrides + a temp git repo.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/hud-status.sh"
  export CLAUDE_HUD_PAUSE_DIR="$(mktemp -d)"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  SRC='. "$1/lib/hud.sh";'
}

teardown() {
  rm -rf "$CLAUDE_HUD_PAUSE_DIR" "$(dirname "$REPO")"
}

@test "hud_paused reflects the repo's pause flag" {
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "0" ]
  touch "$CLAUDE_HUD_PAUSE_DIR/-some-repo"
  run bash -c "$SRC"' hud_paused "/some/repo"' bash "$ROOT"
  [ "$output" = "1" ]
}

@test "hud_agent reflects task-queue's per-repo agent-mode flag" {
  export CLAUDE_HUD_AGENT_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AGENT_DIR/-some-repo"
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  rm -rf "$CLAUDE_HUD_AGENT_DIR"
}

@test "hud_checkpoint reflects task-queue's per-repo checkpoint flag" {
  export CLAUDE_HUD_CKPT_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_checkpoint "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_CKPT_DIR/-some-repo"
  run bash -c "$SRC"' hud_checkpoint "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  rm -rf "$CLAUDE_HUD_CKPT_DIR"
}

@test "hud_away reflects task-queue's per-repo away-mode flag" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_away "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AWAY_DIR/-some-repo"
  run bash -c "$SRC"' hud_away "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "hud_verify reads the verification floor's last outcome" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ -z "$output" ]
  printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sessabc"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ "$output" = "pass" ]
  printf 'fail' > "$CLAUDE_HUD_VERIFY_DIR/result-sessabc"
  run bash -c "$SRC"' hud_verify "sessabc"' bash "$ROOT"; [ "$output" = "fail" ]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "hud_human_tokens: verbatim <1k, N.Nk thousands, N.NM millions, empty on junk" {
  run bash -c "$SRC"' hud_human_tokens 850' bash "$ROOT";     [ "$output" = "850" ]
  run bash -c "$SRC"' hud_human_tokens 12530' bash "$ROOT";   [ "$output" = "12.5k" ]
  run bash -c "$SRC"' hud_human_tokens 1250000' bash "$ROOT"; [ "$output" = "1.2M" ]
  run bash -c "$SRC"' hud_human_tokens ""' bash "$ROOT";      [ -z "$output" ]
  run bash -c "$SRC"' hud_human_tokens abc' bash "$ROOT";     [ -z "$output" ]
}

@test "hud_dirty counts uncommitted files, empty on a clean tree" {
  run bash -c "$SRC"' hud_dirty "$2"' bash "$ROOT" "$REPO"; [ -z "$output" ]   # clean
  printf 'x\n' > "$REPO/new.txt"
  run bash -c "$SRC"' hud_dirty "$2"' bash "$ROOT" "$REPO"; [ "$output" = "1" ]
}

@test "renders a single line with the key slots (ctx %, model)" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus 4.8"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:68, context_window_size:1000000}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctx 68%"* ]]
  [[ "$output" == *"Opus 4.8"* ]]
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]   # single line
}

@test "render: 🚶 away when away-mode is on, hidden when off" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"🚶 away"* ]]
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  touch "$CLAUDE_HUD_AWAY_DIR/$(printf '%s' "$REPO" | sed 's:/:-:g')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"🚶 away"* ]]
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "render: 🧷 ckpt when the crash checkpoint is armed, hidden when off" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"🧷 ckpt"* ]]                 # off by default
  export CLAUDE_HUD_CKPT_DIR="$(mktemp -d)"
  touch "$CLAUDE_HUD_CKPT_DIR/$(printf '%s' "$REPO" | sed 's:/:-:g')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"🧷 ckpt"* ]]                 # shown when armed
  rm -rf "$CLAUDE_HUD_CKPT_DIR"
}

@test "render: ✓ tests when the verification floor last passed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✓ tests"* ]]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: ✗ tests when the verification floor last failed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'fail' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✗ tests"* ]]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: omits ctx when the payload has no context_window" {
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"ctx"* ]]
}

# ---- hud-install (status-line wiring) ---------------------------------------

@test "install: adds a version-resilient statusLine, preserving other settings" {
  local s; s="$(mktemp -d)/settings.json"
  printf '{"existingKey":true}\n' > "$s"
  run bash -c 'CLAUDE_SETTINGS="$1" "$2/bin/hud-install.sh"' _ "$s" "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.existingKey == true' "$s"                       # preserved
  jq -e '.statusLine.type == "command"' "$s"
  [[ "$(jq -r '.statusLine.command' "$s")" == *"sort -V | tail -1"* ]]   # self-resolving, not version-pinned
  [[ "$(jq -r '.statusLine.command' "$s")" != *"/0.1.0/"* ]]
  rm -rf "$(dirname "$s")"
}

@test "install: creates settings.json when absent" {
  local s; s="$(mktemp -d)/settings.json"   # file does not exist yet
  run bash -c 'CLAUDE_SETTINGS="$1" "$2/bin/hud-install.sh"' _ "$s" "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.statusLine.command' "$s"
  rm -rf "$(dirname "$s")"
}

@test "hud_open_questions counts pending/in_progress ❓ tasks (deduped), ignores the rest" {
  export CLAUDE_HUD_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_HUD_TASKS_DIR/sQ"
  jq -n '{id:"1",subject:"❓ Block or warn?",status:"pending"}'      > "$CLAUDE_HUD_TASKS_DIR/sQ/1.json"
  jq -n '{id:"2",subject:"❓ Which style?",status:"in_progress"}'    > "$CLAUDE_HUD_TASKS_DIR/sQ/2.json"
  jq -n '{id:"3",subject:"Do some work",status:"pending"}'          > "$CLAUDE_HUD_TASKS_DIR/sQ/3.json"
  jq -n '{id:"4",subject:"❓ already answered",status:"completed"}'  > "$CLAUDE_HUD_TASKS_DIR/sQ/4.json"
  run bash -c "$SRC"' hud_open_questions sQ' bash "$ROOT"
  [ "$output" = "2" ]
  run bash -c "$SRC"' hud_open_questions none' bash "$ROOT"
  [ "$output" = "0" ]
  rm -rf "$CLAUDE_HUD_TASKS_DIR"
}

@test "status line shows ❓N when open questions exist for the session" {
  export CLAUDE_HUD_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_HUD_TASKS_DIR/sR"
  jq -n '{id:"1",subject:"❓ pending one",status:"pending"}' > "$CLAUDE_HUD_TASKS_DIR/sR/1.json"
  json="$(jq -nc --arg s sR --arg c "$REPO" '{model:{display_name:"Opus"},session_id:$s,cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"❓1"* ]]
  rm -rf "$CLAUDE_HUD_TASKS_DIR"
}

@test "hud_ahead_behind: empty without an upstream, '<ahead> <behind>' with one" {
  run bash -c "$SRC"' hud_ahead_behind "$2"' bash "$ROOT" "$REPO"   # no upstream yet
  [ -z "$output" ]
  # Build a bare "remote", track it, then commit locally so HEAD is ahead by 2.
  local up; up="$(mktemp -d)/up.git"; git init -q --bare "$up"
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  git -C "$REPO" commit -q --allow-empty -m base
  git -C "$REPO" remote add origin "$up"
  git -C "$REPO" push -q origin HEAD:refs/heads/main
  git -C "$REPO" branch -q --set-upstream-to=origin/main
  git -C "$REPO" commit -q --allow-empty -m a
  git -C "$REPO" commit -q --allow-empty -m b
  run bash -c "$SRC"' hud_ahead_behind "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "2 0" ]                                             # 2 ahead, 0 behind
  rm -rf "$(dirname "$up")"
}

@test "status line shows ↑N for unpushed commits next to the branch" {
  local up; up="$(mktemp -d)/up.git"; git init -q --bare "$up"
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  git -C "$REPO" commit -q --allow-empty -m base
  git -C "$REPO" remote add origin "$up"; git -C "$REPO" push -q origin HEAD:refs/heads/main
  git -C "$REPO" branch -q --set-upstream-to=origin/main
  git -C "$REPO" commit -q --allow-empty -m unpushed
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"↑1"* ]]
  rm -rf "$(dirname "$up")"
}

@test "status line shows session cost from the payload, hidden at zero" {
  json="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200,cost:{total_cost_usd:0.4231}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *'$0.42'* ]]
  json="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200,cost:{total_cost_usd:0}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *'$0.00'* ]]
}

@test "status line shows the token slot (⇡input ⇣output), silent before the first API call" {
  json="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200,
      context_window:{total_input_tokens:12530,total_output_tokens:1180}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"tok ⇡12.5k ⇣1.1k"* ]]
  # no context_window (before the first response, or post-compact) → slot collapses
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"tok"* ]]
}

@test "hud_floors_disabled: empty when all on, names each floor set to 0" {
  run bash -c "$SRC"' hud_floors_disabled' bash "$ROOT"; [ -z "$output" ]
  run bash -c "$SRC"' CLAUDE_TIDY_CHECKS=0 hud_floors_disabled' bash "$ROOT"
  [ "$output" = "tests" ]
  run bash -c "$SRC"' CLAUDE_TIDY_SECSCAN=0 CLAUDE_TQ_INTENT_GATE=0 hud_floors_disabled' bash "$ROOT"
  [ "$output" = "secret-scan intent-check" ]   # owner-ordered, space-separated, no leading space
}

@test "status line shows 🛡✗N when a safety floor is disabled, hidden when all on" {
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"🛡"* ]]                                    # all on → no marker
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_TIDY_CHECKS=0 CLAUDE_CHARTER_ALIGN_GATE=0 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🛡✗2"* ]]                                  # two off → count of 2
}

@test "status line keeps the 🛡✗ warning even on a narrow terminal (safety never sheds)" {
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:60}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_TIDY_SECSCAN=0 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🛡✗1"* ]]
}

@test "--legend prints the symbol key and the currently-disabled floors" {
  run bash -c 'NO_COLOR=1 "$1" --legend' _ "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"hud status-line key"* ]]
  [[ "$output" == *"🛡✗"* ]]
  [[ "$output" == *"open questions"* ]]
  run bash -c 'NO_COLOR=1 CLAUDE_TIDY_QUALITY_FLOOR=0 "$1" --legend' _ "$STATUS"
  [[ "$output" == *"Currently disabled"* ]]
  [[ "$output" == *"quality"* ]]
}

@test "hud_coupling reads tidy's cached direction marker" {
  export CLAUDE_HUD_COUPLING_DIR="$(mktemp -d)"
  printf 'up' > "$CLAUDE_HUD_COUPLING_DIR/-some-repo"
  run bash -c "$SRC"' hud_coupling "/some/repo"' bash "$ROOT"; [ "$output" = "up" ]
  printf 'steady' > "$CLAUDE_HUD_COUPLING_DIR/-some-repo"
  run bash -c "$SRC"' hud_coupling "/some/repo"' bash "$ROOT"; [ "$output" = "steady" ]
  rm -rf "$CLAUDE_HUD_COUPLING_DIR"
}

@test "status line shows 🔗↑ only when coupling climbed (hidden when steady)" {
  export CLAUDE_HUD_COUPLING_DIR="$(mktemp -d)"
  enc="$(printf '%s' "$(git -C "$REPO" rev-parse --show-toplevel)" | sed 's:/:-:g')"
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c}')"
  printf 'up' > "$CLAUDE_HUD_COUPLING_DIR/$enc"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🔗↑"* ]]
  printf 'steady' > "$CLAUDE_HUD_COUPLING_DIR/$enc"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"🔗"* ]]
  rm -rf "$CLAUDE_HUD_COUPLING_DIR"
}
