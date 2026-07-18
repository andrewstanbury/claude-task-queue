#!/usr/bin/env bats
#
# Enforced core — the base behavior that must execute or block: the secret gate, `tq` (THE
# queue; the companion owns its store and does NOT use native tasks), SessionStart (steering +
# root-scoped resume), and persisted+enforced autopilot. (R27 edit-gates
# live in companion-gates.bats; the status line in companion-hud.bats.)

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"
  AP="$ROOT/bin/autopilot.sh"; ASK="$ROOT/bin/ask-guard.sh"; STOP="$ROOT/bin/stop-autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
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

@test "secret gate: a generic name=value literal WARNS but does not block (exit 0) — R32" {
  run bash -c 'jq -nc "{tool_input:{file_path:\"/x/c.py\",content:\"password = \\\"hunter2primetime\\\"\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]                          # heuristic no longer breaks the edit
  [[ "$output" == *"WARNING"* ]]              # but it does warn
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

# ---- per-repo feature toggles (R50): one unified surface, scoped per repo ----

@test "features: default list shows every capability, on by default (autopilot/ship off)" {
  run "$ROOT/bin/features.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret     on"* ]]
  [[ "$output" == *"steering   on"* ]]
  [[ "$output" == *"autopilot  off"* ]]
}

@test "features secret off: the gate ALLOWS in that repo but still BLOCKS elsewhere (per-repo, isolated)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo other; repo="$(mktemp -d)"; other="$(mktemp -d)"
  git -C "$repo" init -q; git -C "$other" init -q
  ( cd "$repo" && "$ROOT/bin/features.sh" secret off >/dev/null )
  # off in $repo → allowed
  run bash -c 'jq -nc --arg p "$1" --arg c "$2" "{tool_input:{file_path:\$p,content:\$c}}" | "$3"' _ "$repo/c.py" "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
  # still on in $other → blocked (no cross-repo bleed)
  run bash -c 'jq -nc --arg p "$1" --arg c "$2" "{tool_input:{file_path:\$p,content:\$c}}" | "$3"' _ "$other/c.py" "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  rm -rf "$repo" "$other"
}

@test "features secret off: warns that the gate is irreversible-harm" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2" secret off' _ "$repo" "$ROOT/bin/features.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SECRET GATE"* ]]
  rm -rf "$repo"
}

@test "secret gate FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS (R50/R54 never-fails-open)" {
  # Invariant (invisible to the user): only an exact ^secret=off$ line disables; corruption/typo -> gate ACTIVE.
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$ROOT/bin/features.sh" secret off >/dev/null )   # writes the flag at the enc path
  local flag; flag="$(find "${CLAUDE_COMPANION_STATE_DIR:?}/features" -type f 2>/dev/null | head -1)"
  [ -n "$flag" ]
  printf 'secret=off_typo\ngarbage\n' > "$flag"                     # NOT the exact ^secret=off$ line
  run bash -c 'jq -nc --arg p "$1" --arg c "$2" "{tool_input:{file_path:\$p,content:\$c}}" | "$3"' _ "$repo/c.py" "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]                                               # fail-safe: corrupt flag -> still blocks
  rm -rf "$repo"
}

@test "secret gate is self-contained: sources no lib (R50/R54 never-fails-open via a dependency)" {
  # The one enforced gate must not depend on lib/companion.sh — a broken dependency could make it fail open.
  run grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*companion\.sh' "$GUARD"
  [ "$status" -ne 0 ]
}

@test "features steering off: SessionStart drops the working agreement (resume/lessons unaffected)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$ROOT/bin/features.sh" steering off >/dev/null )
  run bash -c 'jq -nc --arg c "$1" "{source:\"startup\",cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.additionalContext"' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"working agreement"* ]]
  # turn back on → agreement returns
  ( cd "$repo" && "$ROOT/bin/features.sh" steering on >/dev/null )
  run bash -c 'jq -nc --arg c "$1" "{source:\"startup\",cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.additionalContext"' _ "$repo" "$SS"
  [[ "$output" == *"working agreement"* ]]
  rm -rf "$repo"
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
  [[ "$output" == *"#1 → completed"* ]]        # the state transition (behavioral, format-agnostic)
  [[ "$output" == *"📋"* ]]                     # a report is printed
  [[ "$output" == *"pick a backend"* ]]        # the parked sibling is surfaced (leading ❓ stripped)
  [[ "$output" != *"build it"* ]]              # completed task is count-only, not a full line (Design D, R47)
}

