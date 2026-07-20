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
  CAP="$ROOT/bin/capture.sh"; DRIFT="$ROOT/bin/contract-drift.sh"   # R58 living contract
  export CLAUDE_COMPANION_TASKS_DIR="$(mktemp -d)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_STATE_DIR="$(mktemp -d)"   # autopilot flags live here
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

# Write a per-repo feature OFF flag directly at the reader's enc path (the `/companion:features`
# CLI was removed 2026-07-18; the flag mechanism + its readers remain — R50). Mirrors
# companion_feature_file(companion_root(repo)) so secret-guard / session-start / statusline find it.
_feature_off() {  # $1=feature  $2=repo-dir
  local root enc; root="$(git -C "$2" rev-parse --show-toplevel)"
  enc="$(printf '%s' "$root" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  mkdir -p "$CLAUDE_COMPANION_STATE_DIR/features"
  printf '%s=off\n' "$1" >> "$CLAUDE_COMPANION_STATE_DIR/features/$enc"
}
_feature_clear() { rm -f "$CLAUDE_COMPANION_STATE_DIR/features/"* 2>/dev/null || true; }

# ---- R61 anti-drift gate: the ONE matcher + extractor, shared by the gate AND its guard-test ----
# (Factored out so the guard actually exercises the real logic — a guard that re-implements a simpler
# check proves nothing about the gate. DA finding: fixed.)
# _ux_check_resolves FRAGMENT TITLES → 0 iff SOME title contains every ≥4-char …-segment of FRAGMENT.
# A fragment with no ≥4-char segment is UNRESOLVED (return 1), not a silent pass — an empty/too-short
# Check is itself drift, not coverage. Substring-not-exact is deliberate (Checks abbreviate with …);
# the honest ceiling: this proves the referenced test EXISTS + is wired to the row, not that a lazy
# 4-char coincidental substring is the *intended* test — the convention is a distinctive Check.
_ux_check_resolves() {
  local rest="$1" titles="$2" seg; local -a segs=()
  while [ -n "$rest" ]; do
    case "$rest" in *…*) seg="${rest%%…*}"; rest="${rest#*…}";; *) seg="$rest"; rest="";; esac
    seg="${seg#"${seg%%[![:space:]]*}"}"; seg="${seg%"${seg##*[![:space:]]}"}"
    [ "${#seg}" -ge 4 ] && segs+=("$seg")
  done
  [ "${#segs[@]}" -gt 0 ] || return 1
  local t ok; while IFS= read -r t; do ok=1
    for seg in "${segs[@]}"; do case "$t" in *"$seg"*) : ;; *) ok=0; break;; esac; done
    [ "$ok" = 1 ] && return 0
  done <<< "$titles"; return 1
}
# _ux_flow_check LINE → the backtick test-name from a flow page's Tests line, or nothing. A flow
# page (docs/flows/*.md, R62) lists tests as `- [E] `<test name>` ✅` (enforced → must resolve) or
# `- [S] … 👁` (judgment → skipped). The literal `- [E] ` prefix (matched literally via [[ == ]],
# NOT a case glob where [E] is a char-class) isolates Tests lines from every other `[E]` mention
# (headers, config bullets), so extraction can't stray. Robust to leading indentation.
_ux_flow_check() {
  local line="${1#"${1%%[![:space:]]*}"}"                  # strip leading whitespace
  [[ "$line" == '- [E] '* ]] || return 0                    # a Tests [E] line only
  printf '%s\n' "$line" | grep -oE '`[^`]*`' | head -1 || true
}

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

@test "secret gate: honors a per-repo secret=off flag — ALLOWS there but still BLOCKS elsewhere (isolated, R50/R54)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo other; repo="$(mktemp -d)"; other="$(mktemp -d)"
  git -C "$repo" init -q; git -C "$other" init -q
  _feature_off secret "$repo"
  # off in $repo → allowed
  run bash -c 'jq -nc --arg p "$1" --arg c "$2" "{tool_input:{file_path:\$p,content:\$c}}" | "$3"' _ "$repo/c.py" "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
  # still on in $other → blocked (no cross-repo bleed)
  run bash -c 'jq -nc --arg p "$1" --arg c "$2" "{tool_input:{file_path:\$p,content:\$c}}" | "$3"' _ "$other/c.py" "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  rm -rf "$repo" "$other"
}

