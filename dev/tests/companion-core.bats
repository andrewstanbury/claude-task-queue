#!/usr/bin/env bats
#
# Enforced core — the base behavior that must execute or block: the secret gate, `tq` (THE
# queue; the companion owns its store and does NOT use native tasks), SessionStart (steering +
# root-scoped resume), and persisted+enforced autopilot. (R27 edit-gates
# live in companion-gates.bats; the status line in companion-hud.bats.)

# Fixture dirs go under BATS_TEST_TMPDIR, which bats removes after each test. Plain `mktemp -d`
# leaks: one session of this suite left 37,000 directories in /tmp and exhausted the inode table,
# which then fails unrelated tests for reasons that look like code defects.
_tmpd() { mktemp -d "$BATS_TEST_TMPDIR/d.XXXXXX"; }

setup() {
  # Tests live in dev/ and are NOT shipped. ROOT still means the SHIPPED plugin dir; DEV is
  # where the gates that verify it live. Keeping the two named apart is the point of the split.
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../plugins/companion" && pwd)"
  DEV="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/secret-guard.sh"; TQ="$ROOT/bin/tq"; SS="$ROOT/bin/session-start.sh"; SL="$ROOT/bin/statusline.sh"
  AP="$ROOT/bin/autopilot.sh"; ASK="$ROOT/bin/ask-guard.sh"; STOP="$ROOT/bin/stop-autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  DRIFT="$ROOT/bin/contract-drift.sh"   # R58 living contract (drift backstop)
  export CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_STATE_DIR="$(_tmpd)"   # autopilot flags live here
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
  local repo other; repo="$(_tmpd)"; other="$(_tmpd)"
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local A; A="$(_tmpd)"; git -C "$A" init -q
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
  local B storeB; B="$(_tmpd)"; storeB="$(_tmpd)"; git -C "$B" init -q
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
  local A; A="$(_tmpd)"; git -C "$A" init -q
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
  local A; A="$(_tmpd)"; git -C "$A" init -q
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
  local A; A="$(_tmpd)"; git -C "$A" init -q; mkdir -p "$A/.companion"
  jq -n '[{subject:"fix bug",status:"pending",done_when:"auth",description:"",notes:[]},
          {subject:"fix bug",status:"pending",done_when:"upload",description:"",notes:[]}]' > "$A/.companion/queue.json"
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added 2"* ]]
  [ "$(jq -s 'length' "$CLAUDE_COMPANION_TASKS_DIR/s1"/*.json)" -eq 2 ]
  rm -rf "$A"
}

@test "tq import (R60): refuses when the session is bound to a DIFFERENT repo (no wrong-.root landing)" {
  local A; A="$(_tmpd)"; git -C "$A" init -q; mkdir -p "$A/.companion"
  jq -n '[{subject:"x",status:"pending",done_when:"",notes:[]}]' > "$A/.companion/queue.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/s1"; printf '/some/other/repo' > "$CLAUDE_COMPANION_TASKS_DIR/s1/.root"
  run bash -c "cd '$A' && '$TQ' import"
  [ "$status" -ne 0 ]                                                # refused
  [[ "$output" == *"bound to /some/other/repo"* ]]
  [ ! -e "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json" ]                  # nothing landed
  rm -rf "$A"
}

@test "tq import (R60): a merge-conflicted queue.json is a LOUD no-op, not a silent one" {
  local A; A="$(_tmpd)"; git -C "$A" init -q; mkdir -p "$A/.companion"
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
  grep -q "anti-laundering"                "$C/docs.md"     # only the owner's pick records a 🔒
  grep -q "autopilot"                      "$C/resume.md"       # resume respects/clears autopilot
  grep -q "resume.sh"                       "$C/resume.md"       # resume runs the session-pickup re-surface (R39)
  grep -q "companion:review"               "$C/resume.md"       # pickup hands off to review (R39 re-split)
  grep -qE "parked|❓"                       "$C/review.md"       # review walks the parked pile (R38)
  # R83: review PAUSES rather than kills — it must disarm to ask, then put autopilot back. Both
  # halves are load-bearing: pause without resume is the old behaviour with extra steps, and the
  # guard has to pin the pair or the resume can quietly disappear.
  grep -q 'autopilot.sh" pause'            "$C/review.md"       # review disarms to ask (R83)
  grep -q 'autopilot.sh" resume'           "$C/review.md"       # ...and re-arms when done (R83)
  grep -qiE "up front|upfront"             "$C/review.md"       # the whole pile at once, not drip-fed
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
  [ -d "$repo/docs/flows" ]; titles="$(grep -h '^@test' "$DEV/tests"/*.bats)"
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
  local titles; titles="$(grep -h '^@test' "$DEV/tests"/*.bats)"
  local frag s; _check() { local r="$1"                # returns 0 iff the line's [E] test resolves
    frag="$(_ux_flow_check "$r")"; [ -n "$frag" ] || return 1
    s="${frag#\`}"; s="${s%\`}"; _ux_check_resolves "$s" "$titles"; }
  ! _check '- [E] `this test absolutely does not exist xyzzy`'   # phantom → unresolved
  _check '- [E] `secret gate: blocks a real AWS key (exit 2)`'    # real → resolves (not always-fail)
  ! _check '   - [E] `another phantom qqq nonexistent`'          # indented phantom still reaches matcher
  ! _check '- [S] `secret gate: blocks a real AWS key (exit 2)`' # an [S] line is NOT gated (skipped)
}

@test "resume survives a repo MOVE — scoping keys on a per-worktree identity, not the abspath (R63)" {
  # The papercut in path-scoping: move the repo and your carried queue silently vanishes (the abspath
  # .root no longer matches). tq now also stamps .repo (a per-working-tree id in the tree's git dir,
  # which moves WITH the tree), and companion_open_tasks matches on it, so a move no longer hides tasks.
  local a b; a="$(_tmpd)/proj"; mkdir -p "$a"; git -C "$a" init -q
  ( cd "$a" && "$TQ" add "carry me" ) >/dev/null
  [ -f "$CLAUDE_COMPANION_TASKS_DIR/s1/.repo" ]                       # identity stamp written
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$a" "$ROOT"
  [[ "$output" == *"carry me"* ]]                                     # found at the original path
  b="$(_tmpd)/moved"; mkdir -p "$(dirname "$b")"; mv "$a" "$b"    # MOVE to a different abspath
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$b" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carry me"* ]]                                     # STILL found after the move
  rm -rf "$(dirname "$b")"
}

@test "resume ISOLATES git worktrees — same history, separate trees, separate queues (R63: not root-SHA)" {
  # A worktree (or clone/fork) shares the root commit but is a DISTINCT working tree; its queue must
  # stay separate (the "no cross-project task bleed" invariant). Identity is a per-worktree tag, NOT
  # the root-SHA — which would collide worktrees/clones and merge their queues (a devil's-advocate catch).
  local main wt; main="$(_tmpd)/main"; mkdir -p "$main"; git -C "$main" init -q
  git -C "$main" -c user.email=t@t -c user.name=t commit -q --allow-empty -m root
  ( cd "$main" && "$TQ" add "main-tree task" ) >/dev/null
  wt="$(_tmpd)/feature"; git -C "$main" worktree add -q "$wt" 2>/dev/null
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$main" "$ROOT"
  [[ "$output" == *"main-tree task"* ]]                               # the main tree sees its task
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$wt" "$ROOT"
  [[ "$output" != *"main-tree task"* ]]                               # the worktree does NOT — isolated
  git -C "$main" worktree remove --force "$wt" 2>/dev/null || true
  rm -rf "$(dirname "$main")" "$(dirname "$wt")"
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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

@test "session start: injects the STEERING CORE only — rationale below the marker excluded; missing marker fails OPEN (R69)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s69\"}" | "$2" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core is injected…
  [[ "$output" == *"Posture"* ]]                   # …through its last section
  [[ "$output" != *"Rationale (not injected"* ]]   # the below-marker half NEVER ships
  [[ "$output" != *"injection stops here"* ]]      # the marker line itself is excluded too
  # Fail-open (R7): a STEERING with no marker (old copy, botched edit) injects the WHOLE doc —
  # degraded-but-working beats silently steering-less. Build a marker-less plugin dir to prove it.
  local plug; plug="$(_tmpd)"; mkdir -p "$plug/bin" "$plug/lib"
  cp "$SS" "$plug/bin/session-start.sh"; cp "$ROOT/lib/companion.sh" "$plug/lib/"
  sed '/injection stops here/d' "$ROOT/STEERING.md" > "$plug/STEERING.md"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"s69b\"}" | "$2/bin/session-start.sh" | jq -r .hookSpecificOutput.additionalContext' _ "$repo" "$plug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rationale (not injected"* ]]   # no marker → whole doc (fail-open, not fail-silent)
}

@test "session start: re-anchors on a compaction with queue+pointer, NOT the full STEERING — R30·d2 / R32" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sM"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sM/.root"
  jq -n '{id:"1",subject:"pick me up",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/1.json"
  jq -n '{id:"2",subject:"already shipped",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/sM/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pick me up"* ]]          # open task surfaced
  [[ "$output" != *"already shipped"* ]]     # completed excluded
  # a repo with nothing says so
  local empty; empty="$(_tmpd)"; git -C "$empty" init -q
  run bash -c 'cd "$1" && "$2"' _ "$empty" "$RESUME"
  [[ "$output" == *"No carried-over"* ]]
}