@test "tq: cancel retracts a task — cancelled, excluded from report counts, file kept (R32)" {
  ( cd "$ROOT" && "$TQ" add "wrong task" "keep me" ) >/dev/null
  run "$TQ" cancel 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"cancelled"* ]]
  [ "$(jq -r .status "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "cancelled" ]   # file kept for audit
  run "$TQ" report
  [[ "$output" != *"wrong task"* ]]        # retracted → not shown (no false ✔, no lingering ◻)
  [[ "$output" == *"keep me"* ]]           # the sibling remains
  # cancelled excluded from open — asserted at the store, not the header string (format-agnostic)
  [ "$(jq -s '[.[]|select(.status=="pending")]|length' "$CLAUDE_COMPANION_TASKS_DIR/s1"/*.json)" -eq 1 ]
}

@test "tq: writes go temp-file + mv, never in-place jq (R44 crash-safety)" {
  # Guards the atomic write idiom against a 'simplify to jq > $f' refactor that breaks crash-resume.
  [ "$(grep -Fc 'mv "$t" "$f"' "$ROOT/bin/tq")" -ge 2 ]         # set_task/append_note/done-when rename
  grep -Fq 'mv "$DIR/.$id.tmp" "$DIR/$id.json"' "$ROOT/bin/tq"  # add() renames too
}

@test "tq: no session id errors cleanly" {
  run env -u CLAUDE_COMPANION_SESSION_ID -u CLAUDE_CODE_SESSION_ID "$TQ" add x
  [ "$status" -ne 0 ]
  [[ "$output" == *"session id"* ]]
}

@test "tq: done-when — --done on add + the done-when subcommand STORE it; report omits it (D/R47, resurfaced on resume)" {
  ( cd "$ROOT" && "$TQ" add "wire export" --done "downloads a .csv" ) >/dev/null
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "downloads a .csv" ]   # stored in the task
  run "$TQ" report
  [[ "$output" == *"#1"*"wire export"* ]]                # the task is listed
  [[ "$output" != *"done when"* ]]                       # …but the compact report does NOT render done-when (Design D)
  ( cd "$ROOT" && "$TQ" add "plain" ) >/dev/null          # no --done → empty, no done-when line
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "" ]
  "$TQ" done-when 2 "no errors on load" >/dev/null         # set it after the fact
  [ "$(jq -r .done_when "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "no errors on load" ]
}

# ---- session start (steering + root-scoped resume, no native transcript) ----

@test "session start: injects STEERING and resumes THIS repo's tasks only (scoped by .root)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sMine"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sMine/.root"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOther"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"
  # this repo's LESSONS.md is surfaced (R30·d7)
  mkdir -p "$repo/docs"; printf 'GOTCHA_MARKER: brace vars before emoji\n' > "$repo/docs/LESSONS.md"

  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"new\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]     # STEERING injected
  [[ "$output" == *"resume me"* ]]             # this repo's task
  [[ "$output" != *"NOT MINE"* ]]              # no cross-repo bleed
  [[ "$output" == *"GOTCHA_MARKER"* ]]         # this repo's LESSONS surfaced
}

@test "session start: re-anchors on a compaction with queue+pointer, NOT the full STEERING — R30·d2 / R32" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/xc"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/xc/.root"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/xc/1.json"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"x\",source:\"compact\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"compacted"* ]]             # compaction-aware lead
  [[ "$output" == *"still applies"* ]]         # pointer to the session-start agreement
  [[ "$output" == *"resume me"* ]]             # the live queue is re-injected
  [[ "$output" != *"How we work"* ]]           # the full STEERING body is NOT re-pasted (token saving)
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

@test "manual resume: turns autopilot OFF first, announced when on and quiet when off (R39)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "on" ]                  # armed
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"autopilot was ON"* ]]                     # the flip is announced, not silent
  [ "$(cd "$repo" && "$AP" status)" = "off" ]                 # flag for THIS root actually cleared
  # second run: already off → quiet no-op, no autopilot notice
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"autopilot was ON"* ]]
}