@test "secret gate FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS (R50/R54 never-fails-open)" {
  # Invariant (invisible to the user): only an exact ^secret=off$ line disables; corruption/typo -> gate ACTIVE.
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  _feature_off secret "$repo"                                      # writes the flag at the enc path
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

@test "steering off (per-repo flag): SessionStart drops the working agreement (resume/lessons unaffected, R50)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  _feature_off steering "$repo"
  run bash -c 'jq -nc --arg c "$1" "{source:\"startup\",cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.additionalContext"' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" != *"working agreement"* ]]
  # clear the flag → agreement returns (default ON)
  _feature_clear
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

@test "bin/lib scripts use no bash-4-only builtins — macOS CI runs bash 3.2 (regression guard)" {
  # mapfile/readarray are Bash 4+; macOS CI's /bin/bash is 3.2, but a dev on bash 5 won't see the
  # failure locally — it shipped red once (R60 used mapfile in tq). Grep the enforced-core scripts
  # for the builtins as invoked; if any appears, CI on macOS will `command not found`.
  run grep -rnE '(mapfile|readarray)' "$ROOT/bin" "$ROOT/lib"
  [ "$status" -ne 0 ]                                # no match → grep exits non-zero → clean
}

@test "tq: writes go temp-file + mv, never in-place jq (R44 crash-safety)" {
  # Guards the atomic write idiom against a 'simplify to jq > $f' refactor that breaks crash-resume.
  [ "$(grep -Fc 'mv "$t" "$f"' "$ROOT/bin/tq")" -ge 2 ]         # set_task/append_note/done-when rename
  grep -Fq 'mv "$DIR/.$id.tmp" "$DIR/$id.json"' "$ROOT/bin/tq"  # add() renames too
}

@test "tq export/import (R60): carries the open queue to a NEW clone path, re-stamped + idempotent" {
  # Machine A: open + in_progress + parked + one completed (the completed must NOT travel).
  local A; A="$(mktemp -d)"; git -C "$A" init -q
  ( cd "$A" && "$TQ" add "build widget" --done "widget works" ) >/dev/null
  ( cd "$A" && "$TQ" add "❓ pick color" ) >/dev/null
  ( cd "$A" && "$TQ" doing 1 ) >/dev/null
  ( cd "$A" && "$TQ" add "already done" ) >/dev/null
  ( cd "$A" && "$TQ" done 3 ) >/dev/null
  run bash -c "cd '$A' && '$TQ' export"
  [ "$status" -eq 0 ]
  [ -f "$A/.companion/queue.json" ]
  [ "$(jq 'length' "$A/.companion/queue.json")" -eq 2 ]          # open only, completed excluded
  run grep -F "$A" "$A/.companion/queue.json"                    # content is path-free (clone-agnostic)
  [ "$status" -ne 0 ]
  [ "$(jq -r '[.[]|select(.subject=="build widget")][0].status' "$A/.companion/queue.json")" = "in_progress" ]

  # Machine B: DIFFERENT clone path, DIFFERENT store + session id (a fresh machine after git pull).
  local B storeB; B="$(mktemp -d)"; storeB="$(mktemp -d)"; git -C "$B" init -q
  mkdir -p "$B/.companion"; cp "$A/.companion/queue.json" "$B/.companion/queue.json"
  run env CLAUDE_COMPANION_TASKS_DIR="$storeB" CLAUDE_COMPANION_SESSION_ID="sB" \
      bash -c "cd '$B' && '$TQ' import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added 2"* ]]
  # re-stamped under B's OWN path — the fix that makes resume path-tolerant across clones
  [ "$(cat "$storeB/sB/.root")" = "$(git -C "$B" rev-parse --show-toplevel)" ]
  [ "$(jq -s '[.[]|select(.status!="completed")]|length' "$storeB/sB"/*.json)" -eq 2 ]

  run env CLAUDE_COMPANION_TASKS_DIR="$storeB" CLAUDE_COMPANION_SESSION_ID="sB" \
      bash -c "cd '$B' && '$TQ' import"                          # idempotent — re-run adds nothing
  [[ "$output" == *"added 0"* ]]
  rm -rf "$A" "$B" "$storeB"
}