@test "resume: BATCHED scan — many dirs x many files in one jq, newline-less markers still match" {
  # companion_open_tasks collects every matching file and runs ONE jq over all of them (it used to
  # spawn a jq per file: 277 spawns / ~2s on a real store, on the SessionStart + compaction path).
  # Two failure modes this pins, both of which lose tasks SILENTLY — no error, just a short list:
  #   1. markers are written with `printf '%s'` (NO trailing newline), so the `read` builtin returns
  #      1 on them. Reading them with `read … && match` instead of checking the VARIABLE drops the
  #      whole session dir.
  #   2. a batched jq that mishandles multi-file input drops files after the first.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c 'source "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  # dir A matches on the path-stable .repo identity, dir B on the legacy .root abspath — both
  # newline-less, exactly as `tq` writes them. Several files each, so batching has to span dirs.
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sA"; printf '%s' "$rid"  > "$CLAUDE_COMPANION_TASKS_DIR/sA/.repo"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sB"; printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/sB/.root"
  jq -n '{id:"1",subject:"alpha A1",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sA/1.json"
  jq -n '{id:"2",subject:"alpha A2",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/sA/2.json"
  jq -n '{id:"3",subject:"alpha A3",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/sA/3.json"
  jq -n '{id:"1",subject:"beta B1",status:"pending"}'      > "$CLAUDE_COMPANION_TASKS_DIR/sB/1.json"
  jq -n '{id:"2",subject:"beta B2",status:"pending"}'      > "$CLAUDE_COMPANION_TASKS_DIR/sB/2.json"
  # a third repo's dir must not leak in, and a marker-less dir must not match by accident
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sC"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sC/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/sC/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sD"
  jq -n '{id:"1",subject:"UNSTAMPED",status:"pending"}'    > "$CLAUDE_COMPANION_TASKS_DIR/sD/1.json"

  run bash -c 'cd "$1" && source "$2" && companion_open_tasks "$PWD"' _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  # every OPEN task across BOTH matching dirs survives the batch — the count is the real assertion
  [ "$(printf '%s\n' "$output" | grep -c '◻')" -eq 4 ]
  [[ "$output" == *"alpha A1"* ]] && [[ "$output" == *"alpha A2"* ]]
  [[ "$output" == *"beta B1"*  ]] && [[ "$output" == *"beta B2"*  ]]
  [[ "$output" != *"alpha A3"* ]]    # completed excluded
  [[ "$output" != *"NOT MINE"* ]]    # no cross-repo bleed
  [[ "$output" != *"UNSTAMPED"* ]]   # an unmarked dir is not a match
  # and it stays a SINGLE jq: batching is the point, so a regression to per-file is a failure
  local n; n="$(cd "$repo" && strace -f -e trace=execve -o /dev/stdout \
      bash -c 'source "$1"; companion_open_tasks "$PWD"' _ "$ROOT/lib/companion.sh" 2>/dev/null \
      | grep -c 'execve("[^"]*/jq"' || true)"
  [ -z "$n" ] || [ "$n" -le 1 ]      # skips cleanly where strace is unavailable (macOS CI)
}

@test "manual resume: turns autopilot OFF first, announced when on and quiet when off (R39)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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

@test "tq delta (R69): add/doing print a one-line counts delta, NOT the full queue; done prints the full report" {
  run bash -c 'cd "$1" && "$2" add "first task" "second task"' _ "$ROOT" "$TQ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added #1"* ]] && [[ "$output" == *"added #2"* ]]   # per-add lines stay
  [[ "$output" == *"📋"* ]] && [[ "$output" == *"◻2"* ]]              # counts delta present…
  [[ "$output" == *"→ next: #1"* ]]                                    # …with the next pointer
  # delta ≠ full report: subjects are NOT read back on a mutation (the token-spend R69 removes)
  last="$(printf '%s\n' "$output" | tail -1)"
  [[ "$last" != *"first task"* ]] && [[ "$last" != *"second task"* ]]
  run bash -c 'cd "$1" && "$2" doing 1' _ "$ROOT" "$TQ"
  [[ "$output" == *"▸1"* ]] && [[ "$output" != *"first task"* ]]       # doing: delta only
  run bash -c 'cd "$1" && "$2" done 1' _ "$ROOT" "$TQ"
  [[ "$output" == *"second task"* ]]                                    # done: FULL report (boundary)
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c}" | "$2" | jq -r ".hookSpecificOutput.permissionDecisionReason // \"\""' _ "$repo" "$ASK"
  [[ "$output" == *"PARK"* ]]                # instructs to park, not answer
  [[ "$output" == *"❓ [parked]"* ]]         # with the park token + full payload
  [[ "$output" == *"options"* ]]             # carry the options
  [[ "$output" == *"rec"* ]]                 # + a recommendation
}

@test "autopilot decisive (R59): toggle persists, and flips the ask-guard guidance park→decide" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$TQ" add "scoped" ) >/dev/null
  # not just that .root exists (already pinned) — that it holds the CORRECT root, else resume mis-scopes
  [ "$(cat "$CLAUDE_COMPANION_TASKS_DIR/s1/.root")" = "$(git -C "$repo" rev-parse --show-toplevel)" ]
}

@test "session start: the compaction re-anchor keeps the recommendation-contract clause (R56 G3 — R49)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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

# ---- decisions surfaced + recorded by /companion:docs (R41; renamed from document 2026-07-22) ----

@test "secret gate: covers NotebookEdit's new_source — key blocked, clean cell passes (R43)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  run bash -c 'jq -nc --arg c "$1" "{tool_input:{notebook_path:\"/x/n.ipynb\",new_source:\$c}}" | "$2"' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]                                       # NotebookEdit no longer bypasses the gate
  [[ "$output" == *"BLOCKED"* ]]
  run bash -c 'jq -nc "{tool_input:{notebook_path:\"/x/n.ipynb\",new_source:\"print(1+1)\"}}" | "$1"' _ "$GUARD"
  [ "$status" -eq 0 ]                                       # a clean cell still passes
}

@test "parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value (R42)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
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

# ---- living contract (R58): drift backstop (capture retired 2026-07-29) ----

@test "contract-drift: warns when behaviour changed without a contract doc, silent otherwise (R58)" {
  local repo; repo="$(_tmpd)"
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
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
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

# ── sweep mode (R77) ───────────────────────────────────────────────────────────────────────────
# Sweep is the ONE mode that reaches backwards into the already-parked pile, so eligibility is the
# safety property. It keys on a POSITIVE marker the parker wrote — `rev:` = reversible, but the
# owner's call — never on inference over prose. An earlier build inferred eligibility as
# "❓ ∧ rec: ∧ ¬decompose:", which under decisive mode selected EXACTLY the irreversible parks it
# was meant to protect (decisive parks only the irreversible, and writes `rec:` on them). Every
# exclusion below is pinned separately, and each fixture carries the OTHER markers so no rule can
# be masked by another — the masking trap that already hid two of these once.

_sw_task() {  # $1=subject $2=id
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sw"
  jq -n --arg s "$1" --arg i "$2" '{id:$i,subject:$s,status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sw/$2.json"
}
_sw_decision() {  # -> "block" when the drain keeps going, "" when it lets the session stop
  printf '{"session_id":"sw","cwd":"%s"}' "$1" | bash "$STOP" | jq -r '.decision // ""' 2>/dev/null
}
_sw_repo() {
  local r; r="$(_tmpd)"; git -C "$r" init -q
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  ( cd "$r" && "$AP" on ) >/dev/null; printf '%s' "$r"
}

@test "autopilot sweep: flag persists per-repo and is independent of ship/decisive (R77)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "off" ]
  ( cd "$repo" && "$AP" sweep on ) >/dev/null
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "on" ]
  run bash -c 'cd "$1" && "$2" decisive status' _ "$repo" "$AP"; [ "$output" = "off" ]
  ( cd "$repo" && "$AP" sweep off ) >/dev/null
  run bash -c 'cd "$1" && "$2" sweep status' _ "$repo" "$AP"; [ "$output" = "off" ]
}

@test "autopilot sweep: OFF stops on a parked-only queue, ON works a rev: park (R77)" {
  local repo; repo="$(_sw_repo)"
  _sw_task "❓ [parked] rev: colour scheme — options: A) dark B) light; rec: A + matches the app" 1
  ( cd "$repo" && "$AP" sweep off ) >/dev/null
  [ "$(_sw_decision "$repo")" = "" ]          # parked-only -> done, session may stop
  # Assert the note's ABSENCE where a nudge is actually emitted: with sweep off and plain work
  # present the hook blocks, so the text exists to be checked. Asserting it on the parked-only
  # queue above passes vacuously — the hook prints nothing at all there (a mutation that emitted
  # the note unconditionally slipped through exactly that way).
  _sw_task "plain work that keeps the drain going" 9
  run bash -c 'printf "{\"session_id\":\"sw\",\"cwd\":\"%s\"}" "$1" | bash "$2"' _ "$repo" "$STOP"
  [[ "$output" == *"Autopilot:"* ]]           # a nudge really was emitted...
  [[ "$output" != *"SWEEP (R77)"* ]]          # ...and carries no sweep note while the flag is off
  rm -f "$CLAUDE_COMPANION_TASKS_DIR/sw/9.json"
  ( cd "$repo" && "$AP" sweep on ) >/dev/null
  [ "$(_sw_decision "$repo")" = "block" ]     # sweep -> the rev: park is work
  run bash -c 'printf "{\"session_id\":\"sw\",\"cwd\":\"%s\"}" "$1" | bash "$2"' _ "$repo" "$STOP"
  [[ "$output" == *"colour scheme"* ]]
  [[ "$output" == *"SWEEP (R77)"* ]]          # ...and present while it is on
}

@test "autopilot sweep: an IRREVERSIBLE park (no rev: marker) is never eligible (R77/R59)" {
  # The case that killed the first design: decisive mode parks ONLY the irreversible and writes
  # `rec:` on it, so a rec-based filter selected precisely the set it had to protect.
  local repo; repo="$(_sw_repo)"; ( cd "$repo" && "$AP" sweep on ) >/dev/null
  _sw_task "❓ [parked] force-push the rewrite to origin/main — options: A) force B) PR; rec: A + why" 1
  [ "$(_sw_decision "$repo")" = "" ]
  _sw_task "❓ [parked] delete the staging bucket and its snapshots — options: A) delete B) keep; rec: A + cost" 2
  [ "$(_sw_decision "$repo")" = "" ]          # still nothing sweepable
  _sw_task "❓ [parked] rev: button copy — options: A) Save B) Done; rec: A + clearer" 3
  [ "$(_sw_decision "$repo")" = "block" ]     # only the marked-reversible one is work
  run bash -c 'printf "{\"session_id\":\"sw\",\"cwd\":\"%s\"}" "$1" | bash "$2"' _ "$repo" "$STOP"
  [[ "$output" == *"button copy"* ]]
  [[ "$output" != *"force-push"* ]]
  [[ "$output" != *"delete the staging bucket"* ]]
}

