#!/usr/bin/env bats
#
# Tests for the hud status line: the read-only accessors and a render smoke
# test. Faked via CLAUDE_HUD_* overrides + a temp git repo.

setup() {
  unset CLAUDE_TQ_AGENT_MODE   # isolate from any global default
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STATUS="$ROOT/bin/hud-status.sh"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  SRC='. "$1/lib/hud.sh";'
}

teardown() {
  rm -rf "$(dirname "$REPO")"
}

@test "hud_agent reflects task-queue's per-repo agent-mode flag" {
  export CLAUDE_HUD_AGENT_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AGENT_DIR/%2Fsome%2Frepo"    # tq_enc_root encoding: / → %2F
  run bash -c "$SRC"' hud_agent "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  rm -rf "$CLAUDE_HUD_AGENT_DIR"
}

@test "hud_away reflects task-queue's per-repo away-mode flag" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_away "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AWAY_DIR/%2Fsome%2Frepo"    # tq_enc_root encoding: / → %2F
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

@test "renders a single line with the key slots (feature status, model)" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus 4.8"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus 4.8"* ]]
  [[ "$output" != *"autopilot"* ]]                  # Hybrid: no words on the toggles…
  [[ "$output" != *"agents"* ]]                     # …and both off by default → no ✈️/🤖 at all
  [[ "$output" != *"ctx"* ]]                        # ctx slot removed
  [ "$(printf '%s\n' "$output" | wc -l)" -eq 1 ]   # single line
}

@test "render: palette uses default ANSI theme colors (no pinned RGB), none under NO_COLOR" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  # color terminal → plain ANSI SGR codes that inherit the terminal theme, and NO
  # pinned 24-bit RGB (38;2;...). Even when COLORTERM=truecolor is advertised we
  # let the terminal own the hue. Pin the whole color environment (unset NO_COLOR,
  # non-dumb TERM) so CI's TERM=dumb can't preempt it.
  run bash -c 'printf "%s" "$1" | env -u NO_COLOR TERM=xterm COLORTERM=truecolor "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *$'\033[32m'* ]]
  [[ "$output" != *$'\033[38;2;'* ]]
  # NO_COLOR wins → no escape codes at all
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 COLORTERM=truecolor TERM=xterm "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *$'\033['* ]]
}

@test "render: ✈️ shows when the away flag is set, absent otherwise (presence = on)" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"✈️"* ]]                        # off → no plane at all
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  touch "$CLAUDE_HUD_AWAY_DIR/$(printf '%s' "$REPO" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✈️"* ]]                        # on → plane shown, no "autopilot" word
  [[ "$output" != *"autopilot"* ]]
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "render: ✓ tests when the verification floor last passed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'pass' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✅"* ]]                          # self-colored pass emoji, no "tests" word
  [[ "$output" != *"tests"* ]]
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: ✗ tests when the verification floor last failed" {
  export CLAUDE_HUD_VERIFY_DIR="$(mktemp -d)"; printf 'fail' > "$CLAUDE_HUD_VERIFY_DIR/result-sess"
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, context_window:{used_percentage:5}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"❌"* ]]                          # self-colored fail emoji, no "tests" word
  rm -rf "$CLAUDE_HUD_VERIFY_DIR"
}

@test "render: repo-name anchor sits just left of the branch on a wide terminal" {
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  echo x > "$REPO/f"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m init
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"proj"* ]]                       # basename of REPO (…/proj)
  [[ "$output" == *"proj"*"⎇"* ]]                   # and it sits left of the branch marker
}

@test "render: no ctx slot (removed in favor of always-on feature status)" {
  payload="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c,
      context_window:{used_percentage:68}, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" != *"ctx"* ]]
}

@test "render: feature status honors the global-default env (agents on, no flag)" {
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_TQ_AGENT_MODE=on "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"🤖"* ]]                       # env default flips the icon on with no per-repo flag
  [[ "$output" != *"agents"* ]]                   # no word
}

@test "render: the feature zone hugs the trailing divider (no space after the wide emoji)" {
  # Wide emoji under-fill their 2-cell slot, so a normal " │" after one looks double-spaced.
  # The trailing divider is tight so the emoji's own advance supplies the gap → "│ 🤖 │" reads even.
  export CLAUDE_HUD_AGENT_DIR="$(mktemp -d)"
  touch "$CLAUDE_HUD_AGENT_DIR/$(printf '%s' "$REPO" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"🤖│"* ]]                       # emoji immediately followed by the divider, no space
  rm -rf "$CLAUDE_HUD_AGENT_DIR"
}

@test "render: narrow terminal collapses feature status to only the ON ones" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  touch "$CLAUDE_HUD_AWAY_DIR/$(printf '%s' "$REPO" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  payload="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"}, session_id:"sess", cwd:$c, terminal_width:60}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$STATUS"
  [[ "$output" == *"✈️"* ]]                   # ON shows (presence = on, narrow or wide)
  [[ "$output" != *"🤖"* ]]                   # agents off → absent
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

# ---- hud-install (status-line wiring) ---------------------------------------