@test "tq import (R60): dedups across ALL statuses — a task completed here is not resurrected" {
  local A; A="$(mktemp -d)"; git -C "$A" init -q
  mkdir -p "$A/.companion"
  jq -n '[{subject:"task X",status:"pending",done_when:"",description:"",notes:[]}]' > "$A/.companion/queue.json"
  ( cd "$A" && "$TQ" add "task X" ) >/dev/null                   # but on THIS machine it's already done
  ( cd "$A" && "$TQ" done 1 ) >/dev/null
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added 0"* ]]                                 # completed subject → not re-added
  [ "$(jq -s '[.[]|select(.subject=="task X")]|length' "$CLAUDE_COMPANION_TASKS_DIR/s1"/*.json)" -eq 1 ]
  [ "$(jq -r '.status' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "completed" ]
  rm -rf "$A"
}

@test "tq export (R60): one corrupt task file is skipped, the backlog is NOT zeroed (R44-class robustness)" {
  local A; A="$(mktemp -d)"; git -C "$A" init -q
  ( cd "$A" && "$TQ" add "good one" ) >/dev/null
  ( cd "$A" && "$TQ" add "good two" ) >/dev/null
  printf '{half-written' > "$CLAUDE_COMPANION_TASKS_DIR/s1/99.json"   # a crash-mangled file
  run bash -c "cd '$A' && '$TQ' export"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped 1 unreadable"* ]]                        # surfaced, not silent
  [ "$(jq 'length' "$A/.companion/queue.json")" -eq 2 ]             # both good tasks survive
  [ ! -e "$A/.companion/queue.json.tmp" ]; [ ! -e "$A/.companion/queue.json.parts" ]  # no litter
  rm -rf "$A"
}

@test "tq import (R60): two DISTINCT tasks sharing a subject line both import (no subject-collision collapse)" {
  local A; A="$(mktemp -d)"; git -C "$A" init -q; mkdir -p "$A/.companion"
  jq -n '[{subject:"fix bug",status:"pending",done_when:"auth",description:"",notes:[]},
          {subject:"fix bug",status:"pending",done_when:"upload",description:"",notes:[]}]' > "$A/.companion/queue.json"
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added 2"* ]]
  [ "$(jq -s 'length' "$CLAUDE_COMPANION_TASKS_DIR/s1"/*.json)" -eq 2 ]
  rm -rf "$A"
}

@test "tq import (R60): refuses when the session is bound to a DIFFERENT repo (no wrong-.root landing)" {
  local A; A="$(mktemp -d)"; git -C "$A" init -q; mkdir -p "$A/.companion"
  jq -n '[{subject:"x",status:"pending",done_when:"",notes:[]}]' > "$A/.companion/queue.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/s1"; printf '/some/other/repo' > "$CLAUDE_COMPANION_TASKS_DIR/s1/.root"
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -ne 0 ]                                                # refused
  [[ "$output" == *"bound to /some/other/repo"* ]]
  [ ! -e "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json" ]                  # nothing landed
  rm -rf "$A"
}

@test "tq import (R60): a merge-conflicted queue.json is a LOUD no-op, not a silent one" {
  local A; A="$(mktemp -d)"; git -C "$A" init -q; mkdir -p "$A/.companion"
  printf '<<<<<<< HEAD\n[]\n=======\n[]\n>>>>>>>\n' > "$A/.companion/queue.json"
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a readable JSON array"* ]]
  rm -rf "$A"
}

