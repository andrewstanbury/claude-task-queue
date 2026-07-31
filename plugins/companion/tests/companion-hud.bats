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
  # Render tests assert on REAL git state, so the git-segment TTL cache is off by default here —
  # otherwise a test that changes the tree between two runs would read its own stale line. The
  # cache has its own dedicated tests below, which set the TTL explicitly.
  export CLAUDE_COMPANION_SL_CACHE_TTL=0
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

@test "status line: renders version · model · tokens · task count · project · branch (no shield when gate on)" {
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
  [[ "$output" != *"🛡"* ]]            # gate ON (default) → NO shield icon; the guard shows one only when disabled (owner request 2026-07-19)
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
  # gate OFF so the features section is populated (🛡️✗) — proves feature placement between beacon and queue
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_SECSCAN=0 NO_COLOR=1 "$2"' _ "$p" "$SL"
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

# ── account rate-limit bars (R76) ──────────────────────────────────────────────────────────────
# `.rate_limits` is the ONLY account-scoped input the line has, and it is optional in three
# different ways (API-key users, pre-first-response, per-window). Every one of those must render
# nothing rather than a zero or a placeholder, so each absence shape gets a case.

@test "status line: 5h + 7d usage bars render both windows from .rate_limits (R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRL",cwd:$c,
    rate_limits:{five_hour:{used_percentage:23.5},seven_day:{used_percentage:41.2}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h"* ]] && [[ "$output" == *"23%"* ]]   # float truncated to int, not rounded
  [[ "$output" == *"7d"* ]] && [[ "$output" == *"41%"* ]]
  [[ "$output" == *"▰"* ]] && [[ "$output" == *"▱"* ]]      # partially-filled bar
}

@test "status line: no .rate_limits (API-key user / pre-first-response) renders NO bar (R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRL2",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"5h"* ]]; [[ "$output" != *"7d"* ]]
  [[ "$output" != *"▰"* ]]; [[ "$output" != *"▱"* ]]
  [[ "$output" != *"0%"* ]]     # never invent a zero for a number we were not given
  [[ "$output" == *"Opus"* ]]   # the rest of the line still renders
}

@test "status line: one window absent renders ONLY the other — no field shift (R76)" {
  # Regression pin: `IFS=$'\t' read` collapses consecutive tabs (tab is IFS whitespace), which
  # would slide 7d's percentage into the 5h slot whenever five_hour was missing. The reader uses
  # a non-whitespace separator so an empty field stays empty in place.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRL3",cwd:$c,
    rate_limits:{seven_day:{used_percentage:41.2}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"5h"* ]]      # absent window is silent...
  [[ "$output" == *"7d"* ]]      # ...and the present one keeps its own label
  [[ "$output" == *"41%"* ]]     # and its own value — NOT re-labelled as 5h
}

@test "status line: usage bar clamps >100, keeps 87% distinguishable from 100% (R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRL4",cwd:$c,
    rate_limits:{five_hour:{used_percentage:87},seven_day:{used_percentage:130}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"87%"* ]]
  [[ "$output" == *"100%"* ]]        # 130 clamped, never "130%"
  [[ "$output" != *"130%"* ]]
  [[ "$output" == *"5h ▰▰▰▰▱ 87%"* ]]  # floor: 87% is NOT a full bar
  [[ "$output" == *"7d ▰▰▰▰▰ 100%"* ]] # only a truly exhausted window fills
}

@test "status line: usage bar severity colors — green <60, yellow 60-84, red >=85 (R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  # Extract the SGR in PURE BASH. `cat -v` + `grep -o '\^\['…` reads the same on GNU but not on
  # BSD/macOS, where the backslash-escaped `^` in a BRE is not portable — that dialect gap turned
  # a green local run into a red macOS CI run for a colour that is a fixed string either way.
  # Prefix-match the literal escape sequence instead: no external tool, no regex dialect.
  local esc; esc=$'\033'
  _bar_sgr() {  # $1 = used_percentage → the SGR code applied to the bar
    local p="$1" out rest
    out="$(printf '%s' "$(jq -nc --arg c "$repo" --argjson p "$p" \
      '{model:{display_name:"Opus"},session_id:"sRL5",cwd:$c,rate_limits:{five_hour:{used_percentage:$p}}}')" \
      | env -u NO_COLOR TERM=xterm "$SL")"
    rest="${out#*5h}"                     # label → reset → the space → the bar's colour
    case "$rest" in
      "$esc[0m $esc[32m"*) printf '32m' ;;
      "$esc[0m $esc[33m"*) printf '33m' ;;
      "$esc[0m $esc[31m"*) printf '31m' ;;
      *) printf 'none' ;;
    esac
  }
  [ "$(_bar_sgr 30)" = "32m" ]   # green
  [ "$(_bar_sgr 59)" = "32m" ]   # green, just under the line
  [ "$(_bar_sgr 60)" = "33m" ]   # yellow
  [ "$(_bar_sgr 84)" = "33m" ]   # yellow, just under the line
  [ "$(_bar_sgr 85)" = "31m" ]   # red
  [ "$(_bar_sgr 100)" = "31m" ]  # red
}

