#!/usr/bin/env bats
#
# Tests for the companion's ENFORCED CORE — the only behavior that must execute or block
# (the steering layer is STEERING.md, prose the model reads; it isn't unit-testable, and
# pretending otherwise was the old system's mistake). Four things are real code: the secret
# gate, `tq` (THE queue — the companion owns its store; it does NOT use native tasks),
# SessionStart (steering + root-scoped resume), and the status line.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"; TOUCH="$ROOT/bin/touch.sh"
  AP="$ROOT/bin/autopilot.sh"; ASK="$ROOT/bin/ask-guard.sh"; STOP="$ROOT/bin/stop-autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  PROMPT="$ROOT/bin/prompt.sh"; WG="$ROOT/bin/work-guard.sh"; IN="$ROOT/bin/intent-note.sh"
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"   # autopilot flags live here
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

# ---- secret gate (the one enforced content block) ----

@test "secret gate: blocks a real AWS key (exit 2)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{file_path:\"/x/c.py\",content:\$c}}" | "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCKED"* ]]
}

@test "secret gate: blocks a generic secret literal (exit 2)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/c.py\",content:\"password = \\\"hunter2primetime\\\"\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 2 ]
}

@test "secret gate: allows a placeholder (exit 0)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/c.py\",content:\"API_KEY = \\\"your-key-here\\\"\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]
}

@test "secret gate: allows ordinary code (exit 0)" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/a.py\",content:\"def add(a,b): return a+b\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]
}

@test "secret gate: disabled via CLAUDE_COMPANION_SECSCAN=0" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'CLAUDE_COMPANION_SECSCAN=0 bash -c "jq -nc --arg c \"\$1\" \"{tool_input:{file_path:\\\"/x/c.py\\\",content:\\\$c}}\" | \"\$2\"" _ "$1" "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
}

# ---- tq (THE queue, companion-owned store) ----

@test "tq: add/doing/done write the companion store + stamp the repo root; report groups by state" {
  ( cd "$ROOT" && "$TQ" add "build it" "❓ pick a backend" ) >/dev/null
  [ -f "$CLAUDE_COMPANION_TASKS_DIR/s1/.root" ]                # session dir stamped with the repo root
  run jq -r '.subject + "|" + .status' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json"
  [ "$output" = "build it|pending" ]
  "$TQ" doing 1 >/dev/null
  [ "$(jq -r .status "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "in_progress" ]
  run "$TQ" done 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"#1 → completed"* ]]
  [[ "$output" == *"📋 Task queue"* ]]
  [[ "$output" == *"1 parked"* ]]
  [[ "$output" == *"✔ #1"* ]]
}

@test "tq: no session id errors cleanly" {
  run env -u CLAUDE_COMPANION_SESSION_ID -u CLAUDE_CODE_SESSION_ID "$TQ" add x
  [ "$status" -ne 0 ]
  [[ "$output" == *"session id"* ]]
}

# ---- session start (steering + root-scoped resume, no native transcript) ----

@test "session start: injects STEERING and resumes THIS repo's tasks only (scoped by .root)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sMine"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sMine/.root"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOther"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"

  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"new\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]   # STEERING injected
  [[ "$output" == *"resume me"* ]]           # this repo's task
  [[ "$output" != *"NOT MINE"* ]]            # no cross-repo bleed
}

@test "manual resume: lists THIS repo's open tasks on demand (and says so when none)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sM"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sM/.root"
  jq -n '{id:"1",subject:"pick me up",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/1.json"
  jq -n '{id:"2",subject:"already shipped",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pick me up"* ]]          # open task surfaced
  [[ "$output" != *"already shipped"* ]]     # completed excluded
  # a repo with nothing says so
  local empty; empty="$(mktemp -d)"; git -C "$empty" init -q
  run bash -c 'cd "$1" && "$2"' _ "$empty" "$RESUME"
  [[ "$output" == *"No carried-over"* ]]
}

# ---- status line (the glance surface) ----

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
  [[ "$output" == *"📋 2"* ]]           # 2 open (completed excluded)
  [[ "$output" == *"⎇"* ]]             # branch
}

@test "status line: 🛡✗ when the secret gate is disabled" {
  run bash -c 'printf "{}" | CLAUDE_COMPANION_SECSCAN=0 NO_COLOR=1 "$1"' _ "$SL"
  [[ "$output" == *"🛡✗"* ]]
}