@test "command prompts retain their critical gate steps (R56 P3 — structural guard for prose)" {
  # Prose behavior can't be tested behaviorally (it's Claude's judgment, R28); the ceiling is a
  # structural guard that a command's non-negotiable gate INSTRUCTION wasn't deleted (like a regen
  # of a .md might do). Catches deletion, not a subtler regression — the honest best for prose.
  local C="$ROOT/commands"
  grep -q "invariant net covers the app"   "$C/redesign.md"     # D0 coverage gate
  grep -qE "bounded, check-gated|never.*unbounded" "$C/redesign.md"  # D2/D3 bounded passes
  grep -q 'autopilot.sh" off'              "$C/redesign.md"     # step-0 autopilot clear
  grep -q "auto-revert"                    "$C/redesign.md"     # R5 rollback-on-red (inlined regen engine)
  grep -qE "Refuse to (regenerate|proceed)" "$C/redesign.md"    # R3 checks-first + D1 document gate
  grep -q "REQUIRED first step"            "$C/redesign.md"     # D1 document-first requirement (R55)
  grep -q "Verify FIRST"                   "$C/ship-it.md"      # verify before commit
  grep -q "Never force-push"               "$C/ship-it.md"      # never rewrite published history
  grep -q "Sync the contract"              "$C/ship-it.md"      # R57 contract-sync step
  grep -q "Propose the flow-page update"   "$C/ship-it.md"      # R57/R62 flow-page proposal (owner-governed, not silent)
  grep -q "anti-laundering"                "$C/document.md"     # only the owner's pick records a 🔒
  grep -q "autopilot"                      "$C/resume.md"       # resume respects/clears autopilot
  grep -q "resume.sh"                       "$C/resume.md"       # resume runs the session-pickup re-surface (R39)
  grep -q "companion:review"               "$C/resume.md"       # pickup hands off to review (R39 re-split)
  grep -qE "parked|❓"                       "$C/review.md"       # review walks the parked pile (R38)
  grep -q 'autopilot.sh" off'              "$C/review.md"       # review clears autopilot (it asks)
  grep -qiE "before .*new work"            "$C/review.md"       # R38 write-back-before-new-work
  grep -qiE "asks before it writes|buy-in still comes first|recommendation-first" "$C/cover.md"  # R58·d amended by R61/R62: cover SCAFFOLDS, but buy-in (owner picks) still precedes any write
  grep -q 'autopilot.sh" off'              "$C/cover.md"        # cover clears autopilot (it asks)
}