@test "autopilot sweep: ⏳, decompose:, unrecorded and prose-only markers stay excluded (R77/R65)" {
  local repo; repo="$(_sw_repo)"; ( cd "$repo" && "$AP" sweep on ) >/dev/null
  # each fixture carries EVERY other marker, so it can only be excluded by the rule it targets
  _sw_task "⏳ [blocked] rev: delete the production bucket; rec: yes do it" 1
  _sw_task "❓ [parked] rev: Decompose: migrate the store — need: which fields; rec: split by table" 2
  _sw_task "❓ [parked] rev: drop the legacy table? — A) drop B) keep; no rec: recorded, this one is yours" 3
  _sw_task "❓ [parked] mentions rev: only in prose here; rec: A + why" 4
  [ "$(_sw_decision "$repo")" = "" ]          # not one of them is eligible
  _sw_task "❓ [parked] rev: wording — options: A) terse B) chatty; rec: A + the voice" 5
  [ "$(_sw_decision "$repo")" = "block" ]
  run bash -c 'printf "{\"session_id\":\"sw\",\"cwd\":\"%s\"}" "$1" | bash "$2"' _ "$repo" "$STOP"
  [[ "$output" == *"wording"* ]]
  [[ "$output" != *"production bucket"* ]]
  [[ "$output" != *"migrate the store"* ]]
  [[ "$output" != *"legacy table"* ]]
}

@test "autopilot sweep TERMINATES: bounded by a counter no completion resets (R77)" {
  # The stall cap cannot bound a sweep — closing a swept park advances DONE, which resets stall.
  # Measured before the fix: 25/25 turns blocked against a cap of 8. Plain work must stay unbounded.
  local repo; repo="$(_sw_repo)"; ( cd "$repo" && "$AP" sweep on ) >/dev/null
  local i turns=0
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do            # close one rev: park, open the next
    _sw_task "❓ [parked] rev: choice $i — options: A) x B) y; rec: A + why" "$i"
    [ "$i" -gt 1 ] && jq -n --arg d "$((i-1))" '{id:$d,subject:"done",status:"completed"}'       > "$CLAUDE_COMPANION_TASKS_DIR/sw/$((i-1)).json"
    [ "$(_sw_decision "$repo")" = "block" ] || break
    turns=$((turns+1))
  done
  [ "$turns" -le 8 ]                                  # yields at the cap instead of forever
  [ "$turns" -ge 1 ]                                  # ...but does sweep before yielding
}

# ── doc-lint (R78) ─────────────────────────────────────────────────────────────────────────────
# These two checks used to live inline in check.sh, which the suite cannot invoke without recursion
# (check.sh runs bats) — so they had no behavioural case and no mutation, a gap R78 had to record
# rather than close. Extracted to bin/doc-lint.sh precisely so these cases can exist.