@test "install: adds a version-resilient statusLine, preserving other settings" {
  local s; s="$(mktemp -d)/settings.json"
  printf '{"existingKey":true}\n' > "$s"
  run bash -c 'CLAUDE_SETTINGS="$1" "$2/bin/hud-install.sh"' _ "$s" "$ROOT"
  [ "$status" -eq 0 ]
  jq -e '.existingKey == true' "$s"                       # preserved
  jq -e '.statusLine.type == "command"' "$s"
  jq -e '.statusLine.refreshInterval == 1' "$s"          # drives the animated beacon (1 fps)
  [[ "$(jq -r '.statusLine.command' "$s")" == *"ls -dt"*"| head -1"* ]]   # self-resolving (newest mtime wins), not version-pinned
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

@test "hud_review_pending reflects task-queue's return-review gate marker (per repo)" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_review_pending "/some/repo"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AWAY_DIR/review-%2Fsome%2Frepo"    # tq_review_file encoding: / → %2F
  run bash -c "$SRC"' hud_review_pending "/some/repo"' bash "$ROOT"; [ "$output" = "1" ]
  run bash -c "$SRC"' hud_review_pending ""' bash "$ROOT"; [ "$output" = "0" ]
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "hud_design_pending reflects task-queue's design-preview marker (per session)" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  run bash -c "$SRC"' hud_design_pending "sX"' bash "$ROOT"; [ "$output" = "0" ]
  touch "$CLAUDE_HUD_AWAY_DIR/design-sX"
  run bash -c "$SRC"' hud_design_pending "sX"' bash "$ROOT"; [ "$output" = "1" ]
  run bash -c "$SRC"' hud_design_pending ""' bash "$ROOT"; [ "$output" = "0" ]
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "status line shows 🔒 when the return-review gate is armed for the repo" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  local root enc; root="$(git -C "$REPO" rev-parse --show-toplevel)"; enc="$(printf '%s' "$root" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  json="$(jq -nc --arg s sL --arg c "$REPO" '{model:{display_name:"Opus"},session_id:$s,cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"🔒"* ]]                          # not armed → hidden
  touch "$CLAUDE_HUD_AWAY_DIR/review-$enc"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🔒"* ]]                          # armed → shown
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
}

@test "status line shows 🎨 while a design preview is pending for the session" {
  export CLAUDE_HUD_AWAY_DIR="$(mktemp -d)"
  json="$(jq -nc --arg s sD --arg c "$REPO" '{model:{display_name:"Opus"},session_id:$s,cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"🎨"* ]]                          # not pending → hidden
  touch "$CLAUDE_HUD_AWAY_DIR/design-sD"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🎨"* ]]                          # pending → shown
  rm -rf "$CLAUDE_HUD_AWAY_DIR"
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

@test "status line no longer renders the session cost ($) slot (removed to save width)" {
  json="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200,cost:{total_cost_usd:0.4231}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *'$0.42'* ]]
}

@test "status line shows the token slot (⇡input ⇣output), silent before the first API call" {
  json="$(jq -nc --arg c "$REPO" \
    '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200,
      context_window:{total_input_tokens:12530,total_output_tokens:1180}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"⇡12.5k ⇣1.1k"* ]]
  [[ "$output" != *"tok"* ]]   # the "tok" label was dropped — just the ⇡/⇣ arrows now
  # no context_window (before the first response, or post-compact) → slot collapses
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"⇡"* ]]
}

@test "health beacon: braille-orbit frame animates with color AND with no-color; static ● only on TERM=dumb" {
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  braille='⠋|⠙|⠹|⠸|⠼|⠴|⠦|⠧|⠇|⠏'
  # color on → a braille frame, never the static dot
  run bash -c 'printf "%s" "$1" | TERM=xterm NO_COLOR= "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"●"* ]]
  printf '%s' "$output" | grep -qE "$braille"
  # NO_COLOR (capable terminal) → STILL animates: a braille frame, no static dot. The
  # braille shapes read without color, so no-color no longer means a frozen beacon.
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 TERM=xterm "$2"' _ "$json" "$STATUS"
  [[ "$output" != *"●"* ]]
  printf '%s' "$output" | grep -qE "$braille"
  # TERM=dumb → static ● (can't rely on braille rendering there)
  run bash -c 'printf "%s" "$1" | TERM=dumb "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"●"* ]]
  ! printf '%s' "$output" | grep -qE "$braille"
}

@test "hud_floors_disabled: empty when all on, names each floor set to 0" {
  run bash -c "$SRC"' hud_floors_disabled' bash "$ROOT"; [ -z "$output" ]
  run bash -c "$SRC"' CLAUDE_TIDY_CHECKS=0 hud_floors_disabled' bash "$ROOT"
  [ "$output" = "tests" ]
  run bash -c "$SRC"' CLAUDE_TIDY_SECSCAN=0 CLAUDE_TQ_INTENT_GATE=0 hud_floors_disabled' bash "$ROOT"
  [ "$output" = "secret-scan intent-check" ]   # owner-ordered, space-separated, no leading space
}

@test "status line shows green 🛡 when all floors on, 🛡✗N when any disabled" {
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:200}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🛡"* ]]                                    # all on → shield present (positive)
  [[ "$output" != *"🛡✗"* ]]                                   # ...and it's the healthy shield, not the alarm
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_TIDY_CHECKS=0 CLAUDE_CHARTER_ALIGN_GATE=0 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🛡✗2"* ]]                                  # two off → count of 2
}

@test "status line keeps the green 🛡 even on a narrow terminal (safety never sheds)" {
  json="$(jq -nc --arg c "$REPO" '{model:{display_name:"Opus"},session_id:"s",cwd:$c,terminal_width:60}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$json" "$STATUS"
  [[ "$output" == *"🛡"* ]]
  [[ "$output" != *"🛡✗"* ]]
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