@test "docs/flows index lists every shipped command + the count matches (contract can't silently drift)" {
  # The flows index is the R54 contract pillar a regen reproduces; if a command is added without an
  # entry, a regen reproduces the WRONG surface. This is the guard that caught the 8-vs-10 drift.
  local repo idx; repo="$(cd "$ROOT/../.." && pwd)"; idx="$repo/docs/flows/README.md"
  [ -f "$idx" ]
  local f name n=0
  for f in "$ROOT/commands"/*.md; do
    name="$(basename "$f" .md)"
    grep -q "companion:$name" "$idx"       # every shipped command must appear in the flows index
    n=$((n+1))
  done
  grep -q "Slash commands ($n)" "$idx"     # and the stated count matches reality
}

@test "docs/flows: every [E] flow test resolves to a real @test (anti-drift gate — R61/R62)" {
  # THE gate: a flow page's `- [E] `<name>`` Tests line names a backtick substring of a real bats
  # @test title — the machine-readable link from a documented user experience to the test that proves
  # it. If that test is renamed/deleted, the flow page silently lies, and a golden/happy-path test
  # built from the contract LATER would chase a ghost (the exact drift to avoid). This FAILS the build
  # the moment a referenced test stops resolving. Honest gaps ([S] judgment lines, 👁) are skipped,
  # not failed — coverage stays truthful. (bats proves the test PASSES; this proves it EXISTS + is
  # wired to the flow.) Uses the shared _ux_* helpers — the same code the guard-test runs.
  local repo titles; repo="$(cd "$ROOT/../.." && pwd)"
  [ -d "$repo/docs/flows" ]; titles="$(grep -h '^@test' "$ROOT/tests"/*.bats)"
  local f line frag s; local -a bad=()
  for f in "$repo"/docs/flows/*.md; do [ -f "$f" ] || continue
    while IFS= read -r line; do
      frag="$(_ux_flow_check "$line")"; [ -n "$frag" ] || continue
      s="${frag#\`}"; s="${s%\`}"; [ -n "$s" ] || continue
      _ux_check_resolves "$s" "$titles" || bad+=("$(basename "$f"): $s")
    done < "$f"
  done
  if [ "${#bad[@]}" -gt 0 ]; then printf 'flow [E] test resolves to no @test:\n'; printf '  - %s\n' "${bad[@]}"; false; fi
}

@test "docs/flows anti-drift gate FAILS on a phantom test + PASSES a real one — via the real matcher (R61/R62)" {
  # Guards the guard: a gate that can't fail is theater. This drives fixture lines through the SAME
  # _ux_flow_check + _ux_check_resolves the real gate uses (not a re-implemented proxy), proving the
  # matcher rejects a phantom AND accepts a real name — so it can't be silently stuck always-pass or
  # always-fail. Also covers the silent-skip edge: a leading-indented Tests line must still be gated.
  local titles; titles="$(grep -h '^@test' "$ROOT/tests"/*.bats)"
  local frag s; _check() { local r="$1"                # returns 0 iff the line's [E] test resolves
    frag="$(_ux_flow_check "$r")"; [ -n "$frag" ] || return 1
    s="${frag#\`}"; s="${s%\`}"; _ux_check_resolves "$s" "$titles"; }
  ! _check '- [E] `this test absolutely does not exist xyzzy`'   # phantom → unresolved
  _check '- [E] `secret gate: blocks a real AWS key (exit 2)`'    # real → resolves (not always-fail)
  ! _check '   - [E] `another phantom qqq nonexistent`'          # indented phantom still reaches matcher
  ! _check '- [S] `secret gate: blocks a real AWS key (exit 2)`' # an [S] line is NOT gated (skipped)
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

# ---- R56 P2: characterization tests for beacon-class gaps the coverage audit found ----
# (intended, load-bearing behaviors a green from-scratch regen would silently drop)

@test "autopilot: the Stop block REASON carries the nudge — next #id, done-when, both park tokens (R56 G1)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apR; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"7",subject:"real work",status:"pending",done_when:"it works"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/7.json"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s}" | "$3" | jq -r ".reason // \"\""' _ "$repo" "$sid" "$STOP"
  [[ "$output" == *"#7"* ]]                    # names the next task id
  [[ "$output" == *"done when: it works"* ]]   # carries its acceptance criterion
  [[ "$output" == *"❓ [parked]"* ]]           # the park-a-decision instruction
  [[ "$output" == *"⏳ [blocked]"* ]]          # the block-an-owner-action instruction
  [[ "$output" == *"DO NOT stop"* ]]           # the keep-going instruction
}

@test "resume: carried tasks render the done-when + LATEST note sub-lines (R56 G2 — R47/PR126 resume enrichment)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  local sid=rEn; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"carry me",status:"pending",done_when:"green tests",notes:[{ts:"t1",text:"first crumb"},{ts:"t2",text:"latest crumb"}]}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carry me"* ]]                 # the task surfaces
  [[ "$output" == *"done when: green tests"* ]]   # acceptance re-surfaced (the R47 resume side)
  [[ "$output" == *"note: latest crumb"* ]]       # LATEST note (PR #126), not the first
  [[ "$output" != *"note: first crumb"* ]]        # only the latest, not the whole trail
}

@test "tq report: glyph-count header + → next pointer (R56 G3/G4 — R47 spec)" {
  ( cd "$ROOT" && "$TQ" add "task one" ) >/dev/null
  ( cd "$ROOT" && "$TQ" add "task two" ) >/dev/null
  run bash -c 'cd "$1" && "$2" report' _ "$ROOT" "$TQ"
  [[ "$output" == *"📋"* ]]                 # the glyph-count header line
  [[ "$output" == *"◻2"* ]]                 # 2 open, counted in the header
  [[ "$output" == *"→ next: #1"* ]]         # pointer = head of the open queue
  ( cd "$ROOT" && "$TQ" doing 2 ) >/dev/null
  run bash -c 'cd "$1" && "$2" report' _ "$ROOT" "$TQ"
  [[ "$output" == *"▸1"* ]]                 # 1 in-progress, counted
  [[ "$output" == *"→ next: #2"* ]]         # the in-progress task becomes next
}

@test "tq note: appends to .notes[] cumulatively, never overwrites (R56 G4 — PR #126)" {
  ( cd "$ROOT" && "$TQ" add "with notes" ) >/dev/null
  ( cd "$ROOT" && "$TQ" note 1 "first" ) >/dev/null
  ( cd "$ROOT" && "$TQ" note 1 "second" ) >/dev/null
  local f; f="$(ls "$CLAUDE_COMPANION_TASKS_DIR"/*/1.json | head -1)"
  [ "$(jq '.notes | length' "$f")" -eq 2 ]            # both breadcrumbs kept (not overwritten)
  [ "$(jq -r '.notes[0].text' "$f")" = "first" ]      # first preserved
  [ "$(jq -r '.notes[1].text' "$f")" = "second" ]     # second appended after it
}