@test "status line: reset countdown shows whenever resets_at is present, at ANY usage (R76 amended)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  # Deliberately NOT an exact multiple of a minute: the script reads its own clock a beat after the
  # test builds the payload, so "now + 45m" floors to 44m whenever a second elapses in between.
  # Assert the countdown's PRESENCE and unit, never a specific remaining count.
  local soon; soon=$(( $(date +%s) + 2700 ))     # ~45 min out
  # LOW usage shows the countdown too — the >=80% gate was reversed 2026-07-31 (owner-picked).
  # It sits IN THE LABEL SLOT, immediately before the bar, and the window name `5h` is GONE.
  local low; low="$(jq -nc --arg c "$repo" --argjson r "$soon" '{model:{display_name:"Opus"},session_id:"sRL6",cwd:$c,
    rate_limits:{five_hour:{used_percentage:3,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$low" "$SL"
  [[ "$output" =~ ↻[0-9]+m\ ▰ ]]     # countdown, space, then the bar — the label slot itself
  [[ "$output" != *"5h"* ]]          # the window name it replaced is gone, not merely moved
  # high usage still shows it, in minutes
  local high; high="$(jq -nc --arg c "$repo" --argjson r "$soon" '{model:{display_name:"Opus"},session_id:"sRL7",cwd:$c,
    rate_limits:{five_hour:{used_percentage:90,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$high" "$SL"
  [[ "$output" =~ ↻[0-9]+m\ ▰ ]]
  # a multi-day window reports days, not thousands of minutes
  local far; far="$(jq -nc --arg c "$repo" --argjson r "$(( $(date +%s) + 300000 ))" '{model:{display_name:"Opus"},session_id:"sRL8",cwd:$c,
    rate_limits:{seven_day:{used_percentage:95,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$far" "$SL"
  [[ "$output" =~ ↻3d ]]
  # NO resets_at → the bar still renders and NO countdown appears. This is the honest-absence case:
  # the field is missing for API-key users and before the session's first API response.
  local none; none="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRL9",cwd:$c,
    rate_limits:{five_hour:{used_percentage:41.2}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$none" "$SL"
  [[ "$output" == *"5h ▰▰▱▱▱ 41%"* ]]   # the window NAME is back in the slot — never anonymous
  [[ "$output" != *"↻"* ]]
  # An ALREADY-ELAPSED reset time prints no countdown rather than a negative one. Reversing the
  # >=80% gate widened this path from "only under pressure" to every payload that carries the
  # field, so the guard matters MORE now, not less — a stale timestamp is the common case right
  # after a window rolls.
  local past; past="$(jq -nc --arg c "$repo" --argjson r "$(( $(date +%s) - 60 ))" '{model:{display_name:"Opus"},session_id:"sRLa",cwd:$c,
    rate_limits:{five_hour:{used_percentage:95,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$past" "$SL"
  [[ "$output" == *"5h ▰▰▰▰▱ 95%"* ]]; [[ "$output" != *"↻"* ]]
  # A NON-NUMERIC resets_at (an ISO string, a float epoch, anything) is discarded, not arithmetic'd
  # — `$(( ))` on a string would abort the whole status line under `set -e` (R68: best-effort, the
  # line must still render). The bar survives; only the countdown is dropped.
  local junk err; err="$(mktemp)"
  junk="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRLb",cwd:$c,
    rate_limits:{five_hour:{used_percentage:70,resets_at:"2026-07-31T12:00:00Z"}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2" 2>"$3"' _ "$junk" "$SL" "$err"
  [ "$status" -eq 0 ]; [[ "$output" == *"5h ▰▰▰▱▱ 70%"* ]]; [[ "$output" != *"↻"* ]]
  # STDERR MUST BE SILENT, and that is the assertion the guard actually needs. Since the countdown
  # moved into `rlleft`, it is computed in a command substitution — which ISOLATES an arithmetic
  # failure, so dropping the guard no longer changes a single rendered glyph. What it changes is
  # a bash parse error on stderr every repaint (~1200/hour). Asserting only the rendering left a
  # mutation hole here; this is the line that closes it.
  [ ! -s "$err" ]; rm -f "$err"
}

@test "status line: the ▴/▾ pace marker says whether the 7d window will be spent (R76)" {
  local repo now; repo="$(mktemp -d)"; git -C "$repo" init -q; now="$(date +%s)"
  # The 7d window is 604800s. `resets_at = now + 345600` (4d left) puts it 3d in → 42% elapsed.
  # BEHIND: 41% used against 42% elapsed → at this rate the window resets unspent.
  local behind; behind="$(jq -nc --arg c "$repo" --argjson r "$(( now + 345600 ))" '{model:{display_name:"Opus"},session_id:"sP1",cwd:$c,
    rate_limits:{seven_day:{used_percentage:41,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$behind" "$SL"
  [[ "$output" == *"41%▾"* ]]          # marker rides the percent, no gap
  # AHEAD: same instant, 60% used against the same 42% elapsed.
  local ahead; ahead="$(jq -nc --arg c "$repo" --argjson r "$(( now + 345600 ))" '{model:{display_name:"Opus"},session_id:"sP2",cwd:$c,
    rate_limits:{seven_day:{used_percentage:60,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$ahead" "$SL"
  [[ "$output" == *"60%▴"* ]]
  # The marker is NOT a restatement of the percentage: these two payloads differ ONLY in how far
  # into the window they are, and the SAME 41% flips the verdict. That is the whole point of it.
  local early; early="$(jq -nc --arg c "$repo" --argjson r "$(( now + 594000 ))" '{model:{display_name:"Opus"},session_id:"sP3",cwd:$c,
    rate_limits:{seven_day:{used_percentage:41,resets_at:$r}}}')"   # ~2% elapsed
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$early" "$SL"
  [[ "$output" == *"41%▴"* ]]
  # 5h NEVER carries a marker — it is passed no window length, and "on pace" is not a question
  # anyone asks of it. Pin it on a payload where the 5h numbers would otherwise read as behind.
  local both; both="$(jq -nc --arg c "$repo" --argjson a "$(( now + 900 ))" --argjson r "$(( now + 345600 ))" '{model:{display_name:"Opus"},session_id:"sP4",cwd:$c,
    rate_limits:{five_hour:{used_percentage:3,resets_at:$a},seven_day:{used_percentage:41,resets_at:$r}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$both" "$SL"
  [[ "$output" == *"3%"* ]]; [[ "$output" != *"3%▾"* ]]; [[ "$output" != *"3%▴"* ]]
  [[ "$output" == *"41%▾"* ]]          # ...while the 7d beside it still carries one
  # NO resets_at → no marker at all. The marker is only ever as good as the timestamp behind it,
  # and there is no pace to report without one (same silence as the countdown).
  local none; none="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sP5",cwd:$c,
    rate_limits:{seven_day:{used_percentage:41}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$none" "$SL"
  [[ "$output" == *"7d ▰▰▱▱▱ 41%"* ]]; [[ "$output" != *"▾"* ]]; [[ "$output" != *"▴"* ]]
}

@test "status line: a control character in the payload cannot truncate the line (R76)" {
  # `@tsv` used to escape \n\r\t for us; a plain join does not. A newline in a path or model name
  # would split jq's record so `read` took only the first line — silently dropping the tokens,
  # both bars and the git segment. The reader neutralises framing characters before joining.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local weird="$repo/we
ird"; mkdir -p "$weird"
  local payload; payload="$(jq -nc --arg c "$weird" '{model:{display_name:"Opus"},session_id:"sRLc",cwd:$c,
    context_window:{total_input_tokens:5000,total_output_tokens:200},
    rate_limits:{five_hour:{used_percentage:23.5},seven_day:{used_percentage:41.2}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]        # ONE line out, whatever went in
  [[ "$output" == *"Opus"* ]]     # fields after the newline survive intact...
  [[ "$output" == *"⇡5.0k"* ]]
  [[ "$output" == *"23%"* ]]
  [[ "$output" == *"41%"* ]]      # ...including the LAST one, the far side of the break
}

@test "status line: usage bars sit between the queue and the model (R34 order, R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sRLo"   # an OPEN task, or 📋 is absent by design (R80)
  jq -n '{id:"1",subject:"work",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sRLo/1.json"
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRLo",cwd:$c,
    rate_limits:{five_hour:{used_percentage:23.5},seven_day:{used_percentage:41.2}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  # queue → 5h → 7d → model → branch, in that order (R76 claims to compose R34; pin it)
  [[ "$output" =~ 📋.*5h.*7d.*Opus.*⎇ ]]
}

@test "status line: an absurd percentage is clamped with NO stderr spew (R7/R68, R76)" {
  # The line repaints every ~3s; a value that overflows the shell's integer compare would emit a
  # `[: integer expression expected` to stderr on every repaint AND print the raw number.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRLh",cwd:$c,
    rate_limits:{five_hour:{used_percentage:99999999999999999999999}}}')"
  local err; err="$(mktemp)"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2" 2>"$3"' _ "$payload" "$SL" "$err"
  [ "$status" -eq 0 ]
  [ ! -s "$err" ]                      # stderr completely empty
  [[ "$output" == *"100%"* ]]
  [[ "$output" != *"99999"* ]]
  rm -f "$err"
}

@test "status line: a sub-1% window is distinguishable from an idle one (R76)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sRLz",cwd:$c,
    rate_limits:{five_hour:{used_percentage:0.4},seven_day:{used_percentage:0}}}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"5h ▰▱▱▱▱ 0%"* ]]   # in use, just barely → one cell lit
  [[ "$output" == *"7d ▱▱▱▱▱ 0%"* ]]   # genuinely idle → none
}

@test "status line: a DRAINED queue renders no queue section at all (R80)" {
  # 📋 used to render permanently, even at 0 — the always-on zero that this line's own
  # shown-only-when-relevant rule exists to prevent (cf. 🛡✗, ✈️, 📦, ↑↓). The section reappearing
  # IS the signal that there is work; its divider goes too, so the line stays clean.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sDrained"
  jq -n '{id:"1",subject:"shipped",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/sDrained/1.json"
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"sDrained",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" != *"📋"* ]]           # no count...
  [[ "$output" != *"📋 0"* ]]         # ...and certainly not a zero
  [[ "$output" == *"Opus"* ]]         # the rest of the line is untouched
  # one open task and it comes straight back
  jq -n '{id:"2",subject:"real work",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sDrained/2.json"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$p" "$SL"
  [[ "$output" == *"📋 1"* ]]
}

@test "status line: the git segment is CACHED for its TTL, and a hit skips git entirely (R81)" {
  # `git status` walks the worktree every refresh — 6ms here, 43ms on a 17k-file repo — and the
  # line repaints ~1200x/hour per window. A hit must serve from the cache file, not re-run git.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"s1",cwd:$c}')"
  # first run: cold — populates the cache
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_COMPANION_SL_CACHE_TTL=60 "$2"' _ "$p" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"⎇"* ]]
  local enc cf; enc="$(printf '%s' "$repo" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  cf="$CLAUDE_COMPANION_STATE_DIR/slcache/$enc"
  [ -f "$cf" ]
  # dirty the tree; a WARM run must still show the cached (clean) count — staleness is the deal
  : > "$repo/newfile"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_COMPANION_SL_CACHE_TTL=60 "$2"' _ "$p" "$SL"
  [[ "$output" != *"*1"* ]]
  # ...and with the cache OFF the same tree reports the change immediately
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_COMPANION_SL_CACHE_TTL=0 "$2"' _ "$p" "$SL"
  [[ "$output" == *"*1"* ]]
}

@test "status line: a garbled or future-dated cache line falls back to LIVE git, never renders junk" {
  # Cache-miss is the safe direction (R7/R68). A truncated write, a clock jump, or a hand-edited
  # file must degrade to reading git — not print a corrupt branch or a negative count.
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local p enc cf; p="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"s1",cwd:$c}')"
  enc="$(printf '%s' "$repo" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  cf="$CLAUDE_COMPANION_STATE_DIR/slcache/$enc"; mkdir -p "$CLAUDE_COMPANION_STATE_DIR/slcache"
  for junk in "garbage" "" "abc def ghi jkl mno" "99999999999 0 0 0 fake-branch"; do
    printf '%s\n' "$junk" > "$cf"
    run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_COMPANION_SL_CACHE_TTL=60 "$2"' _ "$p" "$SL"
    [ "$status" -eq 0 ]
    [[ "$output" != *"fake-branch"* ]]   # a future-dated line is not trusted
    [[ "$output" == *"Opus"* ]]          # and the line still renders
  done
}

@test "status line: an unwritable state dir still renders — the cache is best-effort (R68)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local p; p="$(jq -nc --arg c "$repo" '{model:{display_name:"Opus"},session_id:"s1",cwd:$c}')"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 CLAUDE_COMPANION_SL_CACHE_TTL=60 CLAUDE_COMPANION_STATE_DIR=/proc/nonexistent "$2"' _ "$p" "$SL"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Opus"* ]]
  [[ "$output" == *"⎇"* ]]
}