# ---- autopilot (persisted + enforced: ask-guard deny · Stop auto-continue) ----

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

@test "ship-mode (R34): toggle, and Stop auto-commits work to an autopilot/* branch — NEVER main" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  [ "$(cd "$repo" && "$AP" ship status)" = "off" ]
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  [ "$(cd "$repo" && "$AP" ship status)" = "on" ]
  ( cd "$repo" && "$AP" on ) >/dev/null                      # auto-commit requires autopilot on too
  local sid=shipT; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"do it",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  printf 'work\n' > "$repo/newfile.txt"                      # uncommitted work while HEAD is on main
  jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" >/dev/null 2>&1 || true
  [ "$(git -C "$repo" branch --show-current)" != "main" ]    # moved off main to protect it
  git -C "$repo" branch | grep -q 'autopilot/'              # onto an autopilot/* branch
  [ -z "$(git -C "$repo" status --porcelain)" ]             # the work got committed (clean tree)
  git -C "$repo" log -1 --pretty=%s | grep -q 'autopilot: checkpoint'
  ! git -C "$repo" cat-file -e main:newfile.txt 2>/dev/null  # main NEVER received the work
}

@test "ship-mode: off → Stop does NOT auto-commit (work stays uncommitted)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ( cd "$repo" && "$AP" on ) >/dev/null                      # autopilot on, ship-mode OFF
  local sid=noShip; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"do it",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  printf 'work\n' > "$repo/newfile.txt"
  jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" >/dev/null 2>&1 || true
  [ "$(git -C "$repo" branch --show-current)" = "main" ]     # no branch created
  [ -n "$(git -C "$repo" status --porcelain)" ]             # work left uncommitted for the owner
}

@test "ship-mode: refuses to auto-commit a hardcoded credential (R34)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ( cd "$repo" && "$AP" ship on ) >/dev/null; ( cd "$repo" && "$AP" on ) >/dev/null
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  printf 'AWS = "%s"\n' "$k" > "$repo/creds.py"             # a real-shaped key in the work
  local sid=secT; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"x",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" >/dev/null 2>&1 || true
  ! git -C "$repo" log --all --oneline | grep -q 'autopilot: checkpoint'   # no checkpoint committed
  [ -n "$(git -C "$repo" status --porcelain)" ]            # the work (with the key) left uncommitted
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

# ---- decisions surfaced + recorded by /companion:document (R41) ----

@test "secret gate: covers NotebookEdit's new_source — key blocked, clean cell passes (R43)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{notebook_path:\"/x/n.ipynb\",new_source:\$c}}" | "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]                                       # NotebookEdit no longer bypasses the gate
  [[ "$output" == *"BLOCKED"* ]]
  run bash -c 'jq -nc "{tool_input:{notebook_path:\"/x/n.ipynb\",new_source:\"print(1+1)\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]                                       # a clean cell still passes
}

@test "parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value (R42)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=pkv; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"did it",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"❓ decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s}" | "$3"' _ "$repo" "$sid" "$STOP"
  [ -z "$output" ]                                          # a ❓ PENDING task counts as parked → Stop yields
  # drop the prefix → same pending task is now real open work → Stop blocks (keeps draining)
  jq -n '{id:"2",subject:"decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s}" | "$3" | jq -r ".decision // \"allow\""' _ "$repo" "$sid" "$STOP"
  [ "$output" = "block" ]                                   # so parked-ness lives in the prefix, not status
}

@test "ship-mode never commits to the default branch, even from detached HEAD (R45)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  git -C "$repo" checkout -q --detach 2>/dev/null           # detached HEAD (cur=="HEAD")
  ( cd "$repo" && "$AP" ship on ) >/dev/null; ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=det; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"x",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  printf 'work\n' > "$repo/newfile.txt"
  jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" >/dev/null 2>&1 || true
  git -C "$repo" branch | grep -q 'autopilot/'                    # moved onto an autopilot/* branch
  git -C "$repo" log -1 --pretty=%s | grep -q 'autopilot: checkpoint'  # a checkpoint WAS committed (non-vacuous)
  ! git -C "$repo" cat-file -e main:newfile.txt 2>/dev/null       # …but main NEVER received the work
}