@test "ask-guard: the deny REASON carries park-with-full-options guidance (R56 G5)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.permissionDecisionReason // \"\""' _ "$repo" "$ASK"
  [[ "$output" == *"PARK"* ]]                # instructs to park, not answer
  [[ "$output" == *"❓ [parked]"* ]]         # with the park token + full payload
  [[ "$output" == *"options"* ]]             # carry the options
  [[ "$output" == *"rec"* ]]                 # + a recommendation
}

@test "autopilot decisive (R59): toggle persists, and flips the ask-guard guidance park→decide" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "off" ]           # off by default
  ( cd "$repo" && "$AP" decisive on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "on" ]            # persisted flag
  # still DENIES (asking = stopping), but the guidance now says DECIDE reversible + park only irreversible
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2"' _ "$repo" "$ASK"
  [[ "$output" == *'"permissionDecision":"deny"'* ]]
  local reason; reason="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')"
  [[ "$reason" == *"DECISIVE"* ]]
  [[ "$reason" == *"pick your own recommended option"* ]]        # auto-decide reversible
  [[ "$reason" == *"IRREVERSIBLE"* ]]                            # park ONLY irreversible-critical
  [[ "$reason" != *"belongs to the owner"* ]]                    # the R33 always-park-taste line is overridden
  # decisive is a no-op without autopilot on (it's an intensity ON TOP of autopilot)
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2"' _ "$repo" "$ASK"
  [[ "$output" != *"deny"* ]]                                    # autopilot off → ask-guard silent (no deny) regardless of decisive
}

@test "tq: stamps the session .root with the actual git toplevel (R56 G8 — cross-session scope)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$TQ" add "scoped" ) >/dev/null
  # not just that .root exists (already pinned) — that it holds the CORRECT root, else resume mis-scopes
  [ "$(cat "$CLAUDE_COMPANION_TASKS_DIR/s1/.root")" = "$(git -C "$repo" rev-parse --show-toplevel)" ]
}

@test "session start: the compaction re-anchor keeps the recommendation-contract clause (R56 G3 — R49)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" "{source:\"compact\",cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.additionalContext // \"\""' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation-first"* ]]   # the R49 posture must survive a compaction summary (its whole purpose)
}