@test "status line: shows 🎨/🔒 only when the R27 edit-gates are armed" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q; git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  local root; root="$(git -C "$repo" rev-parse --show-toplevel)"
  local payload; payload="$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"sG",cwd:$c}')"
  # idle → neither gate icon
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [[ "$output" != *"🎨"* ]]
  [[ "$output" != *"🔒"* ]]
  # design-preview armed → 🎨
  : > "$CLAUDE_COMPANION_STATE_DIR/design-sG"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [[ "$output" == *"🎨"* ]]
  # return-review armed (parked ❓, not yet presented) → 🔒
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sPk"; printf '%s' "$root" > "$CLAUDE_COMPANION_TASKS_DIR/sPk/.root"
  jq -n '{id:"1",subject:"❓ [parked] x",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sPk/1.json"
  run bash -c 'printf "%s" "$1" | NO_COLOR=1 "$2"' _ "$payload" "$SL"
  [[ "$output" == *"🔒"* ]]
}

# ---- clean-as-you-touch (PostToolUse: format + blast radius + size) ----

@test "touch: surfaces blast radius (dependents) and over-budget size" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  printf 'def helper(): pass\n' > "$repo/helper.py"
  printf 'from helper import helper\nhelper()\n' > "$repo/main.py"
  git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
  local i; for i in $(seq 1 305); do echo "# $i" >> "$repo/helper.py"; done
  run bash -c 'jq -nc --arg p "$1" "{tool_input:{file_path:\$p}}" | CLAUDE_COMPANION_SIZE_BUDGET=300 "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo/helper.py" "$TOUCH"
  [[ "$output" == *"blast radius"* ]]
  [[ "$output" == *"main.py"* ]]            # the dependent
  [[ "$output" == *"> 300"* ]]              # size flag
}

@test "autopilot: toggle persists, and is enforced (ask-guard deny + Stop auto-continue)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  [ "$(cd "$repo" && "$AP" status)" = "off" ]
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "on" ]                       # persisted flag

  # ask-guard DENIES AskUserQuestion while on
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.permissionDecision // \"allow\""' _ "$repo" "$ASK"
  [ "$output" = "deny" ]

  # Stop auto-continues while non-deferred work remains
  local sid=apT; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"do it",status:"pending"}'   > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"❓ decide",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s}" | "$3" | jq -r ".decision // \"allow\""' _ "$repo" "$sid" "$STOP"
  [ "$output" = "block" ]                                          # keeps draining

  # only ❓ deferred left → Stop allows (genuinely done)
  jq -n '{id:"1",subject:"do it",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s}" | "$3"' _ "$repo" "$sid" "$STOP"
  [ -z "$output" ]

  # off → ask-guard allows again
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2"' _ "$repo" "$ASK"
  [ -z "$output" ]
}

@test "autopilot: Stop yields after the no-progress cap (can't spin forever)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apC; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"stuck",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  # With MAX=3 and no task ever completing: stops 1-2 still block, the 3rd no-progress stop yields.
  local i r; for i in 1 2; do
    r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_MAX=3 "$STOP" | jq -r '.decision // "allow"')"
    [ "$r" = "block" ]                                             # no completion, but under the cap
  done
  r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_MAX=3 "$STOP")"
  [ -z "$r" ]                                                      # 3rd no-progress stop → yield
}

# ---- R27 gates: intent→outcome, design-preview, return-review ----

@test "prompt.sh: a visual prompt arms the design flag + records intent; a code prompt records intent only" {
  local sd="$CLAUDE_COMPANION_STATE_DIR"
  run bash -c 'jq -nc --arg p "$1" "{prompt:\$p,cwd:\"/x\",session_id:\"s1\"}" | "$2"' _ "restyle the navbar" "$PROMPT"
  [ "$status" -eq 0 ]
  [ -f "$sd/design-s1" ]                         # visual → design-preview armed
  [ "$(cat "$sd/intent-s1")" = "restyle the navbar" ]
  # a non-visual prompt clears the design flag and still records intent
  run bash -c 'jq -nc --arg p "$1" "{prompt:\$p,cwd:\"/x\",session_id:\"s1\"}" | "$2"' _ "fix the null deref in the parser" "$PROMPT"
  [ ! -f "$sd/design-s1" ]
  [ "$(cat "$sd/intent-s1")" = "fix the null deref in the parser" ]
}