@test "doc-lint frontmatter: accepts shapes the HOST accepts (no false positives) (R78)" {
  # An earlier whole-block whitelist rejected all three of these, which would have broken valid
  # user commands — worse than having no check at all.
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: "plain"\nallowed-tools:\n  - Bash\n  - Read\n---\nbody\n' > "$d/a.md"
  printf -- '---\ndescription: "plain"\nallowed-tools: [Bash, Read]\n---\nbody\n' > "$d/b.md"
  printf -- "---\ndescription: 'a: b'\nmodel: inherit\n---\nbody\n" > "$d/c.md"
  # UNQUOTED but perfectly valid — without this every fixture was quoted, so a doc-lint that
  # rejected all unquoted values passed all three cases AND left check.sh green (every real
  # command already quotes). The "must not break valid commands" contract had no coverage.
  printf -- '---\ndescription: walk the parked backlog one at a time\n---\nbody\n' > "$d/d.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/a.md" "$d/b.md" "$d/c.md" "$d/d.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "doc-lint frontmatter: rejects shapes the HOST throws on (R75/R78)" {
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: [target] — leading indicator\n---\nbody\n' > "$d/ind.md"
  printf -- '---\ndescription: wire this: the thing\n---\nbody\n'          > "$d/colon.md"
  printf -- '---\ndescription: "never closed\n---\nbody\n'                 > "$d/quote.md"
  printf -- '---\ndescription: "one"\ndescription: "two"\n---\nbody\n'     > "$d/dup.md"
  for c in ind colon quote dup; do
    run "$DEV/doc-lint.sh" frontmatter "$d/$c.md"
    [ "$status" -eq 1 ]
    [[ "$output" == *"FAIL"* ]]
  done
  run "$DEV/doc-lint.sh" frontmatter "$d/ind.md"
  [[ "$output" == *"YAML indicator"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/quote.md"
  [[ "$output" == *"never closes"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/dup.md"
  [[ "$output" == *"duplicate"* ]]
}

@test "doc-lint ledger: a hard measurement needs evidence; a rhetorical figure does not (R78)" {
  local d; d="$(_tmpd)"
  printf '| **R1** | 🔓 | Grew by 512B and blocked 25/25 turns. | 2026-01-01, no evidence. |\n' > "$d/bad.md"
  run "$DEV/doc-lint.sh" ledger "$d/bad.md"
  [ "$status" -eq 1 ]
  [[ "$output" == *"R1 states a measurement with no evidence"* ]]

  printf '| **R2** | 🔓 | Grew by 512B, measured with check.sh. | 2026-01-01. |\n' > "$d/good.md"
  run "$DEV/doc-lint.sh" ledger "$d/good.md"
  [ "$status" -eq 0 ]

  # a rhetorical estimate is a judgement, not a measurement — it must NOT trip the rule (this
  # false-positived on R40's "~90% of the value" during calibration)
  printf '| **R3** | 🔓 | Roughly ~90%% of the value, and version 3.22.0. | 2026-01-01. |\n' > "$d/rhet.md"
  run "$DEV/doc-lint.sh" ledger "$d/rhet.md"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check.sh actually INVOKES doc-lint for both subcommands (R78 wiring guard)" {
  # Extracting the logic made it testable but created a new untested failure mode: the CALL. With
  # both invocations stubbed out the whole suite stayed green while the gate silently checked
  # nothing. bats cannot run check.sh (check.sh runs bats), so this is a structural guard — the
  # same shape as the R56·P3 guard over command prose.
  run grep -c 'doc-lint\.sh" frontmatter' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  run grep -c 'doc-lint\.sh ledger' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
}

@test "doc-lint: CRLF and BOM do not silently disable the frontmatter lint (R78)" {
  # The reader compared line 1 to "---"; a CRLF file made it "---\r", so the block came back EMPTY
  # and EVERY frontmatter check passed vacuously — fail-open on all of them at once, and the exact
  # route by which the 3.21.0 blocker (an unquoted leading `[`) gets back in.
  local d; d="$(_tmpd)"
  printf -- '---\r\ndescription: "never closed\r\n---\r\nbody\r\n' > "$d/crlf.md"
  printf -- '\xef\xbb\xbf---\ndescription: [bad]\n---\nbody\n'     > "$d/bom.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/crlf.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"never closes"* ]]
  run "$DEV/doc-lint.sh" frontmatter "$d/bom.md"
  [ "$status" -eq 1 ]; [[ "$output" == *"YAML indicator"* ]]
  # and the shared reader really returns the block for both
  run "$DEV/doc-lint.sh" fm "$d/crlf.md"
  [[ "$output" == *"description"* ]]
}

@test "doc-lint: folded and literal block scalars are valid YAML, not indicators (R78)" {
  local d; d="$(_tmpd)"
  printf -- '---\ndescription: >\n  folded and valid\n---\nb\n' > "$d/f.md"
  printf -- '---\ndescription: |\n  literal and valid\n---\nb\n' > "$d/l.md"
  run "$DEV/doc-lint.sh" frontmatter "$d/f.md" "$d/l.md"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf -- '---\ndescription: [still bad]\n---\nb\n' > "$d/i.md"   # real indicators still caught
  run "$DEV/doc-lint.sh" frontmatter "$d/i.md"
  [ "$status" -eq 1 ]
}

@test "doc-lint ledger: the ~ exemption works on MULTI-digit numbers (R78)" {
  # `(^|[^~])[0-9]` could begin matching one digit inside the number, so ~371B tripped while ~9B
  # did not — the exemption only worked for single digits.
  local d; d="$(_tmpd)"
  printf '| **R9** | 🔓 | Grew by ~371B and ≈1200 tokens. | x. |\n' > "$d/approx.md"
  run "$DEV/doc-lint.sh" ledger "$d/approx.md"
  [ "$status" -eq 0 ]; [ -z "$output" ]
  printf '| **R9** | 🔓 | Grew by 371B. | x. |\n' > "$d/hard.md"    # a hard figure still needs evidence
  run "$DEV/doc-lint.sh" ledger "$d/hard.md"
  [ "$status" -eq 1 ]
}

@test "doc-lint ledger: a missing file FAILS loudly instead of reporting ok (R78)" {
  # It exited 0, and check.sh then printed "ok (ledger measurements cite their evidence)" for a
  # check that never ran — a gate reporting green on work it did not do.
  run "$DEV/doc-lint.sh" ledger /nonexistent/REQUIREMENTS.md
  [ "$status" -eq 1 ]
  [[ "$output" == *"not found"* ]]
}

@test "R81 hook budget: the gate CATCHES a store-scaling hook and PASSES a bounded one" {
  # The gate's own guard. A budget gate that cannot fail is theatre, so prove both directions
  # against a REAL scaling hook rather than a stub: a fake bin/ whose session-start.sh reads the
  # whole store (the shape of the 2085ms->16108ms regression) must FAIL, and a bounded one PASS.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  local fake; fake="$(_tmpd)"; mkdir -p "$fake/bin" "$fake/lib"
  cp "$DEV/hook-budget.sh" "$fake/bin/"; cp "$ROOT/lib/companion.sh" "$fake/lib/"
  # BOUNDED: touches nothing in the store. Must pass.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/bin/session-start.sh"
  chmod +x "$fake/bin/session-start.sh"
  # Pin the ABSOLUTE cap, which is the hard gate since the recalibration, and use a store big
  # enough that the unbounded hook clears the noise floor. With the old tiny store the fake
  # hook measured UNDER NOISE_MS, where the ratio is not enforced — so the gate passed it and
  # this guard silently stopped guarding. It failed only under load, which is how it surfaced.
  run env HOOK_BUDGET_BIN="$fake/bin" HOOK_BUDGET_BASEDIRS=8 HOOK_BUDGET_PERDIR=8 HOOK_BUDGET_ABSCAP=200 bash "$fake/bin/hook-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"session-start.sh"* ]]
  # UNBOUNDED: one jq per file across every session dir — cost tracks the store. Must fail.
  cat > "$fake/bin/session-start.sh" <<'EOS'
#!/usr/bin/env bash
for f in "${CLAUDE_COMPANION_TASKS_DIR:-/nonexistent}"/*/*.json; do
  [ -f "$f" ] || continue
  jq -r '.subject // empty' "$f" >/dev/null 2>&1 || true
done
exit 0
EOS
  chmod +x "$fake/bin/session-start.sh"
  run env HOOK_BUDGET_BIN="$fake/bin" HOOK_BUDGET_BASEDIRS=8 HOOK_BUDGET_PERDIR=8 HOOK_BUDGET_ABSCAP=200 bash "$fake/bin/hook-budget.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"FAIL"* ]]
}

@test "R81 hook budget: a missing jq/git SKIPS clean — the gate never false-reds the environment" {
  # Best-effort about the environment, strict about the budget (R7/R68): a toolless box must not
  # turn into a red build, or the gate gets deleted for being flaky.
  local fake bsh; fake="$(_tmpd)"; mkdir -p "$fake/bin" "$fake/empty"
  cp "$DEV/hook-budget.sh" "$fake/bin/"
  # Absolute interpreter path: `env PATH=<empty> bash …` would fail to find bash ITSELF, which
  # tests nothing about the gate. Emptying PATH must hide jq/git from the script, not the shell.
  bsh="$(command -v bash)"
  run env PATH="$fake/empty" HOOK_BUDGET_BIN="$fake/bin" "$bsh" "$fake/bin/hook-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKIP"* ]]
}

@test "session start: the compact re-anchor carries BOTH halves of the posture, not the core (R80)" {
  # The posture is what decays across a long session, and the closing-verdict half decays first —
  # it was missing from this message while the options half was present. R30·d2 still holds: the
  # STEERING core itself is NOT re-pasted, only these ~40 bytes of posture.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local p; p="$(jq -nc --arg c "$repo" '{source:"compact",cwd:$c,session_id:"sC"}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$p" "$SS"
  [ "$status" -eq 0 ]
  local ctx; ctx="$(printf '%s' "$output" | jq -r '.hookSpecificOutput.additionalContext')"
  [[ "$ctx" == *"recommendation-first options"* ]]   # the options half
  [[ "$ctx" == *"EVERY reply"* ]]                    # the unconditional verdict half
  [[ "$ctx" == *"compacted"* ]]
  [[ "$ctx" != *"How we keep it clean"* ]]           # the core is still NOT re-pasted (R30·d2)
  [[ "$ctx" != *"Wireframe convention"* ]]
}

@test "tq prune: removes FINISHED old stores, never one with open/parked/blocked work (R81)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  _mk() {  # $1=dirname  $2=status  $3=subject
    mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$1"
    printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/$1/.repo"
    jq -n --arg s "$3" --arg st "$2" '{id:"1",subject:$s,status:$st}' > "$CLAUDE_COMPANION_TASKS_DIR/$1/1.json"
    # backdate everything so the age window can't be what saves it
    find "$CLAUDE_COMPANION_TASKS_DIR/$1" -exec touch -t 202001010000 {} + 2>/dev/null || true
  }
  _mk done1   completed   "shipped"
  _mk done2   cancelled   "dropped"
  _mk open1   pending     "still open"
  _mk doing1  in_progress "mid-flight"
  _mk park1   pending     "❓ [parked] a decision"
  _mk block1  pending     "⏳ [blocked] owner action"
  # another repo's finished store must be invisible to this repo's prune (no cross-project bleed)
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/other"; printf '/somewhere/else' > "$CLAUDE_COMPANION_TASKS_DIR/other/.root"
  jq -n '{id:"1",subject:"theirs",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/other/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/other" -exec touch -t 202001010000 {} + 2>/dev/null || true

  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  # finished stores gone
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/done1" ]
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/done2" ]
  # every flavour of unfinished work survives
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/open1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/doing1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/park1" ]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/block1" ]
  # and another project's store is untouched
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/other" ]
}

@test "tq prune: age protects a RECENT finished store, and --dry-run deletes nothing" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/fresh"; printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/fresh/.repo"
  jq -n '{id:"1",subject:"just finished",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/fresh/1.json"
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/fresh" ]        # recent → kept despite being finished
  # old + finished, but dry-run must not remove it
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/old"; printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/old/.repo"
  jq -n '{id:"1",subject:"ancient",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/old/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/old" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30 --dry-run' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  [[ "$output" == *"would remove"* ]]
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/old" ]          # dry run: still there
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ ! -d "$CLAUDE_COMPANION_TASKS_DIR/old" ]        # real run: gone
}

@test "autopilot RUN bound: the TURN cap stops a PRODUCTIVE drain the stall cap never could (R81)" {
  # The hole this closes: `stall` resets on every completion, so a drain that keeps finishing work
  # ran forever. Complete a task on EVERY turn — the stall cap can never fire — and prove the turn
  # cap still ends it. This is the overnight-runaway case.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apTurns; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"
  printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"9",subject:"always open",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/9.json"
  local i r
  for i in 1 2 3; do
    # a NEW completed task each turn → DONE rises → stall resets to 0 every single time
    jq -n --arg i "$i" '{id:$i,subject:"done \($i)",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/$i.json"
    r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' \
         | CLAUDE_COMPANION_AUTOPILOT_TURNS=4 "$STOP" | jq -r '.decision // "allow"')"
    [ "$r" = "block" ]
  done
  jq -n '{id:"4",subject:"done 4",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/4.json"
  r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_TURNS=4 "$STOP")"
  [ -z "$r" ]        # 4th continuation hits the cap → yields, despite constant progress
}

@test "autopilot RUN bound: the wall-clock deadline yields, and 0 disables both bounds (R81)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apClock; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"
  printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"open work",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  # one turn to create the counter file
  local r; r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" | jq -r '.decision // "allow"')"
  [ "$r" = "block" ]
  local cf="$CLAUDE_COMPANION_STATE_DIR/autopilot/continue-$sid"
  [ -f "$cf" ]
  # backdate the run's start by ~7h, leaving the other fields intact. `|| true`: the counter file is
  # written with printf and NO trailing newline, so `read` returns 1 having set the vars correctly —
  # the same newline-less trap the task-store markers have (see the BATCHED scan test).
  local d s w st tn; read -r d s w st tn < "$cf" || true
  printf '%s %s %s %s %s' "$d" "$s" "$w" "$((st - 25200))" "$tn" > "$cf"
  r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | CLAUDE_COMPANION_AUTOPILOT_HOURS=6 "$STOP")"
  [ -z "$r" ]        # past the 6h deadline → yields
  # ...and with both bounds disabled it keeps going regardless of how old the run is
  printf '%s %s %s %s %s' "$d" "$s" "$w" "$((st - 999999))" "9999" > "$cf"
  r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' \
       | CLAUDE_COMPANION_AUTOPILOT_HOURS=0 CLAUDE_COMPANION_AUTOPILOT_TURNS=0 "$STOP" | jq -r '.decision // "allow"')"
  [ "$r" = "block" ]
}

@test "autopilot RUN bound: an OLD 3-field continue-file still works (no migration, no lost run)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local sid=apOld; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"
  printf '%s' "$repo" > "$CLAUDE_COMPANION_TASKS_DIR/$sid/.root"
  jq -n '{id:"1",subject:"open work",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  local cf="$CLAUDE_COMPANION_STATE_DIR/autopilot/continue-$sid"
  mkdir -p "$(dirname "$cf")"; printf '0 1 0' > "$cf"     # pre-2026-07-29 format
  local r; r="$(jq -nc --arg c "$repo" --arg s "$sid" '{cwd:$c,session_id:$s}' | "$STOP" | jq -r '.decision // "allow"')"
  [ "$r" = "block" ]                                       # keeps going, no crash
  local _a _b _c st tn; read -r _a _b _c st tn < "$cf" || true   # no trailing newline -> read exits 1
  [ -n "$st" ] && [ "$st" -gt 0 ]                          # start re-seeded
  [ "$tn" = "1" ]                                          # turn counter started
}

@test "resume: ONE corrupt task file loses only ITSELF, never the whole backlog (DA blocker)" {
  # The batched jq aborts at the first parse error, so a single half-written file took every task
  # in every LATER file with it — 7 open tasks rendering as 0, silently, on the one path whose job
  # is handing the backlog back after a crash. The per-file fallback is what makes that survivable.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/cA" "$CLAUDE_COMPANION_TASKS_DIR/cB"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/cA/.repo"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/cB/.repo"
  printf '{ NOT VALID JSON' > "$CLAUDE_COMPANION_TASKS_DIR/cA/1.json"
  local i
  for i in 2 3 4;   do jq -n --arg i "$i" '{id:$i,subject:"alpha \($i)",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/cA/$i.json"; done
  for i in 5 6 7 8; do jq -n --arg i "$i" '{id:$i,subject:"beta \($i)",status:"pending"}'  > "$CLAUDE_COMPANION_TASKS_DIR/cB/$i.json"; done
  run bash -c 'cd "$1" && . "$2" && companion_open_tasks "$PWD"' _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c '◻')" -eq 7 ]   # all 7 healthy tasks, not 0
  [[ "$output" == *"alpha 2"* ]] && [[ "$output" == *"beta 8"* ]]
}

@test "tq prune: an UNREADABLE task file means KEEP, never delete (jq exit status, not stdout)" {
  # `jq -s` prints 0 AND exits 2 when it cannot OPEN a file, so reading stdout alone turned
  # "unreadable" into "zero open tasks" and destroyed a store holding a parked decision.
  [ "$(id -u)" -ne 0 ] || skip "running as root: chmod 000 is not enforced"
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/locked"
  printf '%s' "$rid" > "$CLAUDE_COMPANION_TASKS_DIR/locked/.repo"
  jq -n '{id:"1",subject:"❓ [parked] owner decision",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json"
  chmod 000 "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json"
  find "$CLAUDE_COMPANION_TASKS_DIR/locked" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  chmod 644 "$CLAUDE_COMPANION_TASKS_DIR/locked/1.json" 2>/dev/null || true
  [ -d "$CLAUDE_COMPANION_TASKS_DIR/locked" ]
}

@test "tq prune: a SYMLINKED session dir is skipped — rm -rf must not recurse through the link" {
  # The glob yields a trailing slash, which makes rm -rf follow the link and empty the TARGET:
  # an archived session dir outside the store was destroyed while the link itself survived.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local rid; rid="$(cd "$repo" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  local arch; arch="$(_tmpd)"; mkdir -p "$arch/real"
  printf 'IRREPLACEABLE\n' > "$arch/real/notes.md"
  printf '%s' "$rid" > "$arch/real/.repo"
  jq -n '{id:"1",subject:"long done",status:"completed"}' > "$arch/real/1.json"
  ln -s "$arch/real" "$CLAUDE_COMPANION_TASKS_DIR/archived"
  find "$arch" -exec touch -t 202001010000 {} + 2>/dev/null || true
  run bash -c 'cd "$1" && "$2" prune --days 30' _ "$repo" "$TQ"
  [ "$status" -eq 0 ]
  [ -f "$arch/real/notes.md" ]     # the target survived
  rm -rf "$arch"
}

@test "secret gate: NON-STRING content (NotebookEdit array/object) still BLOCKS — no fail-open (R43)" {
  # jq's `+` throws on a non-string, so `rec` came back empty and the gate exited 0 — a real
  # credential straight through, on the very tool R43 added the gate to cover.
  local k="AKIA""ABCDEFGHIJKLMNOP" p          # split so THIS file isn't itself a secret
  p="$(jq -nc --arg k "$k" '{tool_input:{file_path:"/r/n.ipynb",new_source:[$k,"x"]}}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$p" "$GUARD"
  [ "$status" -eq 2 ]
  p="$(jq -nc --arg k "$k" '{tool_input:{file_path:"/r/n.ipynb",content:{a:$k}}}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$p" "$GUARD"
  [ "$status" -eq 2 ]
}

@test "secret gate: an EMPTY edit never scans the FILE PATH as content (no false block)" {
  # With no content there was no newline to split on, so the path itself became the scanned text:
  # an Edit clearing a file under a directory literally named AKIA… was BLOCKED.
  local k="AKIA""ABCDEFGHIJKLMNOP" p        # split so THIS file isn't itself a secret
  p="$(jq -nc --arg d "/tmp/$k/notes.txt" '{tool_input:{file_path:$d,new_string:""}}')"
  run bash -c 'printf "%s" "$1" | "$2"' _ "$p" "$GUARD"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "R81 hook budget: measures under a COMMA-DECIMAL locale (LC_ALL=C is load-bearing)" {
  # TIMEFORMAT renders through the locale: under de_DE every sample was "0,124", failed the
  # digits-only guard and fell through to 0 — a green gate that measured nothing at all.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  run env LC_NUMERIC=de_DE.UTF-8 LC_ALL=de_DE.UTF-8 \
      HOOK_BUDGET_BASEDIRS=6 HOOK_BUDGET_PERDIR=4 bash "$DEV/hook-budget.sh"
  [ "$status" -eq 0 ]
  # at least one hook must report a NON-zero measurement
  [[ "$output" =~ [1-9][0-9]*ms ]]
}

# ── the mutation gate itself (R78) ─────────────────────────────────────────────────────────────
# The gate whose whole job is proving tests CAN fail had no test of its own, and shipped TWO
# defects that let it certify coverage it never observed (3.30.2 and 3.31.0, both caught by
# something other than the suite). It now lives in bin/ so these cases can exist at all; a FAKE
# `bats` first on PATH drives each verdict branch in milliseconds without recursing into the
# real suite.
_mutgate() {  # $1 = shim body ("" = use the real bats) · $2 = tag → runs the REAL gate
  local d="$BATS_TEST_TMPDIR/mg$2"
  mkdir -p "$d/dev/tests" "$d/plugins/companion" "$d/shim"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  [ -n "$1" ] && { printf '%s\n' "$1" > "$d/shim/bats"; chmod +x "$d/shim/bats"; }
  ( cd "$d" && PATH="$d/shim:$PATH" ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1 )
}
# A shim that answers --count with 3, passes the gate's GREEN BASELINE run (call #1), and only
# then behaves as told. The baseline check is itself under test below, so shims must satisfy it.
_shim() {
  printf '#!/bin/sh\n[ "$1" = "--count" ] && { echo 3; exit 0; }\n'
  printf 'n=$(cat "$0.n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$0.n"\n'
  printf 'if [ "$n" -eq 1 ]; then echo "1..3"; echo "ok 1 a"; echo "ok 2 b"; echo "ok 3 c"; exit 0; fi\n'
  printf '%s\n' "$1"
}

@test "mutation gate: only a COMPLETE run that failed counts as caught (R78)" {
  # THE POINT: "bats exited nonzero" and "a test failed" are different claims, and conflating them
  # made the gate certify holes as covered. Each case below exits nonzero; only one is evidence.

  # (1) KILLED — exit 124, nothing ran. This is what load does, and what made a real pace-marker
  #     hole report as caught locally while CI called it a hole (3.30.2).
  run _mutgate "$(_shim 'exit 124')" killed
  [ "$status" -ne 0 ]
  [[ "$output" == *"did not COMPLETE"* ]]; [[ "$output" != *"ok    caught"* ]]

  # (2) PARTIAL — the plan promises 3 results, 2 arrive. A run cut short mid-suite still emits a
  #     `not ok`, so checking only for one accepts a suite that never finished.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; exit 1')" partial
  [ "$status" -ne 0 ]; [[ "$output" == *"did not COMPLETE"* ]]

  # (3) GENUINE — a complete run of 3 with one failure. The gate must still do its actual job.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; echo "ok 3 c"; exit 1')" real
  [ "$status" -eq 0 ]; [[ "$output" == *"caught"* ]]

  # (4) GREEN — the mutation survived. Still a hole.
  run _mutgate "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "ok 2 b"; echo "ok 3 c"; exit 0')" green
  [ "$status" -ne 0 ]; [[ "$output" == *"HOLE"* ]]
}

@test "mutation gate: a suite ALREADY RED is refused — it would score every mutation caught (R78)" {
  # The deepest version of this gate's failure mode. Every verdict is "did the suite go red?",
  # which measures nothing if it was red beforehand: ONE pre-existing failure makes EVERY mutation
  # report "caught" and the gate hand back a clean bill of health for coverage it never saw.
  # This is not hypothetical — a killed run left doc-lint.sh mutated in the tree, one test went
  # red, and the gate duly certified two mutations it had not actually measured.
  local d="$BATS_TEST_TMPDIR/mgred"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "a" { true; }\n@test "already broken" { false; }\n@test "c" { true; }\n' \
    > "$d/dev/tests/t.bats"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"ALREADY RED"* ]]
  [[ "$output" == *"already broken"* ]]   # names the culprit rather than just refusing
  [[ "$output" != *"ok    caught"* ]]     # no mutation was scored
}

@test "mutation gate: refuses to run CONCURRENTLY on one tree (R78/R7)" {
  # Two runs restore each other's *.mutbak and leave enforced core MUTATED in the working tree,
  # ready for the next `git add -A`. That happened: doc-lint.sh lost its BOM stripping and ship.sh
  # lost sight of untracked critical paths, both silently.
  local d="$BATS_TEST_TMPDIR/mglock"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "a" { true; }\n@test "b" { true; }\n' > "$d/dev/tests/t.bats"
  # Hold the lock the way a running gate would, then prove a second run refuses instead of racing.
  local lk; lk="${TMPDIR:-/tmp}/companion-mutate-$(printf '%s' "$d" | cksum | cut -d' ' -f1).lock"
  mkdir -p "$lk"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  rmdir "$lk" 2>/dev/null || true
  [ "$status" -eq 2 ]
  [[ "$output" == *"another --mutate run"* ]]
  [[ "$output" != *"ok    caught"* ]]
  # and the target was never touched while the lock was held
  run cat "$d/plugins/companion/target.sh"
  [ "$output" = "VALUE=1" ]
}

@test "mutation gate: an UNPARSEABLE suite is refused up front, not scored (R78)" {
  # bats answers a suite it cannot parse with a perfectly well-formed `1..1 / not ok
  # bats-gather-tests` — zero tests run. Demanding "a ^not ok" therefore does NOT distinguish it,
  # and the first version of this very fix scored EVERY mutation as caught because of it, exiting
  # 0. Calibrating with `bats --count` catches it before a single mutation is applied.
  local d="$BATS_TEST_TMPDIR/mgparse"
  mkdir -p "$d/dev/tests" "$d/plugins/companion"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  printf '@test "broken" {\n  if true; then\n}\n' > "$d/dev/tests/x.bats"
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1' _ "$d"
  [ "$status" -eq 2 ]
  [[ "$output" == *"cannot enumerate the suite"* ]]
  [[ "$output" != *"caught"* ]]
}

@test "session start: LESSONS is two-tier — only the core above the marker is injected (R69/R30·d7)" {
  # The cap is on INJECTED bytes, not on the file. Before the split, LESSONS sat 5B under its
  # ceiling while the process told every session to append to it, so each new lesson was paid for
  # by deleting a true one — two real remedies were lost that way before this landed.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; mkdir -p "$repo/docs"
  cat > "$repo/docs/LESSONS.md" <<'EOF'
# Lessons
- ALPHA-CORE-TRAP always injected
<!-- lessons injection stops here -->
- OMEGA-ONDEMAND-TRAP read on demand only
EOF
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL bash "$4"' _ \
    "$(jq -nc --arg c "$repo" '{source:"startup",cwd:$c}')" "$(_tmpd)" "$(_tmpd)" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALPHA-CORE-TRAP"* ]]        # the core rides every session...
  [[ "$output" != *"OMEGA-ONDEMAND-TRAP"* ]]    # ...the tail does not, which is the whole point
  [[ "$output" != *"lessons injection stops here"* ]]   # and the marker itself is never injected

  # FAILS OPEN on a file with no marker — a stranger's repo (R9) keeps working, whole file injected.
  printf '# Lessons\n- ZETA-UNSPLIT-TRAP\n' > "$repo/docs/LESSONS.md"
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL2 bash "$4"' _ \
    "$(jq -nc --arg c "$repo" '{source:"startup",cwd:$c}')" "$(_tmpd)" "$(_tmpd)" "$SS"
  [[ "$output" == *"ZETA-UNSPLIT-TRAP"* ]]
}

@test "session start: autopilot mode prose rides ONLY when the mode is armed (R69)" {
  # ~2.7KB of mode rules that are dead weight in every session where autopilot is off — which is
  # most of them. Conditional, not deleted: when the mode IS on the rules are exactly as present as
  # they ever were. This is rent paid per session forever, so the gate is worth having.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  local pay; pay="$(jq -nc --arg c "$repo" '{source:"startup",cwd:$c}')"
  run bash -c 'cd "$4" && printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp bash "$3"' \
      _ "$pay" "$st" "$SS" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core always rides...
  [[ "$output" != *"Keep-going mode"* ]]          # ...the mode prose does not
  [[ "$output" != *"autopilot:start"* ]]          # and the delimiter never leaks
  local off_len="${#output}"

  ( cd "$repo" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" on ) >/dev/null
  run bash -c 'cd "$4" && printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp2 bash "$3"' \
      _ "$pay" "$st" "$SS" "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keep-going mode"* ]]          # armed → the rules are there
  [[ "$output" == *"park with the full payload"* ]]
  [ "${#output}" -gt "$off_len" ]
}

# ── burn-down mode (the only mode that AUTHORS work) ───────────────────────────────────────────
_bd() {  # $1=used7 $2=used5 $3=age-offset → run the forecaster against a fresh fixture
  printf '%s %s %s %s %s\n' "$(( $(date +%s) - ${3:-0} ))" "${2:-20}" "$(( $(date +%s)+7200 ))" \
    "${1:-10}" "$(( $(date +%s)+86400 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
}
# Encode a repo path the way lib/companion.sh does, keyed on the RESOLVED root. On macOS
# `_tmpd` returns /var/folders/... and git resolves it to /private/var/folders/..., so any test
# that hand-encodes the mktemp path creates a flag the product never looks at — green on Linux,
# vacuous on macOS. Always go through git, exactly like companion_root does.
# Stamp a session store with the RESOLVED repo root, the way tq and companion_root do. Writing the
# raw mktemp path is the same macOS trap as _flagpath: git resolves /var/... to /private/var/...,
# the stamp never matches, companion_open_tasks returns nothing, and a test asserting "the queue
# holds work" silently asserts nothing at all.
_stamp_root() {  # $1=session dir · $2=repo dir
  local r; r="$(git -C "$2" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$2")"
  printf '%s' "$r" > "$1/.root"
}

_flagpath() {  # $1=state dir · $2=flag kind (autopilot|burndown|ship|…) · $3=repo dir
  local r; r="$(git -C "$3" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$3")"
  printf '%s/%s/%s' "$1" "$2" "$(printf '%s' "$r" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
}

_bd_setup() {
  BD_REPO="$(_tmpd)"; git -C "$BD_REPO" init -q -b main
  git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  BD_STATE="$(_tmpd)"; BD_TASKS="$(_tmpd)"
  mkdir -p "$BD_STATE/burndown"
  touch "$(_flagpath "$BD_STATE" burndown "$BD_REPO")"
}

@test "burn-down: HOLD is the default and every unknown resolves to it" {
  _bd_setup
  # OFF is the shipped state. This mode authors work, so arming it must be a deliberate act.
  rm -rf "$BD_STATE/burndown"
  _bd 10; [ "$status" -eq 0 ]; [[ "$output" == HOLD:* ]]; [[ "$output" == *"OFF for this repo"* ]]
  mkdir -p "$BD_STATE/burndown"
  touch "$(_flagpath "$BD_STATE" burndown "$BD_REPO")"
  # No snapshot at all — the status line may simply not be wired. Cannot forecast, so hold.
  rm -f "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"no rate-limit snapshot"* ]]
  # A STALE snapshot is not a forecast — old data would let it burn on a window that already rolled.
  _bd 10 20 99999; [[ "$output" == HOLD:* ]]; [[ "$output" == *"stale data"* ]]
  # Garbage in the snapshot must not become a number.
  printf 'not-a-timestamp junk\n' > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [ "$status" -eq 0 ]; [[ "$output" == HOLD:* ]]
}

@test "burn-down: burns ONLY on a forecast underspend, never when on track" {
  _bd_setup
  # 90% used with one day left projects to 105% — on track, so there is no spare capacity to fill.
  _bd 90; [[ "$output" == HOLD:* ]]; [[ "$output" == *"on track"* ]]
  # 10% with one day left projects to ~11% — a genuine underspend.
  _bd 10; [[ "$output" == BURN:* ]]; [[ "$output" == *"tracking to"* ]]
  # The target is what it stops at, and it is configurable: aim at 10% and the same state is fine.
  run env BURNDOWN_TARGET_PCT=10 CLAUDE_COMPANION_STATE_DIR="$BD_STATE" \
      CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
}

@test "burn-down: real queued work outranks generated work" {
  _bd_setup
  mkdir -p "$BD_TASKS/sQ"; _stamp_root "$BD_TASKS/sQ" "$BD_REPO"
  jq -n '{id:"1",subject:"something the owner asked for",status:"pending"}' > "$BD_TASKS/sQ/1.json"
  _bd 10
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]
  # Drain it and the capacity becomes available — the meter fills BEHIND the backlog, never ahead.
  jq -n '{id:"1",subject:"something the owner asked for",status:"completed"}' > "$BD_TASKS/sQ/1.json"
  _bd 10; [[ "$output" == BURN:* ]]
}

@test "burn-down: unreviewed branches apply backpressure — the loop is self-limiting" {
  _bd_setup
  # THE anti-waste guarantee. If the owner is not reviewing, generating more output is by
  # definition waste, so the system must notice that about itself and stop.
  local i
  for i in 1 2; do
    git -C "$BD_REPO" checkout -q -b "burndown/p$i" main
    git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "p$i"
    git -C "$BD_REPO" checkout -q main
  done
  _bd 10; [[ "$output" == BURN:* ]]        # 2 of 3 — still room
  git -C "$BD_REPO" checkout -q -b burndown/p3 main
  git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m p3
  git -C "$BD_REPO" checkout -q main
  _bd 10; [[ "$output" == HOLD:* ]]; [[ "$output" == *"review or delete"* ]]
  # An EMPTY branch is nothing to review, so it must not count against the budget.
  git -C "$BD_REPO" branch -D burndown/p3 >/dev/null 2>&1
  git -C "$BD_REPO" branch burndown/empty main
  _bd 10; [[ "$output" == BURN:* ]]
}

@test "burn-down: refuses when the 5h window has no room to actually work" {
  _bd_setup
  _bd 10 95; [[ "$output" == HOLD:* ]]; [[ "$output" == *"headroom"* ]]
  _bd 10 20; [[ "$output" == BURN:* ]]
}

@test "candidates: never invents while a recorded signal remains, and labels it when it does" {
  # The property that makes unattended generation defensible: authorship of "what is worth doing"
  # stays with the owner. Rank order is the mechanism — invention is last and labelled, not first.
  local d; d="$(_tmpd)"; git -C "$d" init -q
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  local tk; tk="$(_tmpd)"
  _cand() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" bash "$ROOT/bin/candidates.sh"; }

  # Nothing recorded at all → says so, out loud, as rank 5.
  _cand; [ "$status" -eq 0 ]; [[ "$output" == 5\|invent\|* ]]; [[ "$output" == *"INVENTED"* ]]

  # A ROADMAP item outranks invention — and a CHECKED item is done, so it must not appear.
  printf '# R\n- [ ] add a dark theme\n- [x] shipped already\n' > "$d/ROADMAP.md"
  _cand; [[ "$output" == 2\|roadmap\|*"dark theme"* ]]; [[ "$output" != *"shipped already"* ]]
  [[ "$output" != *invent* ]]

  # A TODO in tracked source outranks nothing here, but must be found once committed.
  rm "$d/ROADMAP.md"; printf 'x=1  # TODO: cache this\n' > "$d/a.sh"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m add
  _cand; [[ "$output" == 3\|todo\|* ]]

  # A parked decision carrying a recommendation outranks EVERYTHING — the owner already reasoned it.
  mkdir -p "$tk/sP"; _stamp_root "$tk/sP" "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend — options: A) sqlite B) files; rec: sqlite",status:"pending"}' \
    > "$tk/sP/1.json"
  _cand; [[ "$output" == 1\|parked\|* ]]; [[ "$output" == *"rec: sqlite"* ]]
  # A park WITHOUT a recommendation is not a candidate: nothing has been decided, so building
  # against it would be guessing on the owner's behalf.
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend",status:"pending"}' > "$tk/sP/1.json"
  _cand; [[ "$output" != 1\|parked\|* ]]
}

@test "burndown-branch: work is containerised — never on main, never pushed, always discardable" {
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  _bb start "2|roadmap|add a dark theme"
  [ "$status" -eq 0 ]; [ "$output" = "add-a-dark-theme" ]
  [ "$(git -C "$d" rev-parse --abbrev-ref HEAD)" = "burndown/add-a-dark-theme" ]
  # main is untouched: one commit, exactly as before.
  [ "$(git -C "$d" rev-list --count main)" -eq 1 ]
  git -C "$d" checkout -q main
  # The manifest lives OUTSIDE the repo, so reviewing from main still finds it and the tree is clean.
  [ -z "$(git -C "$d" status --porcelain)" ]
  _bb show add-a-dark-theme
  [[ "$output" == *"must default to OFF"* ]]; [[ "$output" == *"roadmap"* ]]
  [[ "$output" == *"Deleting is the DEFAULT expectation"* ]]
  _bb list; [[ "$output" == *"burndown/add-a-dark-theme"* ]]; [[ "$output" == *"add a dark theme"* ]]

  # A dirty tree is refused: discarding the branch would otherwise discard the owner's own WIP.
  printf 'wip\n' > "$d/wip.txt"
  _bb start "2|roadmap|another thing"; [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
  rm "$d/wip.txt"
  # Duplicates are refused rather than silently reusing a branch that may hold other work.
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 3 ]

  # You cannot delete the branch you are standing on, and the default branch is never a target.
  git -C "$d" checkout -q burndown/add-a-dark-theme
  _bb discard add-a-dark-theme; [ "$status" -eq 5 ]
  git -C "$d" checkout -q main
  _bb discard main; [ "$status" -eq 6 ]
  # Discard is genuinely one step, and leaves nothing behind.
  _bb discard add-a-dark-theme; [ "$status" -eq 0 ]
  _bb list; [ -z "$output" ]
  [ "$(git -C "$d" rev-list --count main)" -eq 1 ]
}

@test "candidates: does not feed on prose ABOUT markers, only real annotations" {
  # The first run of this generator against its own repo returned four candidates that were all
  # documentation EXPLAINING what a TODO signal is — including its own source comments. A
  # generator that reads its own definition as input is a mirror, not a signal.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  printf 'x=1  # TODO: cache this\n'                 > "$d/a.sh"
  printf '# Guide\nWe write TODO: markers like this.\n' > "$d/guide.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.sh"* ]]        # a real annotation in code is still a candidate
  [[ "$output" != *"guide.md"* ]]    # prose about markers is not
  [[ "$output" != *"candidates.sh"* ]]  # and never its own source
}

@test "tq report: a park shows its rec:, and 'next' names the decision when nothing is buildable" {
  # A park is REQUIRED to carry `options:`/`rec:` so the review is a decision and not a rubber
  # stamp — and the 72-char truncation cut at exactly the point where `rec:` begins, so the
  # convention was stored and then hidden in the one place anyone reads it.
  export CLAUDE_COMPANION_SESSION_ID=sRec
  local d="$CLAUDE_COMPANION_TASKS_DIR/sRec"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend — options: A) sqlite (one file, needs a dep) B) plain files (no dep, slower); rec: A — the dep is already vendored",status:"pending"}' > "$d/1.json"
  run "$TQ" report
  [ "$status" -eq 0 ]
  [[ "$output" == *"└ rec: A — the dep is already vendored"* ]]   # the deciding half survives
  # With nothing buildable, "next" must not point at a task — it must name the decision.
  [[ "$output" == *"nothing left to build"* ]]
  [[ "$output" != *"→ next: #1"* ]]

  # A park WITHOUT a rec has no continuation line to show — and must not invent one.
  jq -n '{id:"2",subject:"❓ [parked] something undecided",status:"pending"}' > "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"something undecided"* ]]
  [ "$(printf '%s' "$output" | grep -c '└ rec:')" -eq 1 ]

  # Buildable work still wins: `next` stays mechanical and points at the open task, not the park.
  jq -n '{id:"3",subject:"do the actual thing",status:"pending"}' > "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #3"* ]]
  [[ "$output" != *"nothing left to build"* ]]
}

@test "autopilot pause/resume: a review is transparent to the drain (R83)" {
  # Review had to turn autopilot OFF to ask anything (the ask-guard blocks questions), which meant
  # reviewing was a decision to stop working and the owner re-armed by hand every time. Pause
  # records that it WAS armed; resume puts it back.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  _ap() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$repo" "$st" "$ROOT/bin/autopilot.sh" "$@"; }

  _ap pause; [[ "$output" == *"already off"* ]]          # clean no-op when it was never armed
  _ap resume; [[ "$output" == *"not paused"* ]]          # and resume must not arm it from nothing
  _ap status; [ "$output" = off ]

  _ap on >/dev/null; _ap pause; [[ "$output" == *"PAUSED"* ]]
  _ap status; [ "$output" = off ]                        # disarmed, so the ask-guard lets questions through
  _ap resume; [[ "$output" == *"RESUMED"* ]]
  _ap status; [ "$output" = on ]                         # ...and the drain picks back up

  # AN EXPLICIT `off` DURING A REVIEW OUTRANKS A PENDING RESUME. Without this, saying "stop" mid
  # review would be silently undone by the review finishing.
  _ap on >/dev/null; _ap pause >/dev/null; _ap off >/dev/null
  _ap resume; [[ "$output" == *"not paused"* ]]
  _ap status; [ "$output" = off ]
}

@test "tq report: a parks-only queue names the next action, not just the counts" {
  # Asked to "continue" with nothing buildable, the honest answer is not silence — it is which
  # command clears the pile. Mechanical, so it survives a compaction without costing injected prose.
  export CLAUDE_COMPANION_SESSION_ID=sNx
  local d="$CLAUDE_COMPANION_TASKS_DIR/sNx"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] a decision; rec: A",status:"pending"}'    > "$d/1.json"
  jq -n '{id:"2",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"decision(s) for you"* ]]
  [[ "$output" == *"manual job(s) only you can do"* ]]   # ⏳ is the owner's to-do list
  [[ "$output" == *"/companion:review"* ]]
  [[ "$output" == *"resumes autopilot if it was on"* ]]
}

@test "burn-down: a branch can NEVER exist without a manifest, even with the mode ARMED (R82)" {
  # THE GAP THAT HID THIS: every earlier test used a state dir where the burn-down flag was never
  # set — so the suite only ever exercised the one state the feature cannot really run in. The ON
  # flag is a FILE at $STATE/burndown/<enc>; the manifest dir was a DIRECTORY at the same path, so
  # armed, mkdir failed, no manifest was written, and start still exited 0 with a branch created.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  ( cd "$d" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" burndown on ) >/dev/null
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" start "1|parked|add retry backoff"
  [ "$status" -eq 0 ]
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" show add-retry-backoff
  [ "$status" -eq 0 ]; [[ "$output" == *"must default to OFF"* ]]
  # ...and arming still works afterwards — the two must not fight over one path.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" burndown status' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$output" = on ]
  # An unwritable manifest dir must abort BEFORE the branch exists, not after.
  local d2 st2; d2="$(_tmpd)"; st2="$(_tmpd)"
  git -C "$d2" init -q -b main; git -C "$d2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  chmod 555 "$st2"
  run env BURNDOWN_ROOT="$d2" CLAUDE_COMPANION_STATE_DIR="$st2" bash "$ROOT/bin/burndown-branch.sh" start "1|parked|thing"
  chmod 755 "$st2"
  [ "$status" -eq 7 ]
  [ "$(git -C "$d2" branch --list 'burndown/*' | wc -l)" -eq 0 ]
}

@test "burn-down: parks and blocked items are NOT buildable work and must not block it (R82)" {
  # Counting ❓/⏳ as "queued work" made rank 1 — the highest-signal source — unreachable, stopped
  # the documented loop after one iteration (step 6 parks a ❓, which blocked step 1), and made the
  # 3-branch backpressure unreachable. One long-lived ⏳ disabled the mode permanently.
  local d st tk; d="$(_tmpd)"; st="$(_tmpd)"; tk="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$st/burndown" "$tk/s1"; _stamp_root "$tk/s1" "$d"
  touch "$(_flagpath "$st" burndown "$d")"
  local n; n="$(date +%s)"
  printf '%s 20 %s 10 %s\n' "$n" "$((n+7200))" "$((n+86400))" > "$st/ratelimit"
  _bd2() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" bash "$ROOT/bin/burn-down.sh" status; }
  jq -n '{id:"1",subject:"❓ [parked] a decision; rec: A",status:"pending"}'    > "$tk/s1/1.json"
  jq -n '{id:"2",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$tk/s1/2.json"
  _bd2; [[ "$output" == BURN:* ]]                      # neither is work this loop could pick up
  jq -n '{id:"3",subject:"actual buildable work",status:"pending"}' > "$tk/s1/3.json"
  _bd2; [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]   # real work still wins
}

@test "autopilot pause: refuses to disarm when it cannot record the paused state (R83)" {
  # The first version cleared the flag unconditionally, so an unwritable state dir silently and
  # PERMANENTLY lost autopilot while printing a message promising it would come back — destroying
  # the exact state this verb exists to protect.
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  _ap2() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$d" "$st" "$ROOT/bin/autopilot.sh" "$@"; }
  _ap2 on >/dev/null
  chmod 555 "$st"
  _ap2 pause
  chmod 755 "$st"
  [ "$status" -ne 0 ]; [[ "$output" == *"NOT paused"* ]]
  _ap2 status; [ "$output" = on ]        # still ARMED — failing loud beats losing it silently
}

@test "burndown-branch: a slug cannot escape the manifest dir (R82)" {
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  printf 'keep me\n' > "$st/victim.md"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" discard '../../victim'
  [ "$status" -eq 8 ]
  [ -f "$st/victim.md" ]                 # discard reached OUTSIDE the state dir before this guard
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" show '../../victim'
  [ "$status" -eq 8 ]
}

@test "ask-guard: a blocked question is PARKED, not just denied (R36 + owner-asked)" {
  # Denying alone made the block a dead end: the guard is enforced, the parking that should follow
  # was advisory. The hook already holds the payload, so it writes a park carrying the real options.
  local d st tk; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  ( cd "$d" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" on ) >/dev/null
  local pay; pay="$(jq -nc --arg c "$d" '{cwd:$c,session_id:"sAsk",tool_input:{questions:[{question:"Which cache backend?",header:"Cache",options:[{label:"sqlite (Recommended)",description:"dep already vendored"},{label:"plain files",description:"no dep, slower"}]}]}}')"
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' _ "$pay" "$st" "$tk" "$ROOT/bin/ask-guard.sh"
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecision')" = deny ]
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"ALREADY PARKED FOR YOU"* ]]
  run env CLAUDE_COMPANION_SESSION_ID=sAsk CLAUDE_COMPANION_TASKS_DIR="$tk" "$TQ" list
  [[ "$output" == *"Which cache backend?"* ]]
  [[ "$output" == *"sqlite"* ]] && [[ "$output" == *"plain files"* ]]   # the real options, not a stub
  [[ "$output" != *"rev:"* ]]        # NEVER rev: — the hook cannot know if it is reversible
  # Re-asking must not stack a duplicate.
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' _ "$pay" "$st" "$tk" "$ROOT/bin/ask-guard.sh"
  run env CLAUDE_COMPANION_SESSION_ID=sAsk CLAUDE_COMPANION_TASKS_DIR="$tk" "$TQ" list
  [ "$(printf '%s' "$output" | grep -c 'Which cache backend')" -eq 1 ]
}

@test "autopilot resume: refuses and KEEPS the marker when it cannot re-arm (R83)" {
  # The mirror of the pause fix, and it was missed: resume deleted the marker FIRST, then tried to
  # arm without checking, then printed "RESUMED" unconditionally — leaving autopilot off, the marker
  # gone, and no way back. A half-corrected defect class is worse than an uncorrected one, because
  # the ledger says it is handled.
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  _ar() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$d" "$st" "$ROOT/bin/autopilot.sh" "$@"; }
  _ar on >/dev/null; _ar pause >/dev/null
  rm -rf "$st/autopilot"; chmod 555 "$st"
  _ar resume
  chmod 755 "$st"
  [ "$status" -ne 0 ]; [[ "$output" == *"NOT resumed"* ]]
  [ "$(find "$st/autopilot-paused" -type f | wc -l)" -eq 1 ]   # marker KEPT — recoverable
  _ar resume; [[ "$output" == *"RESUMED"* ]]                    # and the retry works
  _ar status; [ "$output" = on ]
}

@test "tq: concurrent adds cannot lose a task — a HOOK is now a writer (R84)" {
  # tq's header said id allocation needed no locking because "one model drives tq serially". The
  # ask-guard made that false: two writers computed the same id and the second mv silently
  # overwrote the first, so parked DECISIONS disappeared while the model was told they were saved.
  export CLAUDE_COMPANION_SESSION_ID=sRace
  local i
  for i in 1 2 3 4 5 6; do "$TQ" add "concurrent subject $i" >/dev/null 2>&1 & done
  wait
  local dir="$CLAUDE_COMPANION_TASKS_DIR/sRace"
  [ "$(ls "$dir"/*.json | wc -l)" -eq 6 ]
  [ "$(cat "$dir"/*.json | jq -r .subject | sort -u | wc -l)" -eq 6 ]   # none lost
  [ "$(cat "$dir"/*.json | jq -r .id | sort | uniq -d | wc -l)" -eq 0 ] # no duplicate ids
}

@test "ask-guard: parks into the PAYLOAD's repo and survives a relative invocation (R84)" {
  # Two silent failures in one path. (1) tq stamps a session store from $PWD, so running the hook
  # from elsewhere poisoned the whole session's queue — invisible to resume, review, burn-down and
  # the status line, while the model was told the decision was parked. (2) $SELF is RELATIVE when
  # the hook is invoked by a relative path, so cd-ing to the repo broke tq resolution entirely:
  # no task written, success still reported.
  local d st tk elsewhere; d="$(_tmpd)"; git -C "$d" init -q
  st="$(_tmpd)"; tk="$(_tmpd)"; elsewhere="$(_tmpd)"
  ( cd "$d" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" on ) >/dev/null
  local pay; pay="$(jq -nc --arg c "$d" '{cwd:$c,session_id:"sPay",tool_input:{questions:[{question:"Which backend?",options:[{label:"A"},{label:"B"}]}]}}')"
  # Invoked BY A RELATIVE PATH (cwd = the plugin dir, script = bin/ask-guard.sh) while the payload
  # points at a different repo. An absolute path here would not exercise the bug at all — the whole
  # failure is that $SELF stays relative and stops resolving once the hook cd's into the payload's
  # repo. Asserting "relative" while passing an absolute path is a test that cannot fail.
  run bash -c 'cd "$5" && printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' \
      _ "$pay" "$st" "$tk" "bin/ask-guard.sh" "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(ls "$tk/sPay"/*.json 2>/dev/null | wc -l)" -eq 1 ]      # the task actually got written
  # Compare against the RESOLVED root — tq stamps what git reports, which on macOS is the
  # /private/var/... form rather than the raw mktemp path.
  [ "$(cat "$tk/sPay/.root")" = "$(git -C "$d" rev-parse --show-toplevel)" ]   # the PAYLOAD's repo
  [[ "$(printf '%s' "$output" | jq -r '.hookSpecificOutput.permissionDecisionReason')" == *"ALREADY PARKED FOR YOU"* ]]
}

@test "burndown-branch: refuses a slug that collides with the default branch (R82)" {
  # `discard` refuses anything named like the default branch, so minting one created a branch that
  # could never be removed and counted against the backpressure cap forever.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" start "1|parked|Main!"
  [ "$status" -eq 9 ]
  [ "$(git -C "$d" branch --list 'burndown/*' | wc -l)" -eq 0 ]
}

@test "prompt-continue: a bare 'continue' with a parked pile routes to review FIRST (R85)" {
  # The owner types "continue" and gets more building on top of decisions they were never asked
  # about. As STEERING prose this is a reflex the model can skip; as an injection it cannot be,
  # and it costs nothing in every session where nothing is parked.
  local d st tk; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$tk/sP"; _stamp_root "$tk/sP" "$d"
  _pc() { run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' \
            _ "$(jq -nc --arg c "$d" --arg p "$1" '{cwd:$c,session_id:"sP",prompt:$p}')" "$st" "$tk" "$ROOT/bin/prompt-continue.sh"; }

  _pc continue; [ "$status" -eq 0 ]; [ -z "$output" ]        # empty queue → silent
  jq -n '{id:"1",subject:"plain buildable work",status:"pending"}' > "$tk/sP/1.json"
  _pc continue; [ -z "$output" ]                              # buildable work → just drain, silently
  jq -n '{id:"2",subject:"❓ [parked] pick a backend; rec: A",status:"pending"}' > "$tk/sP/2.json"
  _pc continue
  [[ "$output" == *"/companion:review"* ]]; [[ "$output" == *"WHOLE pile"* ]]
  [[ "$output" == *"no pause is needed"* ]]                   # autopilot off
  # ARMED: it must say pause first, because the ask-guard would otherwise PARK the review's own
  # questions instead of asking them — the review would silently accomplish nothing.
  mkdir -p "$st/autopilot"; touch "$(_flagpath "$st" autopilot "$d")"
  _pc continue
  [[ "$output" == *"autopilot.sh pause"* ]] && [[ "$output" == *"resume"* ]]
  # A ⏳ alone counts too — manual jobs are equally the owner's.
  rm "$tk/sP/2.json"; jq -n '{id:"3",subject:"⏳ [blocked] go plug in the device",status:"pending"}' > "$tk/sP/3.json"
  _pc continue; [[ "$output" == *"/companion:review"* ]]
  # A REAL instruction is never second-guessed, even when it starts with the word.
  _pc "continue by refactoring the parser"; [ -z "$output" ]
  _pc "Keep going."; [[ "$output" == *"/companion:review"* ]]   # punctuation and case tolerated
}

@test "check.sh actually INVOKES the portability lint, both halves (wiring guard)" {
  # bats cannot run check.sh (check.sh runs bats), so this is structural — the same shape as the
  # doc-lint wiring guard. Without it, check.sh could quietly stop calling the linter, or call only
  # one half, and every test above would still pass while the gate protected nothing.
  run grep -c 'portability-lint\.sh all' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
}

@test "portability-lint: catches the two traps that keep shipping red CI, and honours its markers" {
  # These two guards were written INLINE in check.sh with declared mutations and no tests, so the
  # mutation gate correctly reported both as HOLES — a guard that cannot fail is not a guard. They
  # live in dev/ now for the same reason doc-lint does: so the suite can reach them.
  local d; d="$BATS_TEST_TMPDIR/pl"; mkdir -p "$d"
  local L="$DEV/portability-lint.sh"

  # SC2015: `A && B || C` reads as if-then-else and is not. CI's shellcheck flags it; the local
  # build does not, which is exactly how it shipped red three times.
  printf '%s\n' '[ -n "$a" ] && [ -n "$b" ] || exit 1' > "$d/bad-sc.sh"
  run "$L" sc2015 "$d/bad-sc.sh"; [ "$status" -eq 1 ]; [[ "$output" == *"bad-sc.sh"* ]]
  printf '%s\n' '[ -n "$a" ] && [ -n "$b" ] || exit 1   # sc2015-ok: unless both held' > "$d/ok-sc.sh"
  run "$L" sc2015 "$d/ok-sc.sh"; [ "$status" -eq 0 ]; [ -z "$output" ]

  # GNU-only escapes: BSD sed/grep read \+ \? \| as LITERALS. This one made burn-down unable to
  # create a single branch on macOS while Linux stayed green.
  printf '%s\n' "x=\$(printf a | sed -e 's/[a-z]\\+/-/g')" > "$d/bad-bre.sh"
  run "$L" bre "$d/bad-bre.sh"; [ "$status" -eq 1 ]; [[ "$output" == *"bad-bre.sh"* ]]
  # An escaped pipe inside an ERE is correct, not a violation — -E/-r invocations are exempt.
  printf '%s\n' "grep -nE 'a\\|b' f" > "$d/ere.sh"
  run "$L" bre "$d/ere.sh"; [ "$status" -eq 0 ]
  printf '%s\n' "sed -e 's/a\\+/b/' f   # bre-ok: deliberate literal plus" > "$d/ok-bre.sh"
  run "$L" bre "$d/ok-bre.sh"; [ "$status" -eq 0 ]

  # A comment mentioning the shape is not code.
  printf '%s\n' '# never write [ a ] && [ b ] || c' > "$d/comment.sh"
  run "$L" all "$d/comment.sh"; [ "$status" -eq 0 ]
  # fixtures: a bare `$(mktemp -d)` in a test leaks a dir bats would otherwise have removed.
  # Checked HERE rather than by a bats case, because a test that greps for the pattern contains
  # the pattern and so fails on itself forever — which is exactly what happened when I tried.
  # Build the leaky line from PARTS: writing the literal into this file would make the fixtures
  # lint flag companion-core.bats itself — the same self-reference that killed the bats-based
  # version of this guard.
  local mk='mktemp -d'
  printf 'repo="$(%s)"\n' "$mk" > "$d/leaky.bats"
  run "$L" fixtures "$d/leaky.bats"; [ "$status" -eq 1 ]; [[ "$output" == *"leaky.bats"* ]]
  printf '%s\n' 'repo="$(_tmpd)"' > "$d/clean.bats"
  run "$L" fixtures "$d/clean.bats"; [ "$status" -eq 0 ]; [ -z "$output" ]

  # `all` fails if EITHER lints fail.
  run "$L" all "$d/bad-sc.sh" "$d/bad-bre.sh"; [ "$status" -eq 1 ]
  run "$L" all "$d/ok-sc.sh" "$d/ok-bre.sh" "$d/ere.sh"; [ "$status" -eq 0 ]
}