@test "secret gate: blocks non-AWS anchored keys too — GH/Slack/Stripe/Google/PEM (R56 — INVARIANTS claim)" {
  # INVARIANTS.md claims six-vendor coverage but only AKIA was ever exercised. Construct each shape
  # at runtime (never a literal key in this file) so gitleaks doesn't flag the test itself.
  local pad; pad="$(printf 'a%.0s' $(seq 40))"                         # 40 alnum, ≥ each prefix's min run
  local ghp="ghp""_$pad" xox="xox""b-$pad" sk="sk_""live_$pad"
  local aiza="AIza$(printf 'a%.0s' $(seq 35))" pem="-----BEGIN ""PRIVATE KEY-----"
  for k in "$ghp" "$xox" "$sk" "$aiza" "$pem"; do
    run bash -c 'jq -nc --arg p "/x/c.txt" --arg c "$1" "{tool_input:{file_path:\$p,content:\$c}}" | "$2"' _ "SECRET=\"$k\"" "$GUARD"
    [ "$status" -eq 2 ]                        # every recognised vendor shape blocks (exit 2), not just AWS
  done
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

@test "autopilot: the no-progress cap RESETS when a task completes — a productive drain keeps going (R56 G5)" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apRst; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"a",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"b",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  local i r
  for i in 1 2; do   # two no-progress stops → stall 2, one below MAX=3
    r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_MAX=3 "$STOP" | jq -r '.decision // "allow"')"
    [ "$r" = "block" ]
  done
  # a task completes → progress made → the next stop RESETS the counter and still BLOCKS (open work remains)
  jq -n '{id:"1",subject:"a",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_MAX=3 "$STOP" | jq -r '.decision // "allow"')"
  [ "$r" = "block" ]   # without the reset this 3rd stop would YIELD; it blocks because a task completed
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

# ---- living contract (R58): capture write-only + drift backstop ----

@test "capture: banks the prompt, injects nothing" {
  local repo; repo="$(mktemp -d)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" --arg p "$2" "{cwd:\$c,prompt:\$p}" | "$3"' _ "$repo" "add a /companion:cover command" "$CAP"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                          # WRITE-ONLY: nothing to stdout (no additionalContext) — N1
  local enc; enc="$(printf '%s' "$(git -C "$repo" rev-parse --show-toplevel)" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  local store="$CLAUDE_COMPANION_STATE_DIR/captures/$enc/prompts.jsonl"
  [ -f "$store" ]                                           # …the prompt WAS banked to the per-repo store
  [ "$(jq -r .prompt "$store")" = "add a /companion:cover command" ]
  # garbage stdin is a clean no-op (best-effort, R7)
  run bash -c 'printf "%s" "not json" | "$1"' _ "$CAP"; [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "contract-drift: warns when behaviour changed without a contract doc, silent otherwise (R58)" {
  local repo; repo="$(mktemp -d)"
  git -C "$repo" init -q; git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  mkdir -p "$repo/docs/flows" "$repo/src"; printf 'x\n' > "$repo/src/app"; printf '# flow\n' > "$repo/docs/flows/upload.md"
  git -C "$repo" add -A; git -C "$repo" commit -qm init
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"          # clean tree
  [ "$status" -eq 0 ]; [ -z "$output" ]                     # nothing changed → silent
  printf 'more\n' >> "$repo/src/app"                         # behaviour changed, no contract doc
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"
  [ "$status" -eq 0 ]; [[ "$output" == *"contract-drift"* ]]; [[ "$output" == *"src/app"* ]]
  printf 'step\n' >> "$repo/docs/flows/upload.md"            # now the contract moved too (a flow page, R62)
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"
  [ "$status" -eq 0 ]; [ -z "$output" ]                     # contract touched → no drift
  printf 'note\n' >> "$repo/docs/MAP.md"; git -C "$repo" checkout -q -- src/app docs/flows/upload.md
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$DRIFT"          # docs-only change is never "behaviour"
  [ "$status" -eq 0 ]; [ -z "$output" ]
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