@test "prompt.sh: slash/bang inputs are not work, and autopilot suppresses arming" {
  local sd="$CLAUDE_COMPANION_STATE_DIR" repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  run bash -c 'jq -nc "{prompt:\"/companion:audit\",cwd:\"/x\",session_id:\"s1\"}" | "$1"' _ "$PROMPT"
  [ ! -f "$sd/intent-s1" ]                       # a slash command isn't an intent of record
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{prompt:\"restyle the navbar\",cwd:\$c,session_id:\"s2\"}" | "$2"' _ "$repo" "$PROMPT"
  [ ! -f "$sd/design-s2" ] && [ ! -f "$sd/intent-s2" ]   # away → no gate arming
}

@test "work-guard: design gate blocks an edit until a wireframe is shown, then allows" {
  local sd="$CLAUDE_COMPANION_STATE_DIR" repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  : > "$sd/design-s1"                            # armed (as prompt.sh would on a visual prompt)
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\"}" | "$2" | jq -r ".hookSpecificOutput.permissionDecision // \"allow\""' _ "$repo" "$WG"
  [ "$output" = "deny" ]
  # presenting via AskUserQuestion (ask-guard, autopilot off) clears the flag
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\"}" | "$2"' _ "$repo" "$ASK"
  [ ! -f "$sd/design-s1" ]
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\"}" | "$2"' _ "$repo" "$WG"
  [ -z "$output" ]                               # no block → allow
}

@test "work-guard: return-review gate blocks until parked ❓ decisions are presented" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local root; root="$(git -C "$repo" rev-parse --show-toplevel)"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sP"; printf '%s' "$root" > "$CLAUDE_COMPANION_TASKS_DIR/sP/.root"
  jq -n '{id:"1",subject:"❓ [parked] pick a backend",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sP/1.json"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"sX\"}" | "$2" | jq -r ".hookSpecificOutput.permissionDecision // \"allow\""' _ "$repo" "$WG"
  [ "$output" = "deny" ]
  # presenting them (any AskUserQuestion while off) sets the review flag → gate clears
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"sX\"}" | "$2"' _ "$repo" "$ASK"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"sX\"}" | "$2"' _ "$repo" "$WG"
  [ -z "$output" ]                               # presented → allow
  # turning autopilot on re-arms the return contract for the NEXT return
  ( cd "$repo" && "$AP" on ) >/dev/null
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"sX\"}" | "$2" | jq -r ".hookSpecificOutput.permissionDecision // \"allow\""' _ "$repo" "$WG"
  [ "$output" = "deny" ]
}

@test "work-guard: gates never fire under autopilot or when disabled" {
  local sd="$CLAUDE_COMPANION_STATE_DIR" repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  : > "$sd/design-s1"
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\"}" | "$2"' _ "$repo" "$WG"
  [ -z "$output" ]                              # away → work-first, no block
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\"}" | CLAUDE_COMPANION_GATES=0 "$2"' _ "$repo" "$WG"
  [ -z "$output" ]                              # disabled → allow
}

@test "intent-note: advisory reminder surfaces the intent once per request, on the first edit" {
  local sd="$CLAUDE_COMPANION_STATE_DIR" repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  printf 'add a logout button' > "$sd/intent-s1"
  # first edit → reminder injected as PostToolUse additionalContext (no block)
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\",tool_input:{file_path:\"/x/a.js\"}}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$IN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"intent of record"* ]]
  [[ "$output" == *"add a logout button"* ]]
  [ -f "$sd/reminded-s1" ]                        # fired: marker set
  # subsequent edits in the same request stay silent
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\",tool_input:{file_path:\"/x/b.js\"}}" | "$2"' _ "$repo" "$IN"
  [ -z "$output" ]
  # a new prompt clears the marker (prompt.sh) → the next request's first edit reminds again
  run bash -c 'jq -nc --arg c "$1" "{prompt:\"rename the field\",cwd:\$c,session_id:\"s1\"}" | "$2"' _ "$repo" "$PROMPT"
  [ ! -f "$sd/reminded-s1" ]
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\",tool_input:{file_path:\"/x/a.js\"}}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$IN"
  [[ "$output" == *"rename the field"* ]]
}

@test "intent-note: silent under autopilot, when nothing recorded, and when disabled" {
  local sd="$CLAUDE_COMPANION_STATE_DIR" repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  # nothing recorded → nothing to say
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"sNone\",tool_input:{file_path:\"/x/a.js\"}}" | "$2"' _ "$repo" "$IN"
  [ -z "$output" ]
  printf 'do a thing' > "$sd/intent-s1"
  ( cd "$repo" && "$AP" on ) >/dev/null          # away → no recap for an absent owner
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\",tool_input:{file_path:\"/x/a.js\"}}" | "$2"' _ "$repo" "$IN"
  [ -z "$output" ]
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s1\",tool_input:{file_path:\"/x/a.js\"}}" | CLAUDE_COMPANION_GATES=0 "$2"' _ "$repo" "$IN"
  [ -z "$output" ]
}

@test "touch: silent on a small file with no dependents, and when disabled" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  printf 'print(1)\n' > "$repo/lonely.py"
  git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m init
  run bash -c 'jq -nc --arg p "$1" "{tool_input:{file_path:\$p}}" | "$2"' _ "$repo/lonely.py" "$TOUCH"
  [ -z "$output" ]                          # nothing to say
  # disabled → silent even when there would be findings
  local i; for i in $(seq 1 305); do echo "# $i" >> "$repo/lonely.py"; done
  run bash -c 'jq -nc --arg p "$1" "{tool_input:{file_path:\$p}}" | CLAUDE_COMPANION_TOUCH=0 "$2"' _ "$repo/lonely.py" "$TOUCH"
  [ -z "$output" ]
}
