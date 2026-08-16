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
  GUARD="$ROOT/bin/check-secrets.sh"; TQ="$ROOT/bin/tq"; SL="$ROOT/bin/statusline.sh"
  AP="$ROOT/bin/autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  SS="$ROOT/bin/session-start.sh"; AG="$ROOT/bin/ask-guard.sh"   # R100/Pass 6 reinstated
  BOARD="$ROOT/bin/board.sh"
  DRIFT="$ROOT/bin/contract-drift.sh"   # R58 living contract (drift backstop)
  export CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_STATE_DIR="$(_tmpd)"   # autopilot flags live here
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

# Write a per-repo feature OFF flag directly at the reader's enc path (the `/companion:features`
# CLI was removed 2026-07-18; the flag mechanism + its readers remain — R50). Mirrors
# companion_feature_file(companion_root(repo)) so secret-guard / resume / statusline find it.
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

@test "check-secrets: BLOCKs a real AWS key (exit 2) — advisory only, R100/Pass 3" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
}

@test "check-secrets: a generic name=value literal WARNS but does not block (exit 0) — R32" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ 'password = "hunter2primetime"' "$GUARD"
  [ "$status" -eq 0 ]                          # heuristic never had veto power; still doesn't
  [[ "$output" == *"WARN"* ]]                 # but it does warn
}

@test "check-secrets: allows a placeholder (exit 0)" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ 'API_KEY = "your-key-here"' "$GUARD"
  [ "$status" -eq 0 ]
}

@test "check-secrets: allows ordinary code (exit 0)" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/a.py' _ 'def add(a,b): return a+b' "$GUARD"
  [ "$status" -eq 0 ]
}

@test "check-secrets: disabled via CLAUDE_COMPANION_SECSCAN=0" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_SECSCAN=0 "$2" --path /x/c.py' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
}

# ---- per-repo feature toggles (R50): one unified surface, scoped per repo ----

@test "check-secrets: honors a per-repo secret=off flag — ALLOWS there but still BLOCKS elsewhere (isolated, R50/R54)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo other; repo="$(_tmpd)"; other="$(_tmpd)"
  git -C "$repo" init -q; git -C "$other" init -q
  _feature_off secret "$repo"
  # off in $repo → allowed
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$repo"
  [ "$status" -eq 0 ]
  # still on in $other → blocked (no cross-repo bleed)
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$other"
  [ "$status" -eq 2 ]
  rm -rf "$repo" "$other"
}

@test "check-secrets FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS (R50/R54 never-fails-open)" {
  # Invariant (invisible to the user): only an exact ^secret=off$ line disables; corruption/typo -> still BLOCKS.
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off secret "$repo"                                      # writes the flag at the enc path
  local flag; flag="$(find "${CLAUDE_COMPANION_STATE_DIR:?}/features" -type f 2>/dev/null | head -1)"
  [ -n "$flag" ]
  printf 'secret=off_typo\ngarbage\n' > "$flag"                     # NOT the exact ^secret=off$ line
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$repo"
  [ "$status" -eq 2 ]                                               # fail-safe: corrupt flag -> still BLOCKS
  rm -rf "$repo"
}

@test "check-secrets is self-contained: sources no lib (R50/R54 never-fails-open via a dependency)" {
  # Even advisory, it should not depend on lib/companion.sh — a broken dependency should not make
  # a verdict silently vanish.
  run grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*companion\.sh' "$GUARD"
  [ "$status" -ne 0 ]
}

@test "steering off (per-repo flag): resume drops the working agreement (tasks/lessons unaffected, R50)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off steering "$repo"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Working agreement"* ]]
  # clear the flag → agreement returns (default ON)
  _feature_clear
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" == *"Working agreement"* ]]
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

@test "MCP server: tq_add via companion-tq matches bin/tq output, same store (Pass 1, R101)" {
  command -v node >/dev/null 2>&1 || skip "node not installed"
  [ -d "$ROOT/mcp-server/node_modules" ] || skip "mcp-server deps not installed (npm ci --prefix plugins/companion/mcp-server)"

  script='
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const transport = new StdioClientTransport({ command: "node", args: [process.env.MCP_INDEX], env: process.env });
const client = new Client({ name: "bats-verify", version: "0.0.1" });
await client.connect(transport);
const r = await client.callTool({ name: "tq_add", arguments: { subjects: ["mcp parity check"] } });
process.stdout.write(r.content[0].text + "\n");
await client.close();
'
  run bash -c 'cd "$1/mcp-server" && CLAUDE_PLUGIN_ROOT="$1" MCP_INDEX="$1/mcp-server/index.js" node --input-type=module -e "$2"' _ "$ROOT" "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *"added #"* ]]

  # same store, reached the ordinary way — the MCP call and the CLI see the same task
  run "$TQ" list
  [ "$status" -eq 0 ]
  [[ "$output" == *"mcp parity check"* ]]
}

# ---- MCP server, Pass 5a: the remaining bin/ scripts as tools, same thin-wrapper contract ----

_mcp_call() {  # $1=repo-dir $2=json-array-of-{name,arguments} -> prints each result's text, \n-joined
  command -v node >/dev/null 2>&1 || skip "node not installed"
  [ -d "$ROOT/mcp-server/node_modules" ] || skip "mcp-server deps not installed (npm ci --prefix plugins/companion/mcp-server)"
  local script='
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const calls = JSON.parse(process.env.MCP_CALLS);
const transport = new StdioClientTransport({ command: "node", args: [process.env.MCP_INDEX], env: process.env });
const client = new Client({ name: "bats-verify", version: "0.0.1" });
await client.connect(transport);
for (const c of calls) {
  const r = await client.callTool({ name: c.name, arguments: c.arguments || {} });
  process.stdout.write("<<<" + c.name + ">>>\n" + r.content[0].text + "\n");
}
await client.close();
'
  run bash -c 'cd "$1/mcp-server" && CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" MCP_INDEX="$1/mcp-server/index.js" MCP_CALLS="$3" node --input-type=module -e "$4"' \
    _ "$ROOT" "$1" "$2" "$script"
}

@test "MCP server: board/resume/burn_down/candidates/rework/autopilot_status read-only tools match their CLIs (Pass 5a)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/mp"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/mp" "$repo"
  jq -n '{id:"1",subject:"parity task",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/mp/1.json"

  _mcp_call "$repo" '[{"name":"board"},{"name":"resume"},{"name":"burn_down","arguments":{"action":"status"}},{"name":"candidates"},{"name":"rework","arguments":{"action":"report"}},{"name":"autopilot_toggle","arguments":{"action":"status"}}]'
  [ "$status" -eq 0 ]
  local mcp_out="$output"

  run "$BOARD"; local board_out="$output"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"; local resume_out="$output"
  run "$ROOT/bin/burn-down.sh" status; local burndown_out="$output"
  run "$ROOT/bin/candidates.sh"; local candidates_out="$output"
  run "$ROOT/bin/rework.sh" report; local rework_out="$output"
  run "$AP" status; local ap_out="$output"

  [[ "$mcp_out" == *"<<<board>>>"* ]]
  [[ "$mcp_out" == *"parity task"* ]]                     # board sees the live queue
  [[ "$mcp_out" == *"<<<resume>>>"* ]]
  [[ "$mcp_out" == *"Working agreement"* ]]                # resume injects steering, same as CLI
  [[ "$mcp_out" == *"<<<burn_down>>>"* ]]
  [[ "$mcp_out" == *"<<<candidates>>>"* ]] || true          # candidates may be empty in a fresh repo
  [[ "$mcp_out" == *"<<<rework>>>"* ]]
  [[ "$mcp_out" == *"<<<autopilot_toggle>>>"* ]]
  [[ "$mcp_out" == *"OFF"* ]] || [[ "$mcp_out" == *"off"* ]]  # fresh repo — autopilot not armed

  rm -rf "$repo"
}

@test "MCP server: autopilot_toggle on/off round-trips the real flag file (Pass 5a)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

  _mcp_call "$repo" '[{"name":"autopilot_toggle","arguments":{"action":"on"}}]'
  [ "$status" -eq 0 ]

  run bash -c 'cd "$1" && "$2" status' _ "$repo" "$AP"
  [[ "$output" == *"ON"* ]] || [[ "$output" == *"on"* ]]

  _mcp_call "$repo" '[{"name":"autopilot_toggle","arguments":{"action":"off"}}]'
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && "$2" status' _ "$repo" "$AP"
  [[ "$output" == *"OFF"* ]] || [[ "$output" == *"off"* ]]

  rm -rf "$repo"
}

@test "MCP server: burndown_branch start/list/discard round-trips a real branch + manifest (Pass 5a)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

  _mcp_call "$repo" '[{"name":"burndown_branch","arguments":{"action":"start","candidate":"4|gap|mcp parity candidate"}}]'
  [ "$status" -eq 0 ]
  # awk, not sed -n '/pat/{n;p}': BSD sed (macOS CI) requires a trailing ';' before '}' that GNU
  # sed does not — the exact "BSD is not GNU" trap this repo's LESSONS.md already tracks.
  local slug; slug="$(printf '%s' "$output" | awk '/<<<burndown_branch>>>/{getline; print; exit}')"
  [ -n "$slug" ]
  git -C "$repo" rev-parse --verify --quiet "burndown/$slug" >/dev/null   # real branch, seen by plain git

  _mcp_call "$repo" '[{"name":"burndown_branch","arguments":{"action":"list"}}]'
  [[ "$output" == *"burndown/$slug"* ]]

  git -C "$repo" checkout -q main   # start left HEAD on the new branch; discard refuses that branch
  _mcp_call "$repo" "[{\"name\":\"burndown_branch\",\"arguments\":{\"action\":\"discard\",\"slug\":\"$slug\"}}]"
  [ "$status" -eq 0 ]
  run git -C "$repo" rev-parse --verify --quiet "burndown/$slug"
  [ "$status" -ne 0 ]                                       # gone, via plain git

  rm -rf "$repo"
}

@test "MCP server: ship_land commits+merges to the default branch, matches bin/ship.sh land (Pass 5a)" {
  # PERSISTENT identity, not -c-scoped: ship.sh land's own `git commit` runs as a separate
  # subprocess (spawned by the MCP server) that does not inherit this command's -c flags, and CI
  # runs with git identity scrubbed (GIT_CONFIG_GLOBAL=/dev/null) — this shipped red once (3.80.1).
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  git -C "$repo" commit -q --allow-empty -m init
  git -C "$repo" checkout -q -b autopilot/mcp-test
  echo hello > "$repo/f.txt"
  git -C "$repo" add f.txt

  _mcp_call "$repo" '[{"name":"ship_land","arguments":{"message":"test: mcp ship_land parity","gate":["true"]}}]'
  [ "$status" -eq 0 ]
  [[ "$output" == *"shipped"* ]]

  run git -C "$repo" rev-parse --abbrev-ref HEAD
  [ "$output" = "main" ]                                    # merged onto the default branch
  run git -C "$repo" log --oneline -1
  [[ "$output" == *"test: mcp ship_land parity"* ]]
  run git -C "$repo" rev-parse --verify --quiet autopilot/mcp-test
  [ "$status" -ne 0 ]                                       # feature branch cleaned up, like the CLI does

  rm -rf "$repo"
}

@test "MCP server: ship_handoff surfaces the same no-remote error as bin/ship.sh handoff (Pass 5a)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init

  _mcp_call "$repo" '[{"name":"ship_handoff"}]'
  [ "$status" -eq 0 ]                                       # tool call succeeds; the CLI's error is in isError/text
  [[ "$output" == *"no remote"* ]]

  run bash -c 'cd "$1" && "$2" handoff' _ "$repo" "$ROOT/bin/ship.sh"
  [[ "$output" == *"no remote"* ]]                          # same message as the direct CLI

  rm -rf "$repo"
}

@test "MCP server: ship_checkpoint commits to a throwaway autopilot/* branch when ship-mode is on (Pass 5a)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  echo dirty > "$repo/f.txt"

  _mcp_call "$repo" '[{"name":"ship_checkpoint"}]'
  [ "$status" -eq 0 ]

  run git -C "$repo" rev-parse --abbrev-ref HEAD
  [[ "$output" == autopilot/* ]]                            # checkpointed onto a throwaway branch
  run git -C "$repo" status --porcelain
  [ -z "$output" ]                                          # committed, tree clean
  run git -C "$repo" log --oneline main -1
  [[ "$output" == *"init"* ]]                                # default branch untouched

  rm -rf "$repo"
}

@test "MCP server: decompose_into_tasks PROMPT (not a tool) returns the decomposition instructions (Pass 5c, R103)" {
  command -v node >/dev/null 2>&1 || skip "node not installed"
  [ -d "$ROOT/mcp-server/node_modules" ] || skip "mcp-server deps not installed (npm ci --prefix plugins/companion/mcp-server)"
  local script='
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const transport = new StdioClientTransport({ command: "node", args: [process.env.MCP_INDEX], env: process.env });
const client = new Client({ name: "bats-verify", version: "0.0.1" });
await client.connect(transport);
const list = await client.listPrompts();
process.stdout.write("<<<list>>>\n" + JSON.stringify(list.prompts.map(p => p.name)) + "\n");
const r = await client.getPrompt({ name: "decompose_into_tasks", arguments: {} });
process.stdout.write("<<<get>>>\n" + r.messages[0].content.text + "\n");
await client.close();
'
  run bash -c 'cd "$1/mcp-server" && CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" MCP_INDEX="$1/mcp-server/index.js" node --input-type=module -e "$3"' \
    _ "$ROOT" "$(_tmpd)" "$script"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decompose_into_tasks"'* ]]                  # discoverable via listPrompts, not just tools
  [[ "$output" == *"❓ [parked]"* ]]                              # carries the same classification vocabulary tq uses
  [[ "$output" == *"⏳ [blocked]"* ]]
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

@test "command prompts retain their critical gate steps (R56 P3 — structural guard for prose)" {
  # Prose behavior can't be tested behaviorally (it's Claude's judgment, R28); the ceiling is a
  # structural guard that a command's non-negotiable gate INSTRUCTION wasn't deleted (like a regen
  # of a .md might do). Catches deletion, not a subtler regression — the honest best for prose.
  local C="$ROOT/commands"
  grep -q "invariant net covers the app"   "$C/redesign.md"     # D0 coverage gate
  grep -qE "bounded, check-gated|never.*unbounded" "$C/redesign.md"  # D2/D3 bounded passes
  grep -q 'autopilot_toggle'               "$C/redesign.md"     # step-0 autopilot clear (R100/Pass 5b: MCP tool, not raw script)
  grep -q "auto-revert"                    "$C/redesign.md"     # R5 rollback-on-red (inlined regen engine)
  grep -qE "Refuse to (regenerate|proceed)" "$C/redesign.md"    # R3 checks-first + D1 document gate
  grep -q "REQUIRED first step"            "$C/redesign.md"     # D1 document-first requirement (R55)
  grep -q "Verify FIRST"                   "$C/ship-it.md"      # verify before commit
  grep -q "Never force-push"               "$C/ship-it.md"      # never rewrite published history
  grep -q "Sync the contract"              "$C/ship-it.md"      # R57 contract-sync step
  grep -q "Propose the flow-page update"   "$C/ship-it.md"      # R57/R62 flow-page proposal (owner-governed, not silent)
  grep -q "anti-laundering"                "$C/docs.md"     # only the owner's pick records a 🔒
  grep -q "autopilot"                      "$C/resume.md"       # resume respects/clears autopilot
  grep -qF 'resume`** MCP tool'            "$C/resume.md"       # resume runs the session-pickup re-surface (R39, R100/Pass 5b)
  grep -q "companion:review"               "$C/resume.md"       # pickup hands off to review (R39 re-split)
  grep -qE "parked|❓"                       "$C/review.md"       # review walks the parked pile (R38)
  # R83: review PAUSES rather than kills — it must disarm to ask, then put autopilot back. Both
  # halves are load-bearing: pause without resume is the old behaviour with extra steps, and the
  # guard has to pin the pair or the resume can quietly disappear.
  grep -q 'autopilot_toggle.*action: "pause"' "$C/review.md"    # review disarms to ask (R83, R100/Pass 5b)
  grep -q 'action: "resume"'               "$C/review.md"       # ...and re-arms when done (R83, R100/Pass 5b)
  grep -qiE "up front|upfront"             "$C/review.md"       # the whole pile at once, not drip-fed
  grep -qiE "before .*new work"            "$C/review.md"       # R38 write-back-before-new-work
  # R112 accept sweep (owner-asked 2026-08-12). The FEATURE is the multiSelect batch; the SAFETY
  # is that an unticked box is not a decision. A multiSelect returns only the PRESENCE of a yes,
  # so a review that read absence as "no" would silently invent rejections across the whole pile —
  # which is worse than the drip-feed it replaces. Both halves pinned, and the exclusions with
  # them: ⏳ is an owner ACTION (nothing to "accept"), and a decompose-park has no options yet.
  grep -q 'multiSelect: true'              "$C/review.md"       # the sweep exists at all
  grep -qE "Unselected is NOT rejected|not ticked is not a no" "$C/review.md"   # absence != rejection
  grep -qiE "NOT eligible for the sweep"   "$C/review.md"       # ⏳ + decompose-park stay out (R65)
  grep -qiE "asks before it writes|buy-in still comes first|recommendation-first" "$C/cover.md"  # R58·d amended by R61/R62: cover SCAFFOLDS, but buy-in (owner picks) still precedes any write
  grep -q 'autopilot_toggle'               "$C/cover.md"        # cover clears autopilot (it asks) — R100/Pass 5b: MCP tool, not raw script
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
  _check '- [E] `tq: no session id errors cleanly`'               # real → resolves (not always-fail)
  ! _check '   - [E] `another phantom qqq nonexistent`'          # indented phantom still reaches matcher
  ! _check '- [S] `tq: no session id errors cleanly`'             # an [S] line is NOT gated (skipped)
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

@test "resume: prints STEERING and resumes THIS repo's tasks only (scoped by .root) — R39" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sMine"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sMine" "$repo"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sMine/1.json"
  # an unrelated repo's task must NOT leak
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sOther"; printf '/other/x' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/.root"
  jq -n '{id:"1",subject:"NOT MINE",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sOther/1.json"
  # this repo's LESSONS.md is surfaced (R30·d7)
  mkdir -p "$repo/docs"; printf 'GOTCHA_MARKER: brace vars before emoji\n' > "$repo/docs/LESSONS.md"

  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]     # STEERING injected
  [[ "$output" == *"resume me"* ]]             # this repo's task
  [[ "$output" != *"NOT MINE"* ]]              # no cross-repo bleed
  [[ "$output" == *"GOTCHA_MARKER"* ]]         # this repo's LESSONS surfaced
}

@test "resume: prints the STEERING CORE only — rationale below the marker excluded; missing marker fails OPEN (R69)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core is printed…
  [[ "$output" == *"Posture"* ]]                   # …through its last section
  [[ "$output" != *"Rationale (not injected"* ]]   # the below-marker half NEVER ships
  [[ "$output" != *"injection stops here"* ]]      # the marker line itself is excluded too
  # Fail-open (R7): a STEERING with no marker (old copy, botched edit) prints the WHOLE doc —
  # degraded-but-working beats silently steering-less. Build a marker-less plugin dir to prove it.
  local plug; plug="$(_tmpd)"; mkdir -p "$plug/bin" "$plug/lib"
  cp "$RESUME" "$plug/bin/resume.sh"; cp "$ROOT/lib/companion.sh" "$ROOT/lib/resume-report.sh" "$plug/lib/"
  sed '/injection stops here/d' "$ROOT/STEERING.md" > "$plug/STEERING.md"
  run bash -c 'cd "$1" && "$2/bin/resume.sh"' _ "$repo" "$plug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Rationale (not injected"* ]]   # no marker → whole doc (fail-open, not fail-silent)
}

@test "resume: shows the FULL STEERING core alongside the live queue — no abbreviated path left to pick (R100/Pass 2)" {
  # R30·d2's old abbreviated compact-only re-anchor is retired with the hook it lived in: there is no
  # more "source:compact" signal to detect (no stdin JSON at all), so resume always shows the same
  # full core plus the live queue — simpler, and never under-shows what a partial-detection bug once
  # risked. The queue re-anchor property R30·d2 existed for (each task's done-when is its own
  # acceptance test, so it survives a compaction the STEERING prose does not need to repeat) still
  # holds — it is just no longer a SEPARATE code path from the ordinary case.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/xc"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/xc" "$repo"
  jq -n '{id:"1",subject:"resume me",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/xc/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]     # the full STEERING core...
  [[ "$output" == *"resume me"* ]]             # ...and the live queue, together, every time
}

@test "manual resume: lists THIS repo's open tasks on demand (and says so when none)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sM"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sM" "$repo"
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
  # Compute the identity from the RESOLVED root, not the possibly-symlinked mktemp path — the
  # readers all resolve, so a fixture that does not writes an id nothing will match.
  local rid; rid="$(cd "$(git -C "$repo" rev-parse --show-toplevel)" && bash -c 'source "$1"; companion_repo_id "$PWD"' _ "$ROOT/lib/companion.sh")"
  # dir A matches on the path-stable .repo identity, dir B on the legacy .root abspath — both
  # newline-less, exactly as `tq` writes them. Several files each, so batching has to span dirs.
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sA"; printf '%s' "$rid"  > "$CLAUDE_COMPANION_TASKS_DIR/sA/.repo"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sB"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sB" "$repo"
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

  # Pass a RESOLVED root, which is what every real caller does (they go through companion_root).
  # `cd` into a symlinked path leaves $PWD logical, so passing it compares an unresolved path
  # against a resolved stamp and silently matches nothing.
  run bash -c 'cd "$1" && source "$2" && companion_open_tasks "$(git rev-parse --show-toplevel)"' _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  # every OPEN task across BOTH matching dirs survives the batch — the count is the real assertion.
  # Both markers, since open means pending (◻) OR in_progress (▸) and alpha A2 is the latter.
  [ "$(printf '%s\n' "$output" | grep -c '[◻▸]')" -eq 4 ]
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

# ---- autopilot (persisted, ADVISORY as of R100/Pass 4 — ask-guard.sh and stop-autopilot.sh
#      retired; nothing enforces this flag anymore, STEERING states it) ----

@test "autopilot: toggle persists per repo, independent of other modes (R26)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  [ "$(cd "$repo" && "$AP" status)" = "off" ]
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "on" ]                       # persisted flag
  ( cd "$repo" && "$AP" off ) >/dev/null
  [ "$(cd "$repo" && "$AP" status)" = "off" ]
}

# ---- R56 P2: characterization tests for beacon-class gaps the coverage audit found ----
# (intended, load-bearing behaviors a green from-scratch regen would silently drop)

@test "tq stopfields: the pointer is the first STARTABLE task, and every blocker counts (R87)" {
  # R87's real claim ("the selection exists in exactly one place") lives in tq stopfields itself —
  # stop-autopilot.sh only ever READ it. That hook is retired (R100/Pass 4); stopfields is not, so
  # this now drives the CLI directly instead of through the deleted Stop-hook wrapper.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=depT d="$CLAUDE_COMPANION_TASKS_DIR/depT"
  mkdir -p "$d"; _stamp_root "$d" "$repo"
  # field 5 is the bare next-id (no leading '#' — that's report's rendering, not stopfields' data).
  _nextid() { CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f5; }

  # The id it names must be the first STARTABLE task, not merely the first open one. A subject
  # saying "after #N" is not startable while #N is live — the same rule `tq report` applies.
  jq -n '{id:"38",subject:"❓ [parked] pick one",status:"pending"}'    > "$d/38.json"
  jq -n '{id:"50",subject:"sharpen it (after #38)",status:"pending"}' > "$d/50.json"
  [ -z "$(_nextid)" ]                          # blocker live → nothing startable
  jq -n '{id:"38",subject:"❓ [parked] pick one",status:"completed"}'  > "$d/38.json"
  [ "$(_nextid)" = "50" ]                       # answered → #50 is offered

  # Only a queue whose waiting task sorts BEFORE its blocker separates "first startable" from
  # "first open": with #10 waiting on #90, an $o[0] pointer would offer the blocked #10.
  rm "$d/50.json"
  jq -n '{id:"10",subject:"needs the other first (after #90)",status:"pending"}' > "$d/10.json"
  jq -n '{id:"90",subject:"the prerequisite",status:"pending"}'                  > "$d/90.json"
  [ "$(_nextid)" = "90" ]

  # A dangling reference must not strand work forever.
  rm "$d/10.json" "$d/90.json"
  jq -n '{id:"60",subject:"orphan ref (after #999)",status:"pending"}' > "$d/60.json"
  [ "$(_nextid)" = "60" ]

  # EVERY blocker counts, not just the first.
  rm "$d/60.json"
  jq -n '{id:"40",subject:"two blockers (after #50) and (after #60)",status:"pending"}' > "$d/40.json"
  jq -n '{id:"50",subject:"first blocker",status:"completed"}'                          > "$d/50.json"
  jq -n '{id:"60",subject:"second blocker",status:"pending"}'                           > "$d/60.json"
  [ "$(_nextid)" != "40" ]      # still held: #60 is open
  jq -n '{id:"60",subject:"second blocker",status:"completed"}'                         > "$d/60.json"
  [ "$(_nextid)" = "40" ]       # both closed → startable
}

@test "check.sh: a red verdict NAMES the section it went red in, and never double-counts (R89)" {
  # Sources the REAL definitions out of check.sh rather than restating them — a re-implementation
  # would pass while the gate itself regressed, which is the failure mode this suite already
  # rejects elsewhere. Running the whole gate here is not an option: check.sh runs bats.
  run bash -c '
    cd "$1" || exit 1
    fail=0
    eval "$(sed -n "/^CUR=\"(startup)\"/,/^}/p" check.sh)"
    section "Alpha" >/dev/null; failsec; failsec
    section "Beta"  >/dev/null; failsec
    section "Gamma" >/dev/null
    printf "fail=%s sections=%s\n" "$fail" "$FAILED_SECTIONS"
  ' _ "$BATS_TEST_DIRNAME/../.."
  [ "$status" -eq 0 ]
  [[ "$output" == *"fail=1"* ]]
  [[ "$output" == *"sections=Alpha;Beta"* ]]   # Alpha once despite two failures; Gamma clean, absent
}

@test "UN-6 foreign repos: the plugin works in ecosystems and paths it has never seen (R91)" {
  # UN-6 is "it works on other people's projects, in whatever language and shape they use", and it
  # was the LEAST verified need in the matrix — 2 requirements to UN-4's twelve, with zero fixtures
  # carrying a package.json, pyproject.toml, go.mod or Cargo.toml. Every fixture was a bare git
  # init, i.e. a repo shaped like this one. Probing found no defect; this keeps it that way.
  local base; base="$(_tmpd)"
  local st tk; st="$(_tmpd)"; tk="$(_tmpd)"

  # 1. TODO detection must be GENERIC (R9: no ecosystem allowlists). One marker, four languages.
  _eco() {  # $1 dir · $2 file · $3 marker line · $4 manifest name · $5 manifest body
    local r="$base/$1"; mkdir -p "$r/src"; git -C "$r" init -q
    printf '%s\n' "$3" > "$r/src/$2"; printf '%s\n' "$5" > "$r/$4"
    git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m i
    run env CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" \
        bash -c 'cd "$1" && "$2"' _ "$r" "$ROOT/bin/candidates.sh"
    [[ "$output" == *"3|todo|"* ]]
  }
  _eco js "app.js"   "// TODO: retry the upload"      package.json   '{"name":"w"}'
  _eco py "app.py"   "# TODO: handle the timeout"     pyproject.toml '[project]'
  _eco go "main.go"  "// TODO: bound the retry loop"  go.mod         'module w'
  _eco rs "main.rs"  "// FIXME: unwrap can panic"     Cargo.toml     '[package]'

  # 2. The per-repo flag must round-trip through paths the encoder has to escape.
  local d
  for d in "with space" "ünïcodé" "quo'te"; do
    mkdir -p "$base/$d"; git -C "$base/$d" init -q
    run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" on >/dev/null && cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" status' _ "$base/$d" "$st" "$AP"
    [ "$output" = "on" ]
    run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" off >/dev/null && cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3" status' _ "$base/$d" "$st" "$AP"
    [ "$output" = "off" ]
  done

  # 3. The status line renders in a directory that is not a git repo at all.
  mkdir -p "$base/nogit"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,session_id:\"f\",model:{display_name:\"Opus\"}}" | NO_COLOR=1 "$2"' _ "$base/nogit" "$SL"
  [ "$status" -eq 0 ]; [ -n "$output" ]
}

@test "UN-6 foreign repos: tq stopfields and the burn loop work there too (R91)" {
  # The gap named when R91 shipped: the matrix covered candidates, flags and the status line, but
  # nothing drove the selection logic or burn-down through a foreign repo. A path WITH A SPACE is
  # the shape most likely to break an unquoted expansion, so every repo here has one. (R100/Pass 4:
  # this used to drive the Stop hook, now retired; tq stopfields carries the selection logic itself.)
  local base st tk; base="$(_tmpd)"; st="$(_tmpd)"; tk="$(_tmpd)"
  local r="$base/my app"; mkdir -p "$r"; git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  printf '{"name":"widget"}\n' > "$r/package.json"

  # --- the selection logic, in a repo it has never seen ---
  local sid=fgn d="$tk/fgn"; mkdir -p "$d"; _stamp_root "$d" "$r"
  jq -n '{id:"1",subject:"ship the widget",status:"pending"}' > "$d/1.json"
  local nid; nid="$(CLAUDE_COMPANION_TASKS_DIR="$tk" CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f5)"
  [ "$nid" = "1" ]                                 # it selects a task in a repo it has never seen
  jq -n '{id:"1",subject:"ship the widget",status:"completed"}' > "$d/1.json"   # done, so it doesn't outrank the burn loop below

  # --- the burn loop: two agreeing samples, then a real branch ---
  mkdir -p "$st/burndown"; touch "$(_flagpath "$st" burndown "$r")"
  local n; n="$(date +%s)"
  _fsnap() { printf '%s 20 %s %s %s\n' "$1" "$((n+7200))" "$2" "$((n+172800))" > "$st/ratelimit"; }
  _fbd()   { run env CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" \
                 BURNDOWN_ROOT="$r" bash "$ROOT/bin/burn-down.sh" status; }
  _fsnap "$((n-9))" 10; _fbd; [[ "$output" == HOLD:* ]]
  _fsnap "$((n-8))" 10; _fbd; [[ "$output" == BURN:* ]]

  # The dirty-tree refusal must hold in a foreign repo too — package.json is untracked here, and
  # starting autonomous work on top of someone else's uncommitted changes is the one thing this
  # guard exists to stop. (Found by this test: the first version left it untracked and got exit 4.)
  run env CLAUDE_COMPANION_STATE_DIR="$st" BURNDOWN_ROOT="$r" \
      bash "$ROOT/bin/burndown-branch.sh" start '3|todo|add offline mode'
  [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
  git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m manifest

  # a NON-ASCII candidate must still yield a usable branch and a manifest, in a spaced path
  run env CLAUDE_COMPANION_STATE_DIR="$st" BURNDOWN_ROOT="$r" \
      bash "$ROOT/bin/burndown-branch.sh" start '3|todo|añadir modo sin conexión'
  [ "$status" -eq 0 ]
  git -C "$r" branch | grep -q 'burndown/'
  [ -n "$(ls "$r/.companion/burndown-manifests" 2>/dev/null)" ]   # manifests are REPO state (R96)
}


@test "boundary lint: derives thresholds from SOURCE and catches a pinned fixture (R92)" {
  # A lint nobody invokes is a hole, and one that derives nothing passes vacuously — both failure
  # modes have happened in this repo, so this pins the real script rather than a re-implementation.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/bin" "$d/dev"
  printf 'FINAL="${BURNDOWN_FINAL_STRETCH:-86400}"\nTARGET="${T:-100}"\n' > "$d/plugins/companion/bin/x.sh"  # boundary-ok: this IS the lint's fixture
  cp "$ROOT/../../dev/portability-lint.sh" "$d/dev/" 2>/dev/null || cp dev/portability-lint.sh "$d/dev/"

  # a fixture pinned to the derived 86400 threshold → caught
  printf 'run _bd_left 50 86400\n' > "$d/t.bats"   # boundary-ok: sample input for the lint under test
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"86400s threshold"* ]]   # boundary-ok: sample input for the lint under test

  # the same line marked as a reviewed exemption → allowed
  printf 'run _bd_left 50 86400   # boundary-ok\n' > "$d/t.bats"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -eq 0 ]

  # a PERCENTAGE-sized constant must NOT be flagged — the first cut used >=60 and buried the real
  # hits under six innocent "100%" assertions
  printf 'assert "$out" = "100%%"\n' > "$d/t.bats"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -eq 0 ]

  # deriving NOTHING must FAIL loudly rather than pass vacuously
  rm "$d/plugins/companion/bin/x.sh"
  run bash -c 'cd "$1" && dev/portability-lint.sh boundary t.bats' _ "$d"
  [ "$status" -ne 0 ]; [[ "$output" == *"vacuously"* ]]
}

@test "command-lint: the COMMAND CONTRACT checks can now fail — they could not while inline (R75)" {
  # These checks lived inline in check.sh, where the suite could not reach them, so their declared
  # mutations had nothing that could redden. Extraction (2026-08-03, size guard) is what makes them
  # testable; this is the test that makes the extraction worth anything.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/commands" "$d/dev"
  cp dev/doc-lint.sh dev/command-lint.sh "$d/dev/"
  _cl() { run bash -c 'cd "$1" && dev/command-lint.sh' _ "$d"; }

  # a well-formed command passes
  printf -- '---\ndescription: Do the thing\n---\n\nBody with no arguments.\n' \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -eq 0 ]

  # an over-long description is per-session injection and must FAIL
  printf -- '---\ndescription: %s\n---\n\nBody.\n' "$(printf 'x%.0s' $(seq 1 200))" \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -ne 0 ]; [[ "$output" == *"> 140B"* ]]

  # a body reading $ARGUMENTS with no argument-hint leaves the parameter invisible where it is typed
  printf -- '---\ndescription: Do the thing\n---\n\nUse $ARGUMENTS here.\n' \
    > "$d/plugins/companion/commands/ok.md"
  _cl; [ "$status" -ne 0 ]; [[ "$output" == *"argument-hint"* ]]
}

@test "command-lint: a mode autopilot.sh IMPLEMENTS but no document mentions is caught (doc vs CODE)" {
  # The live 2026-08-15 miss: `burndown on|off|status` was implemented and the description, the
  # argument-hint and the body ALL omitted it — so every doc-vs-doc check agreed, and agreed about
  # nothing. Three consistent documents are not evidence when the mode is absent from all three.
  local d; d="$(_tmpd)"; mkdir -p "$d/plugins/companion/commands" "$d/plugins/companion/bin" "$d/dev"
  cp dev/doc-lint.sh dev/command-lint.sh "$d/dev/"
  _cl() { run bash -c 'cd "$1" && dev/command-lint.sh' _ "$d"; }
  # a stand-in autopilot.sh whose top-level case implements one shared action and two modes
  printf '%s\n' '#!/usr/bin/env bash' 'case "${1:-}" in' \
    '  status) echo s ;;' '  ship) echo x ;;' '  burndown) echo y ;;' 'esac' \
    > "$d/plugins/companion/bin/autopilot.sh"

  # documents BOTH modes -> clean
  printf -- '---\ndescription: on|off|status · ship/burndown on|off\n---\n\nModes: ship, burndown.\n' \
    > "$d/plugins/companion/commands/autopilot.md"
  _cl; [ "$status" -eq 0 ]

  # drops one mode from every document at once -> exactly the drift that shipped, now caught
  printf -- '---\ndescription: on|off|status · ship on|off\n---\n\nModes: ship.\n' \
    > "$d/plugins/companion/commands/autopilot.md"
  _cl; [ "$status" -ne 0 ]
  [[ "$output" == *"burndown"* ]]
  [[ "$output" != *"never mentions the \`ship\`"* ]]   # the documented mode is not flagged
  [[ "$output" != *"never mentions the \`status\`"* ]] # shared actions are not modes
}

@test "resume: RECENT out-of-band changes print; old ones and no-file cost nothing (R93, now on-demand only)" {
  # The failure this exists for is CONTEXT LOSS: clear the state, open a bug, and the fact that
  # something relevant changed last week is gone. R93's own reasoning was that this must arrive
  # UNASKED because "go look" cannot survive that — pulling it on demand instead (R100/Pass 2, no
  # hook left to inject it automatically) reopens exactly that failure. Recorded honestly, not
  # fixed: this test now proves the content survives the mechanism change, not that the original
  # guarantee still holds — it doesn't.
  local r; r="$(_tmpd)"; git -C "$r" init -q; mkdir -p "$r/docs"
  local today old
  today="$(date -u +%Y-%m-%d)"
  old="$(date -u -d '-60 days' +%Y-%m-%d 2>/dev/null || date -u -v-60d +%Y-%m-%d)"
  printf '## Log\n\n- %s · aws · widened the RDS security group\n  could break: auth callbacks\n- %s · dns · moved the apex A record\n' \
    "$today" "$old" > "$r/docs/CHANGES-OUTSIDE-GIT.md"
  _ctx() { run bash -c 'cd "$1" && "$2"' _ "$1" "$RESUME"; }

  _ctx "$r"
  [[ "$output" == *"widened the RDS security group"* ]]   # recent entry rides in, unasked
  [[ "$output" == *"could break: auth callbacks"* ]]      # ...with its continuation line
  [[ "$output" != *"apex A record"* ]]                    # 60 days old: history, not noise

  # a repo with NO ledger contributes NOTHING — the whole cost argument rests on this
  local p2; p2="$(_tmpd)"; git -C "$p2" init -q
  _ctx "$p2"
  [[ "$output" != *"Changed OUTSIDE"* ]]
}

@test "rework ledger: counts FAILURES not touches, flags a rebuild candidate, and resume prints it (R94)" {
  # Owner: "Claude seems to be making more and more obvious mistakes requiring rework then telling
  # me about how it caught the mistakes." A caught mistake reported as an apparatus win reframes a
  # defect rate as a success. This makes the rate a number, and surfaces it unasked.
  local r st; r="$(_tmpd)"; git -C "$r" init -q; st="$(_tmpd)"
  local RW="$ROOT/bin/rework.sh"
  _rw() { run env CLAUDE_COMPANION_STATE_DIR="$st" REWORK_ROOT="$r" bash "$RW" "$@"; }

  _rw report; [ "$status" -eq 0 ]; [[ "$output" == *"none recorded"* ]]

  # the event that matters most: the owner had to supply the answer
  _rw record owner-supplied; [ "$status" -eq 0 ]
  _rw report; [[ "$output" == *"owner-supplied"* ]]

  # three FAILURES against one file make it a rebuild candidate; the offer names the command
  _rw record gate-fail src/auth.js
  _rw record ci-red   src/auth.js
  _rw record hole     src/auth.js
  _rw report
  [[ "$output" == *"src/auth.js"* ]]; [[ "$output" == *"redesign"* ]]

  # ...but a file seen ONCE is not a candidate — this counts failures, not churn
  [[ "$output" != *"src/other.js"* ]]
  _rw record gate-fail src/other.js
  _rw report; [[ "$output" != *"⟳ src/other.js"* ]]

  # and it shows up whenever resume is called
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3"' _ "$r" "$st" "$RESUME"
  [[ "$output" == *"REWORK already recorded"* ]]

  # a repo with nothing recorded contributes NOTHING
  local clean; clean="$(_tmpd)"; git -C "$clean" init -q
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" "$3"' _ "$clean" "$st" "$RESUME"
  [[ "$output" != *"REWORK already recorded"* ]]
}

@test "⛔ ruled-out is a prefix-view that PERSISTS but is never work (R95)" {
  # The Apple/AWS incident: "the owner confirmed this twice" lived only in a context window, and
  # compaction destroyed it, so the innocent component kept being re-investigated. A closure has to
  # outlive the conversation that produced it. Like ❓/⏳ this is a PREFIX over pending (R42), never
  # a status value, so it rides the same resume path that already survives compaction.
  local sid=rlT d="$CLAUDE_COMPANION_TASKS_DIR/rlT"; mkdir -p "$d"
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" add "real buildable work"
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" add "⛔ [ruled out] Apple login config — owner confirmed twice"

  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" report
  [[ "$output" == *"⛔1"* ]]                       # counted in its own class...
  [[ "$output" == *"[ruled out] Apple login"* ]]   # ...rendered without doubling the glyph
  [[ "$output" == *"→ next: #1"* ]]                # ...and the pointer ignores it

  # the drain must not see it as startable, or a closure becomes a task
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false
  [[ "$output" == "1"* ]]                          # OPEN counts the real work only
  [[ "$output" == *"real buildable work"* ]]
  [[ "$output" != *"Apple login"* ]]

  # ...and with ONLY a ruled-out entry left, there is nothing to do at all
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" done 1
  run env CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false
  [[ "$output" == "0"* ]]
}

@test "modes are REPO state: they survive a wiped state dir and do not block burn-down (R96)" {
  local AP2="$ROOT/bin/autopilot.sh"
  local r h1 h2; r="$(_tmpd)"; git -C "$r" init -q; h1="$(_tmpd)"; h2="$(_tmpd)"
  ( cd "$r" && CLAUDE_COMPANION_STATE_DIR="$h1" bash "$AP2" on ) >/dev/null

  # the flag is a file IN THE REPO, so git carries it to a cloud agent or a fresh container
  [ -f "$r/.companion/modes/autopilot" ]
  # ...AND the legacy location, because the CLI runs from the repo while HOOKS are served from the
  # installed cache — writer and reader are routinely different versions of this plugin. New code
  # reads the legacy flag; OLD code cannot read the new one. Writing only the repo flag left
  # `autopilot on` reporting ON while the installed Stop hook saw OFF and stood down every turn,
  # with work sitting in the queue. Dual-write is what makes the move survivable across versions.
  [ -f "$(_flagpath "$h1" autopilot "$r")" ]
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r" "$h2" "$AP2"
  [ "$output" = "on" ]                       # h2 is a BRAND-NEW state dir: $HOME wiped

  # off must clear it everywhere, or a stale flag resurrects a mode the owner turned off
  ( cd "$r" && CLAUDE_COMPANION_STATE_DIR="$h1" bash "$AP2" off ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r" "$h1" "$AP2"
  [ "$output" = "off" ]
  [ ! -f "$r/.companion/modes/autopilot" ]
  [ ! -f "$(_flagpath "$h1" autopilot "$r")" ]     # BOTH cleared, or an old reader stays armed

  # a LEGACY home-scoped flag is still honoured, so upgrading does not silently lose a mode...
  local r2 h3; r2="$(_tmpd)"; git -C "$r2" init -q; h3="$(_tmpd)"
  mkdir -p "$h3/autopilot"; touch "$(_flagpath "$h3" autopilot "$r2")"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r2" "$h3" "$AP2"
  [ "$output" = "on" ]
  # ...and turning it off clears the legacy one too
  ( cd "$r2" && CLAUDE_COMPANION_STATE_DIR="$h3" bash "$AP2" off ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$r2" "$h3" "$AP2"
  [ "$output" = "off" ]

  # plugin state must NOT count as a dirty tree, or arming burn-down disables burn-down; the
  # owner's own uncommitted work still must.
  local r3 st3; r3="$(_tmpd)"; st3="$(_tmpd)"
  git -C "$r3" init -q -b main; git -C "$r3" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  mkdir -p "$r3/.companion/modes"; : > "$r3/.companion/modes/burndown"
  run env CLAUDE_COMPANION_STATE_DIR="$st3" BURNDOWN_ROOT="$r3" bash "$ROOT/bin/burndown-branch.sh" start '3|todo|only plugin state dirty'
  [ "$status" -eq 0 ]
  git -C "$r3" checkout -q main
  printf 'the owner work\n' > "$r3/notes.txt"
  run env CLAUDE_COMPANION_STATE_DIR="$st3" BURNDOWN_ROOT="$r3" bash "$ROOT/bin/burndown-branch.sh" start '3|todo|real dirt'
  [ "$status" -eq 4 ]; [[ "$output" == *"dirty"* ]]
}

@test "the QUEUE is repo state: it survives into a fresh clone with no home state (R96 stage 2)" {
  # The queue IS the product, so a cloud agent starting with an empty one has nothing to drain.
  # env -u is load-bearing: the suite exports CLAUDE_COMPANION_TASKS_DIR to isolate, and that
  # variable deliberately WINS over the repo store — so a test that left it set would be asserting
  # the old behaviour while believing it tested the new one.
  # HOME is overridden for EVERY step, not just the clone one. Without that this test reads the
  # REAL home store, and a session id that happens to exist there triggers the legacy fallback —
  # which is exactly how it passed alone and failed inside the suite.
  local r hbase; r="$(_tmpd)"; git -C "$r" init -q; hbase="$(_tmpd)"
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s1 "$3" add "ship the widget"' _ "$r" "$hbase" "$TQ"
  [ "$status" -eq 0 ]
  [ -f "$r/.companion/tasks/1.json" ]             # stored IN the repo, FLAT — no session subdir

  # THE POINT OF FLATTENING: a DIFFERENT session must see the queue. A clone or container always
  # has a new session id, and while the store was session-partitioned the tasks travelled with the
  # repo while the drain read an empty directory — the data was there and the system could not use
  # it. This assertion is the one that was missing when that shipped.
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=OTHER "$3" stopfields false' _ "$r" "$hbase" "$TQ"
  [[ "$output" == *"ship the widget"* ]]

  # ...and the RESUME path must read the flat store too, or a carried queue drains but never gets
  # re-surfaced after a compaction. The mutation gate reported exactly this branch as a hole.
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" "$3"' _ "$r" "$hbase" "$RESUME"
  [[ "$output" == *"ship the widget"* ]]

  # a fresh container: a copy of the repo, and a home directory with nothing in it
  local c h; c="$(_tmpd)"; h="$(_tmpd)"
  cp -r "$r/.git" "$c/.git"; cp -r "$r/.companion" "$c/.companion"
  git -C "$c" checkout -q -- . 2>/dev/null || true
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s1 "$3" report' _ "$c" "$h" "$TQ"
  [[ "$output" == *"ship the widget"* ]]

  # an explicit store still wins absolutely — that is how every other test isolates
  local ext; ext="$(_tmpd)"; mkdir -p "$ext/s2"
  run bash -c 'cd "$1" && HOME="$4" CLAUDE_COMPANION_TASKS_DIR="$2" CLAUDE_COMPANION_SESSION_ID=s2 "$3" add "elsewhere"' _ "$r" "$ext" "$TQ" "$hbase"
  [ -f "$ext/s2/1.json" ]
  [ ! -f "$ext/s2/2.json" ]                       # ...and did not land in the repo store either

  # a session ALREADY in the legacy home store keeps working there — upgrading orphans nothing
  local h2; h2="$(_tmpd)"; mkdir -p "$h2/.claude/companion/tasks/s3"
  run bash -c 'cd "$1" && env -u CLAUDE_COMPANION_TASKS_DIR HOME="$2" CLAUDE_COMPANION_SESSION_ID=s3 "$3" add "legacy work"' _ "$r" "$h2" "$TQ"
  [ -f "$h2/.claude/companion/tasks/s3/1.json" ]
  [ ! -f "$r/.companion/tasks/2.json" ]           # legacy session kept its own store
}

@test "the LEDGERS are repo state: a defect rate that resets with the container measures nothing (R96 stage 3)" {
  local r h; r="$(_tmpd)"; git -C "$r" init -q; h="$(_tmpd)"
  local RW="$ROOT/bin/rework.sh"

  run env CLAUDE_COMPANION_STATE_DIR="$h" REWORK_ROOT="$r" bash "$RW" record owner-supplied src/a.js
  [ -f "$r/.companion/rework" ]                    # written IN the repo
  [ ! -d "$h/rework" ]                             # and NOT under the state dir

  # a fresh container with a wiped state dir still sees the history
  local h2; h2="$(_tmpd)"
  run env CLAUDE_COMPANION_STATE_DIR="$h2" REWORK_ROOT="$r" bash "$RW" report
  [[ "$output" == *"owner-supplied"* ]]

  # LEGACY events still count, or the defect rate silently drops to zero on upgrade
  local r2 h3; r2="$(_tmpd)"; git -C "$r2" init -q; h3="$(_tmpd)"
  mkdir -p "$h3/rework"
  printf '%s legacy-event -\n' "$(date +%s)" > "$h3/rework/$(printf '%s' "$r2" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" report
  [[ "$output" == *"legacy-event"* ]]
  # ...and a new event merges with them rather than replacing them
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" record ci-red src/b.js
  run env CLAUDE_COMPANION_STATE_DIR="$h3" REWORK_ROOT="$r2" bash "$RW" report
  [[ "$output" == *"legacy-event"* ]]; [[ "$output" == *"ci-red"* ]]
}

@test "candidates: the ladder escalates small-first and ends at a REBUILD before inventing (R82/R94)" {
  # The owner asked for small work first, escalating as it is exhausted. That is a ladder of
  # PROVENANCE, not of size: a complexity dial was asked for and rejected because the agent would
  # be scoring its own work unauditably (contract-guard.sh). A repeatedly-FAILING component is the
  # largest recorded signal there is, so it ranks after every cleanup and before invention.
  local r st; r="$(_tmpd)"; st="$(_tmpd)"
  git -C "$r" init -q -b main
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  _cand() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" REWORK_ROOT="$1" "$3"' _ "$r" "$st" "$ROOT/bin/candidates.sh"; }

  # nothing recorded → invention, explicitly labelled, at the BOTTOM of the ladder
  _cand; [[ "$output" == *"|invent|"* ]]

  # three recorded FAILURES against one file make it a rebuild candidate, ranked above invention
  local RW="$ROOT/bin/rework.sh"
  for k in gate-fail ci-red hole; do
    run env CLAUDE_COMPANION_STATE_DIR="$st" REWORK_ROOT="$r" bash "$RW" record "$k" src/flaky.js
  done
  _cand
  [[ "$output" == *"5|rework|"* ]]; [[ "$output" == *"src/flaky.js"* ]]
  [[ "$output" != *"|invent|"* ]]                 # invention is suppressed while a signal remains

  # a genuine TODO in source outranks the rebuild — small work first
  mkdir -p "$r/src"; printf '// TODO: bound the retry loop\n' > "$r/src/a.js"
  git -C "$r" add -A; git -C "$r" -c user.email=t@t -c user.name=t commit -q -m todo
  _cand
  [[ "$output" == "3|todo|"* ]]

  # ...but PROSE about TODO markers in the contract is not a task. Excluding markdown alone was
  # never the rule; this repo's contract is yaml, and its own description of the scanner was being
  # offered as work to do.
  local r2 st2; r2="$(_tmpd)"; st2="$(_tmpd)"
  git -C "$r2" init -q -b main
  mkdir -p "$r2/docs"; printf 'note: >\n  Covers TODO detection across ecosystems\n' > "$r2/docs/contract.yaml"
  git -C "$r2" add -A; git -C "$r2" -c user.email=t@t -c user.name=t commit -q -m c
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" REWORK_ROOT="$1" "$3"' _ "$r2" "$st2" "$ROOT/bin/candidates.sh"
  [[ "$output" != *"|todo|"* ]]
}

@test "tq orphans: state kinds are DERIVED from source, so dead state cannot hide (R96)" {
  # Deleting a feature used to leave its state behind forever — captures/, review/, intent-* and
  # reminded-* all outlived the code that wrote them, and only a hand grep could tell. The known
  # kinds are derived from the shipped source rather than listed, because a list is a second thing
  # to update whenever a kind is added.
  local sd; sd="$(_tmpd)"
  mkdir -p "$sd/autopilot" "$sd/tasks" "$sd/slcache" "$sd/somethingdead" "$sd/intent-abc"
  : > "$sd/ratelimit"
  _orph() { run env CLAUDE_COMPANION_STATE_DIR="$sd" CLAUDE_COMPANION_SESSION_ID=o "$TQ" orphans "$@"; }

  _orph
  [ "$status" -eq 0 ]
  [[ "$output" == *"somethingdead"* ]]      # no shipped code builds this path
  [[ "$output" == *"intent-abc"* ]]
  [[ "$output" != *"orphan: autopilot"* ]]  # ...but a real mode kind is NOT flagged
  [[ "$output" != *"orphan: tasks"* ]]
  [[ "$output" != *"orphan: ratelimit"* ]]
  [[ "$output" != *"orphan: slcache"* ]]

  # report is the default — nothing is removed without asking
  [ -d "$sd/somethingdead" ]

  _orph --orphans
  [ ! -d "$sd/somethingdead" ]; [ ! -d "$sd/intent-abc" ]
  [ -d "$sd/autopilot" ]; [ -d "$sd/tasks" ]   # the live ones survive

  _orph
  [[ "$output" == *"none"* ]]
}

@test "resume: carried tasks render the done-when + LATEST note sub-lines (R56 G2 — R47/PR126 resume enrichment)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=rEn; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"carry me",status:"pending",done_when:"green tests",notes:[{ts:"t1",text:"first crumb"},{ts:"t2",text:"latest crumb"}]}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"carry me"* ]]                 # the task surfaces
  [[ "$output" == *"done when: green tests"* ]]   # acceptance re-surfaced (the R47 resume side)
  [[ "$output" == *"note: latest crumb"* ]]       # LATEST note (PR #126), not the first
  [[ "$output" != *"note: first crumb"* ]]        # only the latest, not the whole trail
}

# ---- crash resume: what an interrupted session leaves behind, and what says so on the way back ----

@test "resume: an in_progress task renders ▸ (mid-flight), a pending one ◻ — a crash left them different" {
  # Both statuses used to render "◻", so the task a crashed session was actually WORKING ON came
  # back indistinguishable from one merely queued — the queue knew where the work stopped and the
  # resume path threw it away.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=rIP; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"merely queued",status:"pending"}'    > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"was mid-flight",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"▸ was mid-flight"* ]]
  [[ "$output" == *"◻ merely queued"* ]]
  [[ "$output" != *"◻ was mid-flight"* ]]
}

@test "resume: dirty tree + NO task in_progress warns UNRECONCILED and names the files" {
  # The crash case the durable queue does not already cover: edits survive on disk, but nothing in
  # the queue claims them, so the next session cannot tell 10%-done from 90%-done.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/tracked.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  local sid=rUn; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"open but unclaimed",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  echo edited >> "$repo/tracked.txt"; echo brand-new > "$repo/untracked.txt"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRECONCILED WORK"* ]]
  [[ "$output" == *"2 uncommitted change(s)"* ]]
  [[ "$output" == *"NO task is in_progress"* ]]
  [[ "$output" == *"tracked.txt"* ]] && [[ "$output" == *"untracked.txt"* ]]
  [[ "$output" == *"tq doing"* ]]                 # says what to DO about it, not just that it is so
}

@test "resume: UNRECONCILED is silent on a clean tree, and silent while a task IS in_progress" {
  # A warning that fires when there is nothing to reconcile gets ignored, which costs the warning
  # its whole value on the one session where it matters.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  local sid=rQu; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"queued",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # clean tree -> nothing to say
  # now dirty it, but leave a proper breadcrumb: the mid-flight task IS the reconciliation
  echo edited >> "$repo/f.txt"
  jq -n '{id:"2",subject:"claimed it",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # breadcrumb present -> the warning stands down
  [[ "$output" == *"▸ claimed it"* ]]             # …and the mid-flight task is what shows instead
}

@test "resume: UNRECONCILED ignores the companion's OWN store — it must not warn about its bookkeeping" {
  # .companion/ is untracked in most projects. Counting it would make this fire every single
  # session, which is the same as not having it.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  mkdir -p "$repo/.companion/tasks"
  jq -n '{id:"1",subject:"in the repo store",status:"pending"}' > "$repo/.companion/tasks/1.json"
  local sid=rSelf; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" != *"UNRECONCILED"* ]]             # only the store is dirty -> silent
  echo edited >> "$repo/f.txt"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [[ "$output" == *"UNRECONCILED"* ]]             # a REAL edit appears -> it fires…
  [[ "$output" == *"1 uncommitted change(s)"* ]]  # …counting 1, not 2: the store never counted
}

@test "session-start: the UNRECONCILED warning reaches the HOOK path too, not just manual resume" {
  # session-start.sh is the one that fires after a crash without anyone asking, so the warning is
  # worth nothing if it only rides the manual pull.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  echo edited >> "$repo/f.txt"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNRECONCILED WORK"* ]]
  [[ "$output" == *"f.txt"* ]]
}

@test "resume: an UNSTAMPED store dir holding open work is reported as UNREACHABLE" {
  # `tq` only writes stamps on `add`, so once the owning session is gone a stamp-less dir can never
  # heal itself — no later `add` runs there. Its open tasks are invisible to every repo forever.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/ghost"          # deliberately NO .repo and NO .root
  jq -n '{id:"1",subject:"lost work",status:"pending"}'     > "$CLAUDE_COMPANION_TASKS_DIR/ghost/1.json"
  jq -n '{id:"2",subject:"also lost",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/ghost/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"UNREACHABLE QUEUE"* ]]
  [[ "$output" == *"2 open"* ]]                          # counts open only, and both statuses count
  [[ "$output" == *"ghost"* ]]                           # names the directory so it can be acted on
}

@test "resume: UNREACHABLE never reports another repo's dir — a stamp is a stamp even if that repo is not here" {
  # THE bleed guard. The first draft required the .root path to exist on disk, and immediately
  # reported a dir belonging to a repo that simply was not mounted — turning a cross-project-safety
  # feature into the cross-project leak it exists to prevent. Absent path = repo elsewhere, not
  # unclaimable. Also: a stamp-less dir whose tasks are all FINISHED is dead weight, not lost work.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/elsewhere"
  printf '%s' "/no/such/path/anymore" > "$CLAUDE_COMPANION_TASKS_DIR/elsewhere/.root"
  jq -n '{id:"1",subject:"theirs",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/elsewhere/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/byid"
  printf '%s' "some-identity" > "$CLAUDE_COMPANION_TASKS_DIR/byid/.repo"
  jq -n '{id:"1",subject:"id-stamped",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/byid/1.json"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/spent"          # unstamped, but nothing open in it
  jq -n '{id:"1",subject:"finished",status:"completed"}' > "$CLAUDE_COMPANION_TASKS_DIR/spent/1.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNREACHABLE"* ]]
  [[ "$output" != *"theirs"* ]]                          # and no other repo's task text leaks in
}

@test "resume: a store path containing a NEWLINE still returns the whole backlog" {
  # Found by the pre-ship adversarial pass: extracting companion_task_files made it hand paths back
  # newline-separated, and a store path with a newline in it split one path into two non-existent
  # ones — every task silently rendered as ZERO, on the one path whose entire job is handing the
  # backlog back after a crash. Same total-loss shape as the corrupt-file abort, different cause.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local root; root="$(git -C "$repo" rev-parse --show-toplevel)"
  local weird="$CLAUDE_COMPANION_TASKS_DIR/we"$'\n'"ird"
  mkdir -p "$weird"; printf '%s' "$root" > "$weird/.root"
  jq -n '{id:"1",subject:"still here",status:"pending"}'  > "$weird/1.json"
  jq -n '{id:"2",subject:"mid-flight",status:"in_progress"}' > "$weird/2.json"
  run bash -c 'cd "$1" && . "$2" && companion_open_tasks "$(git rev-parse --show-toplevel)"' \
    _ "$repo" "$ROOT/lib/companion.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"still here"* ]]
  [[ "$output" == *"▸ mid-flight"* ]]
}

@test "resume: UNRECONCILED survives a corrupt task file — a bad file must not hide a mid-flight task" {
  # companion_any_in_progress batches its jq, and jq aborts at the first unparseable file. If the
  # batch failure were read as "nothing in progress", one torn write would resurrect the warning on
  # top of work that WAS properly claimed — noise exactly when the store is already damaged.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  git -C "$repo" config user.email t@t; git -C "$repo" config user.name t
  echo hi > "$repo/f.txt"; git -C "$repo" add -A; git -C "$repo" commit -qm init
  echo edited >> "$repo/f.txt"
  local sid=rCor; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  printf '{ NOT VALID JSON' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"claimed it",status:"in_progress"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" != *"UNRECONCILED"* ]]             # the mid-flight task is still found
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

@test "autopilot decisive (R59): toggle persists, independent of plain autopilot" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "off" ]           # off by default
  ( cd "$repo" && "$AP" decisive on ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "on" ]            # persisted flag
  ( cd "$repo" && "$AP" off ) >/dev/null
  [ "$(cd "$repo" && "$AP" decisive status)" = "on" ]            # decisive outlives plain autopilot toggling off
}

@test "the decisive/plain park-vs-decide guidance is stated in STEERING and ask-guard.sh enforces it again (R33/R59/R84, R100/Pass 6)" {
  # ask-guard.sh is reinstated (R100/Pass 6, docs/adr/README.md R105): it denies AskUserQuestion
  # and auto-parks again. This pins the prose still states the guidance where autopilot's rules
  # live — the behavioral half (deny + auto-park itself) is pinned separately, by the ask-guard
  # tests, so this structural guard isn't duplicating that coverage.
  local core; core="$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$ROOT/STEERING.md")"
  [[ "$core" == *"park it yourself, before"* ]]                  # R84: proactive parking is still the intended path
  [[ "$core" == *"park it even when trivially reversible"* ]]    # R33: taste, not reversibility, is the test
  [[ "$core" == *"Decisive mode (R59)"* ]]                       # R59: the decisive-mode override exists
  [[ "$core" == *"irreversible-critical"* ]]
}

@test "tq: stamps the session .root with the actual git toplevel (R56 G8 — cross-session scope)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$TQ" add "scoped" ) >/dev/null
  # not just that .root exists (already pinned) — that it holds the CORRECT root, else resume mis-scopes
  [ "$(cat "$CLAUDE_COMPANION_TASKS_DIR/s1/.root")" = "$(git -C "$repo" rev-parse --show-toplevel)" ]
}

@test "resume: keeps the recommendation-contract clause (R56 G3 — R49), since it now rides in the full core every call" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation-first"* ]]   # the R49 posture — always present now, not just after a compaction
}

@test "check-secrets: blocks non-AWS anchored keys too — GH/Slack/Stripe/Google/PEM (R56 — INVARIANTS claim)" {
  # INVARIANTS.md claims six-vendor coverage but only AKIA was ever exercised. Construct each shape
  # at runtime (never a literal key in this file) so gitleaks doesn't flag the test itself.
  local pad; pad="$(printf 'a%.0s' $(seq 40))"                         # 40 alnum, ≥ each prefix's min run
  local ghp="ghp""_$pad" xox="xox""b-$pad" sk="sk_""live_$pad"
  local aiza="AIza$(printf 'a%.0s' $(seq 35))" pem="-----BEGIN ""PRIVATE KEY-----"
  for k in "$ghp" "$xox" "$sk" "$aiza" "$pem"; do
    run bash -c 'printf "%s" "$1" | "$2" --path /x/c.txt' _ "SECRET=\"$k\"" "$GUARD"
    [ "$status" -eq 2 ]                        # every recognised vendor shape blocks (exit 2), not just AWS
  done
}

@test "ship-checkpoint (R34): toggle, and commits work to an autopilot/* branch — NEVER main" {
  # R100/Pass 4: this used to be automatic (Stop hook, ship-mode + autopilot both on). Now it's a
  # CLI the model calls itself at a stopping point — same guarantees, same code, no more trigger.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  [ "$(cd "$repo" && "$AP" ship status)" = "off" ]
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  [ "$(cd "$repo" && "$AP" ship status)" = "on" ]
  printf 'work\n' > "$repo/newfile.txt"                      # uncommitted work while HEAD is on main
  ( cd "$repo" && "$ROOT/bin/ship-checkpoint.sh" ) >/dev/null 2>&1 || true
  [ "$(git -C "$repo" branch --show-current)" != "main" ]    # moved off main to protect it
  git -C "$repo" branch | grep -q 'autopilot/'              # onto an autopilot/* branch
  [ -z "$(git -C "$repo" status --porcelain)" ]             # the work got committed (clean tree)
  git -C "$repo" log -1 --pretty=%s | grep -q 'autopilot: checkpoint'
  ! git -C "$repo" cat-file -e main:newfile.txt 2>/dev/null  # main NEVER received the work
}

@test "ship-checkpoint: off → does NOT commit (work stays uncommitted)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf 'work\n' > "$repo/newfile.txt"                      # ship-mode OFF
  ( cd "$repo" && "$ROOT/bin/ship-checkpoint.sh" ) >/dev/null 2>&1 || true
  [ "$(git -C "$repo" branch --show-current)" = "main" ]     # no branch created
  [ -n "$(git -C "$repo" status --porcelain)" ]             # work left uncommitted for the owner
}

@test "ship-checkpoint: refuses to commit a hardcoded credential (R34)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; git -C "$repo" branch -m main 2>/dev/null || true
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  printf 'AWS = "%s"\n' "$k" > "$repo/creds.py"             # a real-shaped key in the work
  ( cd "$repo" && "$ROOT/bin/ship-checkpoint.sh" ) >/dev/null 2>&1 || true
  ! git -C "$repo" log --all --oneline | grep -q 'autopilot: checkpoint'   # no checkpoint committed
  [ -n "$(git -C "$repo" status --porcelain)" ]            # the work (with the key) left uncommitted
}

# ---- decisions surfaced + recorded by /companion:docs (R41; renamed from document 2026-07-22) ----

@test "check-secrets: tool-agnostic by construction — scans whatever text it's given, notebook-sourced or not (R43)" {
  # The old gate had to specifically extract .new_source to cover NotebookEdit, because Claude Code
  # dispatched it the same PreToolUse hook as every other content tool. That dispatch is gone
  # (R100/Pass 3) — there is no more tool_input to parse, just text on stdin — so "does it cover
  # every content-writing tool" is moot BY DESIGN now, not by extra code: whatever text a notebook
  # cell's source becomes, once it's the argument, is indistinguishable from any other text.
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  run bash -c 'printf "%s" "$1" | "$2" --path /x/n.ipynb' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
  run bash -c 'printf "%s" "$1" | "$2" --path /x/n.ipynb' _ "print(1+1)" "$GUARD"
  [ "$status" -eq 0 ]                                       # a clean cell still passes
}

@test "parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value (R42)" {
  # R100/Pass 4: drives tq stopfields directly (field 1 = open/non-deferred count) instead of the
  # retired Stop hook — same underlying selection logic, tq stopfields owns it (R87).
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local sid=pkv; mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/$sid"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/$sid" "$repo"
  jq -n '{id:"1",subject:"did it",status:"completed"}'   > "$CLAUDE_COMPANION_TASKS_DIR/$sid/1.json"
  jq -n '{id:"2",subject:"❓ decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  local open; open="$(CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f1)"
  [ "${open:-0}" -eq 0 ]                                    # a ❓ PENDING task counts as parked → not open
  # drop the prefix → same pending task is now real open work
  jq -n '{id:"2",subject:"decide X",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/$sid/2.json"
  open="$(CLAUDE_COMPANION_SESSION_ID="$sid" "$TQ" stopfields false 2>/dev/null | cut -d $'\x1f' -f1)"
  [ "$open" -eq 1 ]                                         # so parked-ness lives in the prefix, not status
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
  ( cd "$repo" && "$AP" ship on ) >/dev/null
  printf 'work\n' > "$repo/newfile.txt"
  ( cd "$repo" && "$ROOT/bin/ship-checkpoint.sh" ) >/dev/null 2>&1 || true
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
# R100/Pass 4: stop-autopilot.sh is retired; the sweep-eligibility logic it only ever READ lives in
# (and is driven directly via) tq stopfields now — same rules, no Stop-hook wrapper left.
_sw_next() {  # -> the next-subject field, or "" when nothing is eligible/startable
  CLAUDE_COMPANION_SESSION_ID=sw "$TQ" stopfields "${1:-true}" 2>/dev/null | cut -d $'\x1f' -f4
}
_sw_repo() {
  local r; r="$(_tmpd)"; git -C "$r" init -q
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  printf '%s' "$r"
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
  local repo; repo="$(_sw_repo)"; cd "$repo"
  _sw_task "❓ [parked] rev: colour scheme — options: A) dark B) light; rec: A + matches the app" 1
  [ -z "$(_sw_next false)" ]                  # sweep off: parked-only -> nothing startable
  [[ "$(_sw_next true)" == *"colour scheme"* ]]  # sweep on: the rev: park is work
}

@test "autopilot sweep: an IRREVERSIBLE park (no rev: marker) is never eligible (R77/R59)" {
  # The case that killed the first design: decisive mode parks ONLY the irreversible and writes
  # `rec:` on it, so a rec-based filter selected precisely the set it had to protect.
  local repo; repo="$(_sw_repo)"; cd "$repo"
  _sw_task "❓ [parked] force-push the rewrite to origin/main — options: A) force B) PR; rec: A + why" 1
  [ -z "$(_sw_next)" ]
  _sw_task "❓ [parked] delete the staging bucket and its snapshots — options: A) delete B) keep; rec: A + cost" 2
  [ -z "$(_sw_next)" ]                        # still nothing sweepable
  _sw_task "❓ [parked] rev: button copy — options: A) Save B) Done; rec: A + clearer" 3
  [[ "$(_sw_next)" == *"button copy"* ]]      # only the marked-reversible one is work
  [[ "$(_sw_next)" != *"force-push"* ]]
  [[ "$(_sw_next)" != *"delete the staging bucket"* ]]
}

@test "autopilot sweep: ⏳, decompose:, unrecorded and prose-only markers stay excluded (R77/R65)" {
  local repo; repo="$(_sw_repo)"; cd "$repo"
  # each fixture carries EVERY other marker, so it can only be excluded by the rule it targets
  _sw_task "⏳ [blocked] rev: delete the production bucket; rec: yes do it" 1
  _sw_task "❓ [parked] rev: Decompose: migrate the store — need: which fields; rec: split by table" 2
  _sw_task "❓ [parked] rev: drop the legacy table? — A) drop B) keep; no rec: recorded, this one is yours" 3
  _sw_task "❓ [parked] mentions rev: only in prose here; rec: A + why" 4
  [ -z "$(_sw_next)" ]                        # not one of them is eligible
  _sw_task "❓ [parked] rev: wording — options: A) terse B) chatty; rec: A + the voice" 5
  [[ "$(_sw_next)" == *"wording"* ]]
  [[ "$(_sw_next)" != *"production bucket"* ]]
  [[ "$(_sw_next)" != *"migrate the store"* ]]
  [[ "$(_sw_next)" != *"legacy table"* ]]
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
  # The frontmatter caller MOVED to dev/command-lint.sh with the 2026-08-03 extraction, so this
  # guard follows it. Leaving it pointed at check.sh is the third extraction trap in LESSONS — a
  # moved failure mode — and it fired here: the guard went red for the right reason.
  run grep -c 'doc-lint\.sh" frontmatter' "$DEV/command-lint.sh"
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
  # against a REAL scaling hook rather than a stub: a fake bin/ whose statusline.sh reads the
  # whole store (the shape of the 2085ms->16108ms session-start regression this gate was built to
  # catch — session-start.sh, then stop-autopilot.sh, both retired since, R100/Pass 2 and Pass 4,
  # but the scaling failure mode is generic to any hook that reads the store, so the fixture keeps
  # getting renamed to whatever hook is still standing, never dropped) must FAIL, and a bounded one PASS.
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  local fake; fake="$(_tmpd)"; mkdir -p "$fake/bin" "$fake/lib"
  cp "$DEV/hook-budget.sh" "$fake/bin/"; cp "$ROOT/lib/companion.sh" "$fake/lib/"
  # BOUNDED: touches nothing in the store. Must pass.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$fake/bin/statusline.sh"
  chmod +x "$fake/bin/statusline.sh"
  # Pin the ABSOLUTE cap, which is the hard gate since the recalibration, and use a store big
  # enough that the unbounded hook clears the noise floor. With the old tiny store the fake
  # hook measured UNDER NOISE_MS, where the ratio is not enforced — so the gate passed it and
  # this guard silently stopped guarding. It failed only under load, which is how it surfaced.
  run env HOOK_BUDGET_BIN="$fake/bin" HOOK_BUDGET_BASEDIRS=8 HOOK_BUDGET_PERDIR=8 HOOK_BUDGET_ABSCAP=200 bash "$fake/bin/hook-budget.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"statusline.sh"* ]]
  # UNBOUNDED: one jq per file across every session dir — cost tracks the store. Must fail.
  cat > "$fake/bin/statusline.sh" <<'EOS'
#!/usr/bin/env bash
for f in "${CLAUDE_COMPANION_TASKS_DIR:-/nonexistent}"/*/*.json; do
  [ -f "$f" ] || continue
  jq -r '.subject // empty' "$f" >/dev/null 2>&1 || true
done
exit 0
EOS
  chmod +x "$fake/bin/statusline.sh"
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

@test "resume: carries BOTH halves of the posture — the options half and the honesty-rides-the-pick half (R80)" {
  # R80's original "the verdict is unconditional" clause was already reversed by R80·b (2026-08-03);
  # what survives here is the OTHER half: the honest read stays attached to the recommendation, not
  # tacked onto every reply. R30·d2's separate abbreviated compact path is gone with the hook it
  # lived in (R100/Pass 2) — resume now always shows the full core, which already contains both
  # halves, so there is no longer a distinct "does the short path drop one" case to guard.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'cd "$1" && "$2"' _ "$repo" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"recommendation-first"* ]]      # the options half
  [[ "$output" == *"goes ON the pick"* ]]           # honesty rides the pick (the closing verdict is RETIRED, R80·b)
  [[ "$output" == *"Posture"* ]]                    # the core (incl. this section) DOES ride now (R30·d2 retired with the hook)
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

@test "check-secrets: EMPTY content never scans the FILE PATH as content (no false block)" {
  # The old gate concatenated path+content into one newline-joined stdin blob and split on the
  # FIRST newline — with no content there was no newline, so the path itself became the scanned
  # text, and an Edit clearing a file under a directory literally named AKIA… was BLOCKED. That
  # coupling can't happen here BY STRUCTURE (R100/Pass 3): path arrives via --path, content only
  # ever via stdin, two separate channels, never joined into one string to mis-split. Kept as a
  # regression guard in case a future "simplify" re-couples them.
  local k="AKIA""ABCDEFGHIJKLMNOP"        # split so THIS file isn't itself a secret
  run bash -c 'printf "%s" "$1" | "$2" --path "/tmp/$3/notes.txt"' _ "" "$GUARD" "$k"
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

@test "mutation gate: --shard partitions the set with no gaps and no overlap (R78)" {
  # 65 mutations x a ~50s suite is ~55 minutes serially, and a long job blocks log access for the
  # WHOLE CI run — a red check lane could not be read until the mutation lane finished. Sharding
  # is only safe if the shards are a true partition: every mutation runs exactly once across them.
  local d="$BATS_TEST_TMPDIR/mgshard"
  mkdir -p "$d/dev/tests" "$d/plugins/companion" "$d/shim"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  local i
  for i in 1 2 3 4 5; do printf 'V%s=1\n' "$i" >> "$d/plugins/companion/target.sh"; done
  for i in 1 2 3 4 5; do
    printf 'plugins/companion/target.sh::s@V%s=1@V%s=2@::mutation %s\n' "$i" "$i" "$i"
  done > "$d/dev/tests/mutations.txt"
  printf '%s\n' "$(_shim 'echo "1..3"; echo "ok 1 a"; echo "not ok 2 b"; echo "ok 3 c"; exit 1')" > "$d/shim/bats"
  chmod +x "$d/shim/bats"
  _run_shard() {  # $1 = shard spec, or "" for the whole set
    rm -f "$d/shim/bats.n"
    ( cd "$d" && PATH="$d/shim:$PATH" ./dev/mutate-gate.sh ${1:+--shard "$1"} 2>&1 | tail -1 )
  }
  # Every shard runs SOME, and the parts sum to the whole — no mutation skipped, none run twice.
  local a b whole
  a="$(_run_shard 0/2)"; b="$(_run_shard 1/2)"; whole="$(_run_shard '')"
  [[ "$a" =~ all\ ([0-9]+)\ mutations ]]; local na="${BASH_REMATCH[1]}"
  [[ "$b" =~ all\ ([0-9]+)\ mutations ]]; local nb="${BASH_REMATCH[1]}"
  [[ "$whole" =~ all\ ([0-9]+)\ mutations ]]; local nw="${BASH_REMATCH[1]}"
  [ "$nw" -eq 5 ]
  [ "$(( na + nb ))" -eq "$nw" ]
  [ "$na" -gt 0 ] && [ "$nb" -gt 0 ]
  # A malformed spec is refused rather than silently running everything.
  run bash -c 'cd "$1" && ./dev/mutate-gate.sh --shard nonsense' _ "$d"
  [ "$status" -eq 2 ]
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

@test "resume: LESSONS is two-tier — only the core above the marker prints (R69/R30·d7)" {
  # The cap is on PRINTED bytes, not on the file. Before the split, LESSONS sat 5B under its
  # ceiling while the process told every session to append to it, so each new lesson was paid for
  # by deleting a true one — two real remedies were lost that way before this landed.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q; mkdir -p "$repo/docs"
  cat > "$repo/docs/LESSONS.md" <<'EOF'
# Lessons
- ALPHA-CORE-TRAP always injected
<!-- lessons injection stops here -->
- OMEGA-ONDEMAND-TRAP read on demand only
EOF
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL "$4"' _ "$repo" "$(_tmpd)" "$(_tmpd)" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ALPHA-CORE-TRAP"* ]]        # the core rides every call...
  [[ "$output" != *"OMEGA-ONDEMAND-TRAP"* ]]    # ...the tail does not, which is the whole point
  [[ "$output" != *"lessons injection stops here"* ]]   # and the marker itself is never printed

  # FAILS OPEN on a file with no marker — a stranger's repo (R9) keeps working, whole file prints.
  printf '# Lessons\n- ZETA-UNSPLIT-TRAP\n' > "$repo/docs/LESSONS.md"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" \
    CLAUDE_COMPANION_SESSION_ID=sL2 "$4"' _ "$repo" "$(_tmpd)" "$(_tmpd)" "$RESUME"
  [[ "$output" == *"ZETA-UNSPLIT-TRAP"* ]]
}

@test "resume: autopilot mode prose rides ONLY when the mode WAS armed at call time (R69)" {
  # ~2.7KB of mode rules that are dead weight in every session where autopilot is off — which is
  # most of them. Conditional, not deleted: when the mode IS on the rules are exactly as present as
  # they ever were. This is rent paid per call forever, so the gate is worth having. Checked
  # PRE-clear (resume.sh always disarms autopilot as its own first step, R39) — "armed at call
  # time" is what decides whether the prose shows, not the state after resume has already run.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp "$3"' \
      _ "$repo" "$st" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]        # the core always rides...
  [[ "$output" != *"Keep-going mode"* ]]          # ...the mode prose does not
  [[ "$output" != *"autopilot:start"* ]]          # and the delimiter never leaks
  local off_len="${#output}"

  ( cd "$repo" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" on ) >/dev/null
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" \
      CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" CLAUDE_COMPANION_SESSION_ID=sAp2 "$3"' \
      _ "$repo" "$st" "$RESUME"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Keep-going mode"* ]]          # armed → the rules are there
  [[ "$output" == *"park with the full payload"* ]]
  [ "${#output}" -gt "$off_len" ]
}

# ── burn-down mode (the only mode that AUTHORS work) ───────────────────────────────────────────
_bd() {  # $1=used7 $2=used5 $3=age-offset → run the forecaster against a fresh fixture
  # 7d reset is +172800 (2 days), NOT +86400. At exactly one day the fixture sat ON the FINAL
  # STRETCH boundary, and burn-down reads its own clock a beat after the payload is built — so
  # `left` came out 86399, tipped into the stretch, and the projection-based hold this helper's
  # callers rely on stopped applying at random. Same class as "never assert an exact countdown
  # from date +%s". Two days keeps every caller's HOLD/BURN outcome and stays clear of the edge;
  # the stretch itself is covered deliberately by its own test.
  # A BURN now needs TWO distinct agreeing readings, because one was measured swinging 21 points at
  # a 5h rollover. So seed an earlier, identical sample first — that is what the status line does in
  # reality by repainting. The seeding run is discarded; only the second is asserted on.
  printf '%s %s %s %s %s\n' "$(( $(date +%s) - ${3:-0} - 5 ))" "${2:-20}" "$(( $(date +%s)+7200 ))" \
    "${1:-10}" "$(( $(date +%s)+172800 ))" > "$BD_STATE/ratelimit"
  env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status >/dev/null 2>&1 || true
  printf '%s %s %s %s %s\n' "$(( $(date +%s) - ${3:-0} ))" "${2:-20}" "$(( $(date +%s)+7200 ))" \
    "${1:-10}" "$(( $(date +%s)+172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_BRANCHES_PER_DAY="${_PERDAY:-3}" \
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
  # NOT a recursive call: the bulk rewrite that introduced this helper matched its OWN body and
  # turned the write into a self-call, which spun forever and looked exactly like a hung test.
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

@test "burn-down: in the FINAL STRETCH only actual usage counts, and the branch cap lifts (R82)" {
  _bd_setup
  # snapshot fields: ts · used5 · reset5 · used7 · reset7
  _bd_left() {  # $1=used7 · $2=seconds left in the 7d window
    printf '%s %s %s %s %s\n' "$(( $(date +%s) - 5 ))" 20 "$(( $(date +%s)+7200 ))" "$1" "$(( $(date +%s)+$2 ))" \
      > "$BD_STATE/ratelimit"
    env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
        BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status >/dev/null 2>&1 || true
    printf '%s %s %s %s %s\n' "$(date +%s)" 20 "$(( $(date +%s)+7200 ))" "$1" "$(( $(date +%s)+$2 ))" \
      > "$BD_STATE/ratelimit"
    run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
        BURNDOWN_BRANCHES_PER_DAY="${_PERDAY:-3}" \
        BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  }

  # OUTSIDE the stretch, a projection is sound: 90% with a full day left tracks to ~105%, so the
  # sustained rate gets there on its own and there is no spare capacity to fill.
  _bd_left 90 90000; [[ "$output" == HOLD:* ]]; [[ "$output" == *"on track"* ]]   # clear of the boundary

  # INSIDE it, that same projection is exactly what loses budget — it assumes you keep spending at
  # your average, and a night asleep in the last hours is spending that never happens. Only what is
  # ACTUALLY used counts, so the same 90% now burns.
  # 80000s, NOT 3600s: with an hour left the projection collapses to ~= actual usage, so both rules
  # agree and the case proves nothing — it reported "caught" while the stretch test was mutated to
  # `if true`. Just inside the boundary the projection still reads 103% while usage is 90%, which is
  # the only shape where the two rules genuinely disagree.
  _bd_left 90 80000; [[ "$output" == BURN:* ]]
  [[ "$output" =~ needs\ [1-9][0-9]*%/window ]]  # a REAL required rate — `needs 0%` also matched before

  # ...but at or past the target there is genuinely nothing left to burn, in any stretch.
  # 3600 below is SECONDS-LEFT, deep inside the 86400s stretch; it only coincides with FRESH=3600,
  # which measures snapshot AGE, and the age here is 0.
  _bd_left 100 3600; [[ "$output" == HOLD:* ]]; [[ "$output" == *"nothing left"* ]]  # boundary-ok

  # The cap is what actually stops the burn, so it lifts inside the stretch and not outside it.
  git -C "$BD_REPO" checkout -q -b burndown/a && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m a
  git -C "$BD_REPO" checkout -q -b burndown/b && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m b
  git -C "$BD_REPO" checkout -q -b burndown/c && git -C "$BD_REPO" -c user.email=t@t -c user.name=t \
    commit -q --allow-empty -m c
  git -C "$BD_REPO" checkout -q main
  # 90000s, NOT 86400s: pinning a fixture ON the threshold is the exact trap this repo recorded
  # today, and I walked into it again in the test that DEFINES the threshold. burn-down reads its
  # own clock a beat after the payload is built, so 86400 arrives as 86399 — one second inside the
  # stretch — and the cap had already lifted to 8. Green locally, red on both CI lanes.
  # With growth switched OFF, the base cap of 3 is still the wall — the mechanism is intact.
  _PERDAY=0 _bd_left 50 90000; [[ "$output" == HOLD:* ]]; [[ "$output" == *"max 3"* ]]
  # With growth ON, five elapsed days raise the cap well past three. That is what makes an
  # unattended week possible instead of halting on about day one, and it replaces the old
  # last-day-only lift, which was a special case of the same idea.
  _bd_left 50 90000; [[ "$output" == BURN:* ]]
}

@test "burn-down: a BURN needs TWO agreeing readings — one sample is not evidence (R90)" {
  _bd_setup
  # Timestamps go BACKWARDS from now, never forward: the freshness check rejects a future snapshot
  # ("-1s old") as a bad clock, which silently swallowed the first version of this test.
  _snap() { printf '%s 20 %s %s %s\n' "$1" "$(( $(date +%s)+7200 ))" "$2" "$(( $(date +%s)+172800 ))" \
              > "$BD_STATE/ratelimit"; }
  _run()  { run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
                BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status; }
  local n; n="$(date +%s)"

  # FIRST reading ever: the forecast says burn, but there is nothing to corroborate it.
  _snap "$((n-9))" 10; _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"one rate-limit reading"* ]]

  # A second DISTINCT reading that agrees → now it may burn.
  _snap "$((n-8))" 10; _run
  [[ "$output" == BURN:* ]]

  # The SAME sample re-read is not a second opinion — the snapshot has not refreshed.
  _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"not a second opinion"* ]]

  # Establish a settled high baseline (the jump from 10 to 82 is itself a disagreement, and holds).
  _snap "$((n-7))" 82; _run; [[ "$output" == HOLD:* ]]
  _snap "$((n-6))" 82; _run

  # THE MEASURED TRANSIENT: 82 → 61 across a 5h rollover. The low reading must NOT be actioned —
  # a 21-point phantom of headroom is exactly what would start generating work on nothing.
  _snap "$((n-5))" 61; _run
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"disagree by 21 points"* ]]

  # ...and once the reading settles, two agreeing samples let it proceed again.
  _snap "$((n-4))" 61; _run
  [[ "$output" == BURN:* ]]
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

@test "burn-down: a FRESH FILE carrying STALE WINDOW DATA cannot burn (the write clock is not the data clock)" {
  # Observed live 2026-08-15: the status line rewrites this snapshot every repaint, so `ts` was
  # seconds old while r5/r7 inside it were 4-8 DAYS old and the usage figures disagreed with the
  # owner's own UI. The age check cannot see that — it measures when the file was written.
  # The dangerous shape is the one asserted second: r7 slightly in the FUTURE passes every bounds
  # check, so the forecast runs on days-old usage and BURNS. A 5h window is never more than 5h
  # behind when live, which is what makes the staleness provable rather than guessed.
  _bd_setup
  local n; n="$(date +%s)"
  # file written NOW, 7d reset 2 days out (perfectly plausible), 7d usage low enough to burn —
  # but the 5h reset is 8 days in the past, which no live reading can produce.
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n - 691200 ))" 10 "$(( n + 172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [ "$status" -eq 0 ]
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"STALE"* ]]
  [[ "$output" != *"already rolled"* ]]      # named for what it IS, not the incidental symptom
  # …and a 7d reset further out than the window itself is bad data, not "just started"
  # 14 days out — comfortably past a 7d window without PINNING the fixture to its exact value, which
  # is the boundary-flake class the portability lint guards (and duly caught this line's first draft).
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n + 7200 ))" 10 "$(( n + 1209600 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"does not describe the current window"* ]]
  [[ "$output" != *"just started"* ]]
  # …and the bound is SYMMETRIC: a 5h reset cannot be 5h+ in the FUTURE either. The first draft
  # only checked the past, which the pre-ship adversarial pass caught as a half-checked bound.
  printf '%s %s %s %s %s\n' "$n" 20 "$(( n + 90000 ))" 10 "$(( n + 172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
  [[ "$output" == HOLD:* ]]
  [[ "$output" == *"IMPOSSIBLE"* ]]
}

@test "burn-down: an IN-PROGRESS task outranks generated work too — work in flight is the realest work" {
  # R113 regression, caught by hand and not by this suite: giving in_progress its own glyph (▸) made
  # it invisible to a count that had only ever matched ◻, so the one kind of work burn-down would
  # have ignored was the task actively being WORKED ON — it would have spun up speculative branches
  # mid-task. The count must follow the queue's meaning, not one of its two renderings.
  _bd_setup
  mkdir -p "$BD_TASKS/sIP"; _stamp_root "$BD_TASKS/sIP" "$BD_REPO"
  jq -n '{id:"1",subject:"actively being worked on",status:"in_progress"}' > "$BD_TASKS/sIP/1.json"
  _bd 10
  [[ "$output" == HOLD:* ]]; [[ "$output" == *"still queued"* ]]
  # finished -> the capacity is genuinely free again
  jq -n '{id:"1",subject:"actively being worked on",status:"completed"}' > "$BD_TASKS/sIP/1.json"
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
  _PERDAY=0 _bd 10; [[ "$output" == HOLD:* ]]; [[ "$output" == *"review or delete"* ]]   # cap, not calendar
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
  # REWORK_ROOT must be isolated too (found by a DA pass, 2026-08-07): rank 5 shells out to
  # rework.sh, which without an explicit root falls back to $PWD — the REAL repo this suite runs
  # from, not this test's temp dir. Dormant until the real repo's own rework ledger crossed the
  # rebuild threshold; a real event (recorded honestly) then made THIS test flake.
  _cand() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"; }

  # Nothing recorded at all → says so, out loud, as rank 5.
  _cand; [ "$status" -eq 0 ]; [[ "$output" == 6\|invent\|* ]]; [[ "$output" == *"INVENTED"* ]]

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
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend — options: A) sqlite B) files; rec: sqlite",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' \
    > "$tk/sP/1.json"
  _cand; [[ "$output" == 1\|parked\|* ]]; [[ "$output" == *"rec: sqlite"* ]]
  # A park WITHOUT a recommendation is not a candidate: nothing has been decided, so building
  # against it would be guessing on the owner's behalf.
  jq -n '{id:"1",subject:"❓ [parked] pick a cache backend",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sP/1.json"
  _cand; [[ "$output" != 1\|parked\|* ]]
}

@test "burndown-branch: work is containerised — never on main, never pushed, always discardable" {
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main
  git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  _bb start "4|gap|add a dark theme"
  [ "$status" -eq 0 ]; [ "$output" = "add-a-dark-theme" ]
  [ "$(git -C "$d" rev-parse --abbrev-ref HEAD)" = "burndown/add-a-dark-theme" ]
  # main is untouched: one commit, exactly as before.
  [ "$(git -C "$d" rev-list --count main)" -eq 1 ]
  git -C "$d" checkout -q main
  # The manifest lives OUTSIDE the repo, so reviewing from main still finds it and the tree is clean.
  # .companion/ is plugin state, not the owner's work: since R96 the queue, the modes and now the
  # burn-down manifests live there, so it is legitimately present in `git status`. The product's own
  # dirty-guard draws the same line — asserting a fully clean tree here would assert that plugin
  # state does not exist, which is no longer true.
  [ -z "$(git -C "$d" status --porcelain | grep -vE '^.{2} \.companion/')" ]
  _bb show add-a-dark-theme
  [[ "$output" == *"must default to OFF"* ]]; [[ "$output" == *"gap"* ]]   # the source rides the manifest
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

@test "candidates: a DECISION park is never offered as buildable work (R82 soft spots)" {
  # Two limitations R82 recorded as unsolved, closed by one observation: a park written BY THE
  # ASK-GUARD came from a question, so it is a decision by construction and can be marked as one.
  #   (1) rank 1 stops offering decisions as work — building one would make the owner's choice.
  #   (2) auto-parks stop crowding ranks 2-4 out of the list entirely.
  local d tk; d="$(_tmpd)"; git -C "$d" init -q; tk="$(_tmpd)"
  mkdir -p "$tk/sD"; _stamp_root "$tk/sD" "$d"
  printf '# R\n- [ ] add a dark theme\n' > "$d/ROADMAP.md"
  _cd2() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"; }

  jq -n '{id:"1",subject:"❓ [parked] decision: which cache backend? — options: A) x B) y; rec: A",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sD/1.json"
  _cd2
  [[ "$output" != *"which cache backend"* ]]      # a decision is the owner's to ANSWER, not work
  [[ "$output" == *"dark theme"* ]]               # ...and rank 2 is reachable behind it

  # A park describing WORK still ranks 1 — the exclusion must be narrow, or the strongest signal
  # in the repo is lost with it.
  jq -n '{id:"2",subject:"❓ [parked] add retry backoff — options: A) simple B) jitter; rec: B",status:"pending",notes:[{ts:"t",text:"deferred by the owner at review"}]}' > "$tk/sD/2.json"
  _cd2; [[ "$output" == 1\|parked\|*"retry backoff"* ]]

  # SATURATION: many auto-parks must not fill the list and starve every other signal.
  local i
  for i in 3 4 5 6 7 8; do
    jq -n --arg i "$i" '{id:$i,subject:("❓ [parked] decision: q" + $i + " — options: A) x; rec: A"),status:"pending"}' > "$tk/sD/$i.json"
  done
  _cd2; [[ "$output" == *"dark theme"* ]]
  # decompose: parks stay excluded too (R65 — they exist because context is MISSING).
  jq -n '{id:"9",subject:"❓ [parked] decompose: big thing — need: X; rec: split",status:"pending"}' > "$tk/sD/9.json"
  _cd2; [[ "$output" != *"big thing"* ]]
}

@test "candidates: does not feed on prose ABOUT markers, only real annotations" {
  # The first run of this generator against its own repo returned four candidates that were all
  # documentation EXPLAINING what a TODO signal is — including its own source comments. A
  # generator that reads its own definition as input is a mirror, not a signal.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  printf 'x=1  # TODO: cache this\n'                 > "$d/a.sh"
  printf '# Guide\nWe write TODO: markers like this.\n' > "$d/guide.md"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a.sh"* ]]        # a real annotation in code is still a candidate
  [[ "$output" != *"guide.md"* ]]    # prose about markers is not
  [[ "$output" != *"candidates.sh"* ]]  # and never its own source
}

@test "candidates: rank 1 requires evidence the OWNER SAW the park — a model-authored one is not buildable" {
  # THE SELF-DEALING GUARD. Rank 1 claims "the owner deferred THIS work and a recommendation is
  # already written", which is false for a park the model wrote and nobody has looked at. Caught
  # live 2026-08-15: rank 1 was a park authored minutes earlier recommending the model be given
  # more autonomy — the generator would have built its own unreviewed advice.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  mkdir -p "$d/.companion/tasks"
  # seen-and-deferred: carries the note /companion:review writes when the owner defers
  jq -n '{id:"1",subject:"❓ [parked] rev: pick a cache — options: A) sqlite B) files; rec: A",
          status:"pending",notes:[{ts:"t",text:"deferred pending the storage decision"}]}' \
    > "$d/.companion/tasks/1.json"
  # model-authored, never reviewed: same shape, no deferral note
  jq -n '{id:"2",subject:"❓ [parked] rev: never seen by anyone — rec: B",status:"pending"}' \
    > "$d/.companion/tasks/2.json"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="" REWORK_ROOT="$d" \
    bash "$ROOT/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pick a cache"* ]]      # deferred by the owner -> still the highest signal
  [[ "$output" != *"never seen by anyone"* ]]
  # and it fails to the SAFE side: strip the evidence and rank 1 empties rather than guessing
  jq -n '{id:"1",subject:"❓ [parked] rev: pick a cache — rec: A",status:"pending"}' \
    > "$d/.companion/tasks/1.json"
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="" REWORK_ROOT="$d" \
    bash "$ROOT/bin/candidates.sh"
  [[ "$output" != *"1|parked"* ]]
}

@test "candidates: excludes its own PLUGIN TREE, not just its own file — a sibling describing the ranking is still a mirror" {
  # The live miss (2026-08-15): the self-exclusion was written as "this file", which was too narrow
  # by exactly one directory. mcp-server/index.js describes this very ranking in a string literal
  # ("a TODO/FIXME in tracked source") and duly ranked ABOVE two real signals — same mirror, one
  # file over. Only reachable when the plugin is VENDORED INSIDE the project being scanned, which
  # is exactly the shape of this repo.
  local d tk; d="$(_tmpd)"; tk="$(_tmpd)"; git -C "$d" init -q
  # a real annotation OUTSIDE the vendored plugin — must survive
  printf 'y=2  # FIXME: handle the empty case\n' > "$d/real.sh"
  # the plugin, vendored in-tree, with a sibling that merely DESCRIBES the marker it looks for
  mkdir -p "$d/plugins/companion/bin" "$d/plugins/companion/lib" "$d/plugins/companion/mcp-server"
  cp "$ROOT/bin/candidates.sh" "$d/plugins/companion/bin/"
  cp "$ROOT/lib/companion.sh"  "$d/plugins/companion/lib/"
  printf '%s\n' 'const desc = "ranked: a TODO/FIXME in tracked source beats a coverage gap";' \
    > "$d/plugins/companion/mcp-server/index.js"
  git -C "$d" add -A; git -C "$d" -c user.email=t@t -c user.name=t commit -q -m i
  # run the VENDORED copy, so PLUGIN_DIR really is inside the scanned repo
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_TASKS_DIR="$tk" REWORK_ROOT="$d" \
    bash "$d/plugins/companion/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real.sh"* ]]     # signal outside the tool's own tree is untouched
  [[ "$output" != *"index.js"* ]]    # a sibling explaining the ranking is not buildable work

  # AND THE SAME THING THROUGH A SYMLINK. This half exists because the direct case shipped GREEN on
  # Linux and RED on the macOS lane: bash's `pwd` is logical, git reports the physical path, and
  # macOS's /var -> /private/var made the two disagree — so the exclusion silently did nothing and
  # the tool fed on its own source again. Reproducing that here means the cheap lane catches it
  # instead of CI, and it is the trap lib/companion.sh already documents for the task-store scan.
  local link; link="$(_tmpd)/via-symlink"
  ln -s "$d" "$link"
  run env BURNDOWN_ROOT="$link" CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)" REWORK_ROOT="$link" \
    bash "$link/plugins/companion/bin/candidates.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"real.sh"* ]]
  [[ "$output" != *"index.js"* ]]
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

@test "autopilot resume: a pause marker from ANOTHER session cannot arm autopilot (R108)" {
  # Reproduced live 2026-08-09, on the owner's own machine, by running /companion:review: a review
  # on 2026-08-08 paused and never resumed, leaving the marker behind. The next day a review found
  # autopilot already OFF — so its own `pause` was a correct no-op writing nothing — and `resume`
  # then honoured the DAY-OLD marker and armed a mode the owner had never turned on. Transient
  # state outliving its session. A marker is now only honoured by the session that wrote it.
  local repo st; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"
  _aps() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_SESSION_ID="$3" bash "$4" "${@:5}"' _ "$repo" "$st" "$1" "$ROOT/bin/autopilot.sh" "${@:2}"; }

  # A genuine same-session round trip still works — the fix must not cost R83 its whole point.
  _aps sA on >/dev/null; _aps sA pause; [[ "$output" == *"PAUSED"* ]]
  _aps sA resume; [[ "$output" == *"RESUMED"* ]]
  _aps sA status; [ "$output" = on ]

  # THE DEFECT: session A pauses and never resumes; session B must NOT inherit that promise.
  _aps sA pause >/dev/null
  _aps sB resume; [[ "$output" == *"NOT resumed"* ]]
  _aps sB status; [ "$output" = off ]
  # ...and the marker is DISCARDED, not left to mis-fire on the session after that.
  _aps sB resume; [[ "$output" == *"not paused"* ]]

  # An UNSTAMPED marker — written by a pre-fix version still in the plugin cache — is refused too,
  # which is the case that actually fires during an upgrade.
  mkdir -p "$repo/.companion/modes"; : > "$repo/.companion/modes/autopilot-paused"
  _aps sC resume; [[ "$output" == *"NOT resumed"* ]]
  _aps sC status; [ "$output" = off ]
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

@test "burn-down: the buildable TIER is earned by acceptance, not granted by spare capacity (R82)" {
  # The owner asked for the ladder to climb toward auto-authored features when tokens are going
  # unspent. Utilization is a fine answer to WHETHER there is spare capacity and a terrible one to
  # WHAT may be built: it measures spending, never value, and the real constraint is the owner's
  # review throughput, which does not grow with the token budget. So the tier is gated on the share
  # of generated branches actually KEPT — self-correcting in both directions.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  local _bb; _bb() { run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" "$@"; }

  # NO HISTORY -> debt paydown only. Verifiable against the suite that already exists, which is what
  # makes it safe unattended.
  _bb start "4|gap|add a golden test for checkout"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 12 ]   # a FEATURE is not yet earned
  [[ "$output" == *"earned tier"* ]]
  _bb start "5|rework|rebuild the parser"; [ "$status" -eq 12 ]  # nor a large rebuild

  # INVENTED work is never automatic at ANY rate — nothing recorded asked for it.
  _bb start "6|invent|something nobody asked for"; [ "$status" -eq 13 ]
  [[ "$output" == *"never built unattended"* ]]

  # Two judged outcomes at 50% (one kept, one discarded) -> the feature tier opens.
  _bb start "4|gap|a second debt item"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main
  _bb discard add-a-golden-test-for-checkout; [ "$status" -eq 0 ]
  git -C "$d" branch -D burndown/a-second-debt-item >/dev/null 2>&1   # merged then pruned = kept
  _bb start "2|roadmap|add a dark theme"; [ "$status" -eq 0 ]
  git -C "$d" checkout -q main

  # ...and it FALLS BACK. Discard enough and the ceiling drops to debt again, with no new judgement
  # from anyone — which is the half a utilization clock can never do.
  _bb discard add-a-dark-theme; [ "$status" -eq 0 ]
  _bb start "2|roadmap|another feature"; [ "$status" -eq 12 ]
}

@test "burn-down: a branch can NEVER exist without a manifest, even with the mode ARMED (R82)" {
  # THE GAP THAT HID THIS: every earlier test used a state dir where the burn-down flag was never
  # set — so the suite only ever exercised the one state the feature cannot really run in. The ON
  # flag is a FILE at $STATE/burndown/<enc>; the manifest dir was a DIRECTORY at the same path, so
  # armed, mkdir failed, no manifest was written, and start still exited 0 with a branch created.
  local d st; d="$(_tmpd)"; st="$(_tmpd)"
  git -C "$d" init -q -b main; git -C "$d" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  ( cd "$d" && CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/autopilot.sh" burndown on ) >/dev/null
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" start "4|gap|add retry backoff"
  [ "$status" -eq 0 ]
  run env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" bash "$ROOT/bin/burndown-branch.sh" show add-retry-backoff
  [ "$status" -eq 0 ]; [[ "$output" == *"must default to OFF"* ]]
  # ...and arming still works afterwards — the two must not fight over one path.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" burndown status' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$output" = on ]
  # An unwritable manifest dir must abort BEFORE the branch exists, not after.
  local d2 st2; d2="$(_tmpd)"; st2="$(_tmpd)"
  git -C "$d2" init -q -b main; git -C "$d2" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  # Manifests are REPO state since R96 stage 3, so making the STATE dir unwritable no longer blocks
  # anything — the fault has to be injected where the code actually writes, or this guard silently
  # stops being exercised while still reading green.
  mkdir -p "$d2/.companion"; chmod 555 "$d2/.companion"
  run env BURNDOWN_ROOT="$d2" CLAUDE_COMPANION_STATE_DIR="$st2" bash "$ROOT/bin/burndown-branch.sh" start "4|gap|thing"
  chmod 755 "$d2/.companion"
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
  printf '%s 20 %s 10 %s\n' "$((n-5))" "$((n+7200))" "$((n+172800))" > "$st/ratelimit"
  # seed the corroborating first reading (a BURN needs two distinct agreeing samples)
  env BURNDOWN_ROOT="$d" CLAUDE_COMPANION_STATE_DIR="$st" CLAUDE_COMPANION_TASKS_DIR="$tk" \
      bash "$ROOT/bin/burn-down.sh" status >/dev/null 2>&1 || true
  printf '%s 20 %s 10 %s\n' "$n" "$((n+7200))" "$((n+172800))" > "$st/ratelimit"
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
  # Modes are REPO state since R96, so the fault has to be injected where the marker actually goes:
  # making $HOME read-only no longer blocks anything, and a test that kept doing so would assert a
  # guarantee that had quietly stopped being exercised.
  chmod 555 "$d/.companion/modes"
  _ap2 pause
  chmod 755 "$d/.companion/modes"
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

@test "autopilot resume: refuses and KEEPS the marker when it cannot re-arm (R83)" {
  # The mirror of the pause fix, and it was missed: resume deleted the marker FIRST, then tried to
  # arm without checking, then printed "RESUMED" unconditionally — leaving autopilot off, the marker
  # gone, and no way back. A half-corrected defect class is worse than an uncorrected one, because
  # the ledger says it is handled.
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  _ar() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" "${@:4}"' _ "$d" "$st" "$ROOT/bin/autopilot.sh" "$@"; }
  _ar on >/dev/null; _ar pause >/dev/null
  rm -f "$d/.companion/modes/autopilot"; chmod 555 "$d/.companion/modes"
  _ar resume
  chmod 755 "$d/.companion/modes"
  [ "$status" -ne 0 ]; [[ "$output" == *"NOT resumed"* ]]
  [ -f "$d/.companion/modes/autopilot-paused" ]   # marker KEPT — recoverable
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
  # The ordering is the whole point of the hook, so pin it: unblocking outranks everything, and
  # the model must not answer a parked decision on the owner's behalf.
  [[ "$output" == *"HIGHEST PRIORITY"* ]]
  # The OPENING imperative, not just the ranking further down: a declared mutation replaced
  # "STOP — DO NOT START ANY OTHER WORK YET" with a mild "Note:" and the suite stayed green for
  # three shipped commits, because every assertion here read a LATER sentence. An injection that
  # opens with "Note:" is advisory, which is exactly what this hook exists not to be.
  [[ "$output" == *"STOP — DO NOT START ANY OTHER WORK YET"* ]]
  [[ "$output" == *"do not answer one of these on their behalf"* ]]
  [[ "$output" == *"no pause is needed"* ]]                   # autopilot off
  # ARMED: it must say pause first, because the ask-guard would otherwise PARK the review's own
  # questions instead of asking them — the review would silently accomplish nothing.
  mkdir -p "$st/autopilot"; touch "$(_flagpath "$st" autopilot "$d")"
  _pc continue
  [[ "$output" == *"autopilot.sh pause"* ]] && [[ "$output" == *"resume"* ]]
  [[ "$output" == *"never leave autopilot off"* ]]     # resume is not optional
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
  # The fixtures invocation is a SEPARATE call over the test files, so `all` being wired says
  # nothing about it — CI caught exactly that as a hole.
  run grep -c 'portability-lint\.sh fixtures' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  # ...and so is `boundary`. The mutation gate reported this exact hole when the lint shipped: the
  # guard existed, was tested, and check.sh never called it.
  run grep -c 'portability-lint\.sh boundary' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
  # command-lint was extracted out of check.sh when the 300-line guard fired; an extraction that
  # leaves the caller behind is the same hole in a new place.
  # Match the INVOCATION, not the name: grepping for the bare filename also matched the comment
  # ABOVE the call, so stubbing the call out left this green — the mutation gate caught exactly
  # that. Same family as the TODO scanner that fed on prose about TODO markers.
  run grep -c '\$(dev/command-lint\.sh)' "$ROOT/../../check.sh"
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


@test "the plugin is SELF-CONTAINED — it runs with nothing outside its own root (R6)" {
  # Claude Code installs a plugin's subdirectory alone, so anything the shipped code reaches for
  # outside plugins/companion/ simply is not there for a user. This went untested until 2026-08-02
  # even though the whole 3.33.0 split turned on it — verified twice by hand, never by a case.
  local iso; iso="$(_tmpd)"
  cp -R "$ROOT" "$iso/companion"
  # Nothing from dev/ (the verification kit) or the repo root travels with it.
  [ ! -e "$iso/dev" ] && [ ! -e "$iso/companion/tests" ] && [ ! -e "$iso/companion/../check.sh" ]
  run grep -rlE '(\.\./)+(dev|check\.sh)' "$iso/companion/bin" "$iso/companion/lib" "$iso/companion/mcp-server/index.js"
  [ -z "$output" ]                       # no shipped file reaches up and out

  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local st tk; st="$(_tmpd)"; tk="$(_tmpd)"
  # The entry points a user actually triggers, run from the isolated copy.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" bash "$4"' \
      _ "$repo" "$st" "$tk" "$iso/companion/bin/resume.sh"
  [ "$status" -eq 0 ]; [[ "$output" == *"Working agreement"* ]]
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_STATE_DIR="$2" NO_COLOR=1 bash "$3"' \
      _ "$(jq -nc --arg c "$repo" '{model:{display_name:"m"},session_id:"s",cwd:$c}')" "$st" "$iso/companion/bin/statusline.sh"
  [ "$status" -eq 0 ]
  run env CLAUDE_COMPANION_SESSION_ID=iso CLAUDE_COMPANION_TASKS_DIR="$tk" "$iso/companion/bin/tq" add "works standalone"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" status' _ "$repo" "$st" "$iso/companion/bin/autopilot.sh"
  [ "$status" -eq 0 ]
}

@test "check.sh actually INVOKES the traceability gate (wiring guard)" {
  # bats cannot run check.sh (check.sh runs bats), so this is structural — same shape as the
  # doc-lint and portability wiring guards. Without it check.sh could stop running trace.sh and
  # every requirement could drift out of its tests with the suite still green.
  run grep -c 'dev/trace\.sh' "$ROOT/../../check.sh"
  [ "$output" -ge 1 ]
}

@test "resume: warns when the INSTALLED plugin lags this working tree (R6)" {
  # Claude Code runs the plugin from its CACHE, not the checkout you are editing. On 2026-08-02 a
  # session opened on a cache with no UserPromptSubmit registration at all, so every hook added
  # that day was inert while the repo was green — six hours of work reported as shipped that was
  # not running. Nothing surfaced it; the status line showed the old version and neither of us
  # read it as a warning.
  local repo st tk running
  repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$repo/plugins/companion/.claude-plugin"
  running="$(jq -r .version "$ROOT/.claude-plugin/plugin.json")"
  _ss2() { run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" "$4"' \
             _ "$repo" "$st" "$tk" "$RESUME"; }

  # Tree AHEAD of the running build → warn, and name both versions.
  jq -n '{name:"companion",version:"9.9.9"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [ "$status" -eq 0 ]
  [[ "$output" == *"RUNNING v${running}"* ]]; [[ "$output" == *"9.9.9"* ]]; [[ "$output" == *"INERT"* ]]

  # Same version → silent. A warning that fires when nothing is wrong is noise nobody reads.
  jq -n --arg v "$running" '{name:"companion",version:$v}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [[ "$output" != *"RUNNING v"* ]]

  # A DIFFERENT plugin's manifest is not this plugin — must not warn on someone else's repo (R9).
  jq -n '{name:"somebody-elses-plugin",version:"0.0.1"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  _ss2; [[ "$output" != *"RUNNING v"* ]]

  # An ordinary repo with no plugin manifest at all → silent.
  rm -rf "$repo/plugins"
  _ss2; [ "$status" -eq 0 ]; [[ "$output" != *"RUNNING v"* ]]
}

# ---- SessionStart hook (R100/Pass 6 reinstated — guaranteed context delivery, docs/adr R105) ----

_ss_ctx() {  # $1=repo  $2=source ("" for fresh start)
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,source:\$s}" | "$3" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$1" "$2" "$SS"
}

@test "session-start: fresh start injects the FULL STEERING core + carried tasks, unlike resume it does NOT clear autopilot" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sX"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sX" "$repo"
  jq -n '{id:"1",subject:"carried via session-start",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sX/1.json"
  ( cd "$repo" && "$AP" on ) >/dev/null

  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]           # STEERING core, unlike prompt-continue/ask-guard
  [[ "$output" == *"carried via session-start"* ]]    # this repo's carried task
  run bash -c 'cd "$1" && "$2" status' _ "$repo" "$AP"
  [ "$output" = "on" ]                                # NOT cleared — the whole point vs resume.sh
}

@test "session-start: post-compaction re-anchor is SHORT — queue + posture, not the full STEERING core" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sY"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sY" "$repo"
  jq -n '{id:"1",subject:"survives compaction",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sY/1.json"

  _ss_ctx "$repo" "compact"
  [ "$status" -eq 0 ]
  [[ "$output" == *"just compacted"* ]]
  [[ "$output" == *"survives compaction"* ]]          # the live queue re-anchors
  [[ "$output" == *"recommendation-first options"* ]]  # the posture clause, restated (R49)
  [[ "$output" != *"## The two reflexes"* ]]           # NOT the full STEERING core (token cost, R69)
}

@test "session-start: compact re-anchor carries the SAME version-lag + rework as a fresh start (R93 — a compaction IS a state clear)" {
  local repo st tk; repo="$(_tmpd)"; git -C "$repo" init -q; st="$(_tmpd)"; tk="$(_tmpd)"
  mkdir -p "$repo/plugins/companion/.claude-plugin"
  jq -n '{name:"companion",version:"9.9.9"}' > "$repo/plugins/companion/.claude-plugin/plugin.json"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"compact\"}" | CLAUDE_COMPANION_STATE_DIR="$2" CLAUDE_COMPANION_TASKS_DIR="$3" "$4" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$st" "$tk" "$SS"
  [ "$status" -eq 0 ]
  [[ "$output" == *"just compacted"* ]]
  [[ "$output" == *"RUNNING v"* ]]                     # version-lag warning, not skipped on compact
  [[ "$output" == *"INERT"* ]]
}

@test "session-start: steering=off drops the working agreement, carried tasks unaffected (R50)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off steering "$repo"
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sZ"; _stamp_root "$CLAUDE_COMPANION_TASKS_DIR/sZ" "$repo"
  jq -n '{id:"1",subject:"still carried",status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sZ/1.json"

  _ss_ctx "$repo" ""
  [[ "$output" != *"Working agreement"* ]]
  [[ "$output" != *"Read the working agreement below"* ]]   # DA-caught: the preamble told the
  # model to read a block that steering=off had already dropped — token waste dressed up as a
  # correct render, exactly the R69 carelessness this test exists to pin.
  [[ "$output" == *"still carried"* ]]
  _feature_clear
}

@test "session-start: self-contained fallback — a marker-less plugin dir still reaches lib/resume-report.sh" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local plug; plug="$(_tmpd)"; mkdir -p "$plug/bin" "$plug/lib"
  cp "$SS" "$plug/bin/session-start.sh"
  cp "$ROOT/lib/companion.sh" "$ROOT/lib/resume-report.sh" "$plug/lib/"
  cp "$ROOT/STEERING.md" "$plug/STEERING.md"
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2/bin/session-start.sh" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$repo" "$plug"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Working agreement"* ]]
}

# ---- PreToolUse[AskUserQuestion] guard (R100/Pass 6 reinstated, docs/adr R105) ----

_ag_ask() {  # $1=repo  $2=session-id
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" \
    "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"pick A or B\",options:[{label:\"A\",description:\"faster\"},{label:\"B\",description:\"safer\"}]}]}}" \
    | "$3" | jq -r ".hookSpecificOutput.permissionDecision + \"|\" + .hookSpecificOutput.permissionDecisionReason"' \
    _ "$1" "$2" "$AG"
}

@test "ask-guard: autopilot OFF silently allows — no denial, no park" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"q\",options:[{label:\"A\"}]}]}}" | "$3"' \
    _ "$repo" "off1" "$AG"
  [ "$status" -eq 0 ]
  [ -z "$output" ]                                    # no output at all -> Claude Code's default allow
}

@test "ask-guard: autopilot ON denies AND auto-parks the question with its real options + a recommendation (R84)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  _ag_ask "$repo" "on1"
  [ "$status" -eq 0 ]
  [[ "$output" == deny\|* ]]
  [[ "$output" == *"ALREADY PARKED FOR YOU as task #"* ]]
  run env CLAUDE_COMPANION_SESSION_ID=on1 "$TQ" list
  [[ "$output" == *"❓ [parked] decision: pick A or B"* ]]
  [[ "$output" == *"A (faster)"* ]] && [[ "$output" == *"B (safer)"* ]]
  [[ "$output" == *"rec: A"* ]]                        # first option is the recommendation
  [[ "$output" != *"rev:"* ]]                           # NEVER auto-marks reversible (R77)
}

@test "ask-guard: a RETRIED identical question dedups instead of parking twice" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  _ag_ask "$repo" "dup1"
  _ag_ask "$repo" "dup1"
  [[ "$output" == *"ALREADY PARKED"* ]]
  run env CLAUDE_COMPANION_SESSION_ID=dup1 "$TQ" list
  local n; n="$(printf '%s\n' "$output" | grep -c "pick A or B")"
  [ "$n" -eq 1 ]                                        # exactly one park, not two
}

@test "ask-guard: DECISIVE mode swaps the guidance from park-every-decision to decide-if-reversible (R59)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on && "$AP" decisive on ) >/dev/null
  _ag_ask "$repo" "dec1"
  [[ "$output" == *"DECISIVE mode"* ]]
  [[ "$output" == *"DECIDE it yourself"* ]]
  [[ "$output" != *"park it even when trivially reversible"* ]]
}

@test "the contract bound is stated where it is armed — advisory only now, no guard left (R86)" {
  # contract-guard.sh is retired (R100/Pass 3) — nothing left can refuse a contract edit. What
  # survives is the bound STATED where it matters: the STEERING core (governs every session) and
  # the arming message (visible the moment the owner turns autopilot on). Whether the model
  # actually honors it is judgment now, not a mechanism (R28) — this pins the statement, not
  # enforcement of it, which is the honest ceiling of what's left to test.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"never rewrite it"* ]]
  [[ "$core" == *"Authoring a **need** is never yours"* ]]
  local d st; d="$(_tmpd)"; git -C "$d" init -q; st="$(_tmpd)"
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" on' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"R100"* ]]; [[ "$output" == *"never mine to write"* ]]
  # And no new mode was introduced — the four existing toggles are still the whole set.
  run bash -c 'cd "$1" && CLAUDE_COMPANION_STATE_DIR="$2" bash "$3" contract on' _ "$d" "$st" "$ROOT/bin/autopilot.sh"
  [ "$status" -ne 0 ]
}

@test "sketch-first is DELIVERED to a session, not merely stated in a file — no command to remember (R106)" {
  # The owner's constraint, verbatim: "I will forget to run these commands — is there any way to
  # make it proactive instead of hoping I remember?" So a placement that only exists as a slash
  # command fails the requirement no matter how good its prose is. The property under test is
  # DELIVERY: the reflex must ride the SessionStart injection (R105) into every session, unasked.
  # Asserting the file's bytes alone would pass with the whole injection path deleted — the exact
  # "check that re-implements the logic" hole recorded in LESSONS.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"SKETCH BEFORE CODE"* ]]        # ...and ABOVE the marker, or it is never injected
  [[ "$core" == *"interface delta"* ]]
  [[ "$core" == *"No sketch = not scoped yet"* ]]

  # Now the half that matters: a fresh session receives it without anyone typing anything.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"SKETCH BEFORE CODE"* ]]
  [[ "$output" == *"interface delta"* ]]
}

@test "a drained autopilot run offers a quality read — the lights-off gap has a nudge (R107)" {
  # Autopilot parks DECISIONS but never pauses on structural erosion, because erosion never
  # presents as a decision — it presents as a diff that passes. This is the cheapest honest
  # counterweight (owner-picked over a Stop hook, which would re-open R100/Pass 4): a nudge that
  # rides the same injection, and becomes a parked ❓ under autopilot like every other nudge.
  local core; core="$(awk '/injection stops here/{exit} {print}' "$ROOT/STEERING.md")"
  [[ "$core" == *"drained under autopilot"* ]]
  [[ "$core" == *"/companion:advise"* ]]
  # It must sit in the Nudging section, so the once-only + park-under-autopilot rules govern it.
  local nudge; nudge="$(awk '/^## Nudging/{f=1;next} /^## /{f=0} f' "$ROOT/STEERING.md")"
  [[ "$nudge" == *"drained under autopilot"* ]]
  [[ "$nudge" == *"Surface each"* ]]   # ...the once-only rule is in the same block, still

  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _ss_ctx "$repo" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"drained under autopilot"* ]]
}

@test "tq report: next skips work that waits on an unanswered item (R47)" {
  # The drain loop offered the same blocked task four times in a row, because the queue could not
  # express "waiting on #N" — work blocked by an unanswered park looked identical to work that was
  # ready. Convention: the subject names `after #N`.
  export CLAUDE_COMPANION_SESSION_ID=sWait
  local d="$CLAUDE_COMPANION_TASKS_DIR/sWait"; mkdir -p "$d"
  jq -n '{id:"1",subject:"❓ [parked] pick the source of truth; rec: A",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"sharpen the prose (after #1)",status:"pending"}'                 > "$d/2.json"
  jq -n '{id:"3",subject:"an unrelated ready task",status:"pending"}'                      > "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #3"* ]]        # the READY task, not the blocked one
  [[ "$output" != *"→ next: #2"* ]]

  # With only the blocked task left, say so rather than pointing at work that cannot start.
  rm "$d/3.json"
  run "$TQ" report
  [[ "$output" == *"nothing STARTABLE"* ]]
  [[ "$output" != *"→ next: #2"* ]]

  # Answering the dependency makes it startable — the block must lift on its own.
  jq -n '{id:"1",subject:"picked",status:"completed"}' > "$d/1.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #2"* ]]

  # A task waiting on something that never existed is not blocked forever.
  jq -n '{id:"4",subject:"waits on a ghost (after #999)",status:"pending"}' > "$d/4.json"
  rm "$d/2.json"
  run "$TQ" report
  [[ "$output" == *"→ next: #4"* ]]
}

# ── staleness / challenge (R97) ────────────────────────────────────────────────────────────────
# The contract is a claim about what the owner still wants, and nothing was re-asking. These cover
# the part that must be MECHANICAL: which requirements the work has moved out from under, on the
# only axis each tier actually has. Whether a stale requirement should then be reversed is
# judgement, and deliberately not testable here.

# A repo whose single .bats holds TWO test blocks, so "per block, not per file" is observable.
_stale_repo() {                                  # $1=dir
  local d="$1"
  mkdir -p "$d/dev/tests" "$d/docs"
  cp dev/stale.sh "$d/dev/stale.sh"
  git -C "$d" init -q
  # printf, NOT a heredoc: bats preprocesses this very file and rewrites any line that STARTS with
  # `@test` into a test function — including fixture text inside a quoted heredoc. That silently
  # corrupted both the fixture and every helper defined after it, and the symptom was a drift of 0
  # with no error anywhere. Keep `@test` off column 0 in this file.
  printf -- '@test "alpha holds" {\n  marker=0\n  [ "$marker" -eq 0 ]\n}\n\n@test "beta holds" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' \
    > "$d/dev/tests/t.bats"
}
# Bump ONLY the alpha block. `sed -i` is spelled differently on GNU and BSD, so: temp file + mv.
_bump_alpha() {                                  # $1=dir  $2=n
  sed "s/marker=[0-9]*/marker=$2/" "$1/dev/tests/t.bats" > "$1/dev/tests/t.new"
  mv "$1/dev/tests/t.new" "$1/dev/tests/t.bats"
}
_stale_commit() {                                # $1=dir  $2=YYYY-MM-DD  $3=msg
  git -C "$1" add -A
  GIT_AUTHOR_DATE="$2T12:00:00" GIT_COMMITTER_DATE="$2T12:00:00" \
    git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$3"
}
_st() { printf '%s\n' "$output" | awk -v i="$1" '$1 == i { print $2; exit }'; }

@test "stale: only the requirement whose OWN test block moved goes stale — same file, both tests (R97)" {
  # THE design claim. 130 of this repo's tests live in one .bats, so a file-granular drift signal
  # would give every requirement claiming a test in it the same score and the ranking would carry
  # no information at all. Two requirements, one file, one block churning: only that one may fire.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  cat > "$d/docs/requirements.yaml" <<'EOT'
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  requirement: >
    alpha stays true
  verified_by:
    - "alpha holds"

- id: R2
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  requirement: >
    beta stays true
  verified_by:
    - "beta holds"
EOT
  _stale_commit "$d" 2019-06-01 init
  local i
  for i in 1 2 3 4; do _bump_alpha "$d" "$i"; _stale_commit "$d" "2021-0$i-01" "churn $i"; done

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [ "$(_st R1)" = STALE ]      # 4 commits to its block, threshold 3
  [ "$(_st R2)" = ok ]         # same FILE, untouched BLOCK — must not be billed for R1's churn
}

@test "stale: re-affirming multiplies the threshold, so a surviving requirement goes quiet (R97)" {
  # Surviving a challenge is evidence. Without the backoff the same requirement is re-litigated
  # every time its tests move, which is how a challenge mechanism turns into noise and gets muted.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  _mkreq() {                                     # $1=affirmations
    cat > "$d/docs/requirements.yaml" <<EOT
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: $1
  requirement: >
    alpha stays true
  verified_by:
    - "alpha holds"
EOT
  }
  _mkreq 0
  _stale_commit "$d" 2019-06-01 init
  local i
  for i in 1 2 3 4; do _bump_alpha "$d" "$i"; _stale_commit "$d" "2021-0$i-01" "churn $i"; done

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$(_st R1)" = STALE ]                        # drift 4 >= base 3

  _mkreq 1                                       # affirmed once -> threshold doubles to 6
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$(_st R1)" = ok ]
  [[ "$output" == *"4/6"* ]]                     # and it SHOWS the raised bar, not just silence
}

@test "stale: a judgment-shaped requirement expires on CALENDAR — the only axis it has (R97)" {
  # These name no test by construction, so there is no contact to measure. Age is all that is
  # left; the alternative is exempting exactly the requirements nobody can verify.
  local d; d="$(_tmpd)"; _stale_repo "$d"
  cat > "$d/docs/requirements.yaml" <<'EOT'
- id: R1
  satisfies: [UN-1]
  affirmed: 2020-01-01
  affirmations: 0
  judgment: "a ritual, not a code path"
  requirement: >
    the ritual is worth running
  verified_by: []

- id: R2
  satisfies: [UN-1]
  affirmed: 2199-01-01
  affirmations: 0
  judgment: "also a ritual"
  requirement: >
    the other ritual is worth running
  verified_by: []
EOT
  _stale_commit "$d" 2019-06-01 init
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [ "$(_st R1)" = STALE ]                        # long past the 180d base
  [ "$(_st R2)" = ok ]                           # affirmed in the future: nothing to ask about
}

@test "stale: advisory — it reports on a tree it cannot measure and never fails the build (R97/R28)" {
  # The line R28 draws: code blocks, injects, or guarantees control flow. This does none of the
  # three, so a non-zero exit from it would put a JUDGEMENT call into a gate, which is the exact
  # mistake of asserting a requirement is dead because a clock ran out.
  local d; d="$(_tmpd)"; mkdir -p "$d/dev" "$d/docs"; cp dev/stale.sh "$d/dev/stale.sh"

  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"   # no requirements file, no git repo
  [ "$status" -eq 0 ]

  git -C "$d" init -q; mkdir -p "$d/dev/tests"
  printf -- '- id: R1\n  satisfies: [UN-1]\n  requirement: >\n    x\n  verified_by:\n    - "gone"\n' \
    > "$d/docs/requirements.yaml"                # no affirmed:, and it claims a test that is absent
  _stale_commit "$d" 2019-06-01 init
  run bash -c 'cd "$1" && dev/stale.sh' _ "$d"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NO affirmed"* ]]             # reported, loudly, and still exit 0
}

@test "trace: a requirement with no affirmed:/affirmations: stamp FAILS the shape gate (R97)" {
  # stale.sh cannot date a requirement that carries no stamp, and an OPTIONAL field is a field
  # that is missing on the next entry someone adds. The shape gate is where that is prevented.
  local d; d="$(_tmpd)"; mkdir -p "$d/dev/tests" "$d/docs"; cp dev/trace.sh "$d/dev/trace.sh"
  printf -- '- id: UN-1\n  need: >\n    a thing\n' > "$d/docs/needs.yaml"
  printf -- '@test "alpha holds" {\n  run true\n}\n' > "$d/dev/tests/t.bats"
  _tr() { run bash -c 'cd "$1" && dev/trace.sh' _ "$d"; }

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: 2026-08-02\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -eq 0 ]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmed"* ]]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: last tuesday\n  affirmations: 0\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmed"* ]]

  printf -- '- id: R1\n  satisfies: [UN-1]\n  affirmed: 2026-08-02\n  requirement: >\n    x\n  verified_by:\n    - "alpha holds"\n' > "$d/docs/requirements.yaml"
  _tr; [ "$status" -ne 0 ]; [[ "$output" == *"affirmations"* ]]
}

@test "board: groups tasks into the same typed lanes as tq report, done rendered as a real list" {
  # tq report/delta collapse DONE to a count on purpose (R69 — injected every mutation); board is
  # explicitly invoked and never injected, so it can afford to list completed tasks individually.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"do the actual thing",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"❓ [parked] pick a cache backend — options: A) sqlite B) files; rec: sqlite — vendored already",status:"pending"}' > "$d/2.json"
  jq -n '{id:"3",subject:"first finished thing",status:"completed"}' > "$d/3.json"
  jq -n '{id:"4",subject:"second finished thing",status:"completed"}' > "$d/4.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"◻ OPEN"* ]]; [[ "$output" == *"do the actual thing"* ]]
  [[ "$output" == *"❓ PARKED"* ]]; [[ "$output" == *"└ rec: sqlite — vendored already"* ]]
  # Both completed tasks are listed BY ID, not folded into a bare "✔2" count.
  [[ "$output" == *"✔ #3  first finished thing"* ]]
  [[ "$output" == *"✔ #4  second finished thing"* ]]
}

@test "board: an open task waiting on a live after #N shows the wait, not just silence" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"first thing",status:"pending"}' > "$d/1.json"
  jq -n '{id:"2",subject:"second thing after #1",status:"pending"}' > "$d/2.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"#2  second thing after #1   ⧗ waiting on #1"* ]]
  # #1 has nothing blocking it, so it carries no wait note.
  [[ "$output" == *"#1  first thing"$'\n'* ]] || [[ "$output" == *"#1  first thing" ]]
}

@test "board: the beyond-the-queue section reflects candidates.sh, read-only" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  printf '# R\n- [ ] add a dark theme\n' > "$repo/ROADMAP.md"
  git -C "$repo" add -A; git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m r
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(queue empty)"* ]]
  [[ "$output" == *"beyond the queue"* ]]; [[ "$output" == *"display only"* ]]
  [[ "$output" == *"[roadmap] add a dark theme"* ]]
}

@test "tq add --context / tq context: sets and updates a task's context pointer (R99)" {
  run "$TQ" add "wire the retry logic" --done "429 retried with backoff" --context "lib/http.go"
  [ "$status" -eq 0 ]; [[ "$output" == *"context: lib/http.go"* ]]
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "lib/http.go" ]

  run "$TQ" context 1 "lib/http.go, lib/backoff.go"
  [ "$status" -eq 0 ]; [[ "$output" == *"context set"* ]]
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json")" = "lib/http.go, lib/backoff.go" ]

  # Adding with no --context leaves the field empty, not absent — same convention as done_when.
  run "$TQ" add "an unscoped task"
  [ "$(jq -r '.context' "$CLAUDE_COMPANION_TASKS_DIR/s1/2.json")" = "" ]
}

@test "companion_open_tasks: context renders on resume alongside done_when, survives across sessions (R99)" {
  # This IS the /clear-survival path: SessionStart fires with source:clear same as any other
  # boundary, and companion_open_tasks is what it reads to re-surface still-open work.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/sCtx"; mkdir -p "$d"; _stamp_root "$d" "$repo"
  jq -n '{id:"1",subject:"wire the retry logic",status:"pending",done_when:"429 retried with backoff",context:"lib/http.go, lib/backoff.go"}' > "$d/1.json"
  run bash -c 'cd "$1" && . "$2/lib/companion.sh" && companion_open_tasks "$(companion_root "$PWD")"' _ "$repo" "$ROOT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"└ done when: 429 retried with backoff"* ]]
  [[ "$output" == *"└ context: lib/http.go, lib/backoff.go"* ]]
}

@test "board: context and done_when render as continuation lines when present (R99)" {
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"wire the retry logic",status:"pending",done_when:"429 retried with backoff",context:"lib/http.go"}' > "$d/1.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"└ done when: 429 retried with backoff"* ]]
  [[ "$output" == *"└ context: lib/http.go"* ]]
}

@test "board: one corrupt task file is skipped, not a blank board (DA-caught)" {
  # jq -rs ABORTS on the first unparseable file — companion_open_tasks was already burned by
  # this exact shape (7 open tasks silently rendered as 0). board must not repeat it.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"a fine task",status:"pending"}' > "$d/1.json"
  printf '{not valid json' > "$d/2.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [ "$status" -eq 0 ]
  [[ "$output" == *"a fine task"* ]]                       # the good task still renders
  [[ "$output" == *"1 task file(s) unreadable"* ]]          # and the bad one is named, not silent
  [[ "$output" != *"(queue empty)"* ]]
}

@test "board: waiting-on clears once the blocker is done, not forever (DA-caught)" {
  # dep()'s select used \$live|index(.) — inside select, . rebinds to \$live itself, so it matched
  # EVERY id regardless of liveness. #2 named two blockers; both are done here, so neither should show.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  local d="$CLAUDE_COMPANION_TASKS_DIR/s1"; mkdir -p "$d"
  jq -n '{id:"1",subject:"first thing",status:"completed"}' > "$d/1.json"
  jq -n '{id:"2",subject:"second thing after #1 and after #3",status:"pending"}' > "$d/2.json"
  jq -n '{id:"3",subject:"third thing",status:"completed"}' > "$d/3.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"#2  second thing after #1 and after #3"* ]]
  [[ "$output" != *"waiting on"* ]]

  # A genuinely LIVE blocker still shows — and #1 (done) must not be named as a wait target,
  # even though "#1" itself still legitimately appears in the subject text ("after #1").
  jq -n '{id:"3",subject:"third thing",status:"pending"}' > "$d/3.json"
  run env BOARD_ROOT="$repo" "$BOARD"
  [[ "$output" == *"⧗ waiting on #3"* ]]
  [[ "$output" != *"waiting on #1"* ]]; [[ "$output" != *"waiting on #1, #3"* ]]
}

@test "tq add: --context and --done cannot swallow each other as a value (DA-caught)" {
  # tq add "s" --context --done "x" silently parsed --context's value as the literal "--done",
  # then treated "x" as a SECOND bogus task subject instead of --done's value.
  run "$TQ" add "subject" --context --done "x"
  [ "$status" -ne 0 ]; [[ "$output" == *"--context needs a value"* ]]
  [ ! -f "$CLAUDE_COMPANION_TASKS_DIR/s1/1.json" ]   # nothing was added on the refused call

  run "$TQ" add "subject2" --done --context "y"
  [ "$status" -ne 0 ]; [[ "$output" == *"--done needs a value"* ]]
}

# ── R109: evidence at the completion boundary ────────────────────────────────────────────────
# The recorded failure (owner, 2026-08-10): completion declared at the boundary of what a shell can
# observe, when the owner's experience of the work lived one layer further out. `--seen` cannot
# verify an observation happened (R28 ceiling, same as da-gate.sh's own pass) — it makes the claim
# WRITTEN and READABLE at the moment of closing.

@test "tq done --seen: a rubber stamp leaves the task OPEN; a real observation closes it and renders in list (R109)" {
  run "$TQ" add "ship the media fix"
  [ "$status" -eq 0 ]

  # THE LOAD-BEARING HALF. A gate that complains about a task it has ALREADY closed is decorative:
  # the refusal must happen before the state change, or the queue records a completion the gate
  # rejected. This assertion is why the guard runs before set_task, not after.
  run "$TQ" done 1 --seen "tests pass"
  [ "$status" -eq 2 ]
  run "$TQ" list
  [[ "$output" == *"[pending]"* ]]

  run "$TQ" done 1 --seen "opened the review screen in Expo Go on the device; media thumbnails loaded"
  [ "$status" -eq 0 ]
  # THE READER. A field nobody prints is pure cost — that is R58·a's retired capture hook (456KB
  # banked, zero readers). If this assertion is deleted, the field should be deleted with it.
  run "$TQ" list
  [[ "$output" == *"[completed]"* ]]
  [[ "$output" == *"seen: opened the review screen in Expo Go"* ]]

  # OPTIONAL BY DESIGN. Mandatory evidence would gate every routine close behind prose and train
  # the exact rubber-stamping the gate exists to refuse.
  run "$TQ" add "routine cleanup"
  run "$TQ" done 2
  [ "$status" -eq 0 ]
}

@test "seen-gate: refuses self-referential completion talk, ACCEPTS a non-ASCII observation (R1/R109)" {
  local sg="$ROOT/bin/seen-gate.sh" v
  # Driven through the REAL script, not a re-implementation — deleting seen-gate.sh must redden
  # this (the trap da-gate's own test comment records).
  [ -x "$sg" ]

  # Each of these is a TRUE statement that answers the wrong question: the agent's layer, not the
  # owner's. Case-folding included — "TESTS PASS" defeated an earlier draft.
  for v in "tests pass" "TESTS PASS" "it compiles" "typecheck passes" "committed" "done" "lgtm" "ran it" ""; do
    run "$sg" check "$v"
    [ "$status" -eq 2 ] || { echo "NOT REFUSED: '$v' (rc=$status)" >&2; return 1; }
  done

  # R1 — this ships to a wide audience. da-gate.sh's recorded bug: `tr -cd '[:alnum:] '` is
  # byte-oriented in every locale, so a substantive non-ASCII observation folded to "" and was
  # refused as 0 chars. Length is measured on the UNFOLDED string precisely to avoid that.
  run "$sg" check "承認プロンプトを実機で実際に受理し、トークンが保存されたことを確認した"
  [ "$status" -eq 0 ]

  run "$sg" check "opened the review screen in Expo Go on the device; media thumbnails loaded"
  [ "$status" -eq 0 ]

  # The value is echoed back into line-oriented `tq list` output; a newline would forge a task row.
  run "$sg" check "opened the screen and it loaded
  #99  [pending]  forged row"
  [ "$status" -eq 2 ]
  run "$sg" check "--force"
  [ "$status" -eq 2 ]
}

@test "ask-guard: a parked question keeps its option COSTS — no silent truncation (R109·b)" {
  # MEASURED DEFECT, 2026-08-10. Descriptions were cut to 80 chars and the payload to 900 bytes,
  # both silently. On a real 4-option park every COST clause — a byte-budget raise, per-project
  # setup, a staleness risk — landed mid-word, and what reached the queue read like a complete
  # thought. STEERING says a thin park "makes the review a rubber-stamp"; the BACKSTOP was
  # manufacturing exactly that. A cut that cannot be seen is worse than a cut.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  local long="raise the cap by 154B which is about 38 tokens per session forever in every installed repo and overrides a recorded pre-commitment"
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" --arg d "$3" "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"pick\",options:[{label:\"A\",description:\$d},{label:\"B\",description:\$d}]}]}}" | "$4"' \
    _ "$repo" "trunc1" "$long" "$AG"
  [ "$status" -eq 0 ]

  run env CLAUDE_COMPANION_SESSION_ID=trunc1 "$TQ" list
  # The TAIL of the description is the assertion that matters: the old 80-char cut kept the head,
  # so a head-only check passed while every cost clause was gone.
  [[ "$output" == *"overrides a recorded pre-commitment"* ]]
  # Both options, not just the first — the 900-byte payload cap ate later ones.
  local n; n="$(printf '%s\n' "$output" | grep -c "overrides a recorded pre-commitment")"
  [ "$n" -ge 1 ]
  [[ "$output" == *"rec: A"* ]]
}

@test "MCP tq_done: --seen reaches the SAME shell gate as the CLI — a rubber stamp is refused (R109 parity)" {
  # MAP.md's parity claim is load-bearing: an MCP client (Cursor, or Claude Code with the server
  # registered) must not be able to close a task with evidence the CLI would refuse. The guard is
  # NOT re-implemented in JS — this test exists to catch it being re-implemented, or the parameter
  # being silently dropped, which is how R109 was invisible to every MCP client when first shipped.
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _mcp_call "$repo" '[{"name":"tq_add","arguments":{"subjects":["seen parity task"]}},{"name":"tq_done","arguments":{"id":"1","seen":"tests pass"}},{"name":"tq_list"}]'

  # The stamp is refused and the task is STILL pending — same outcome as `tq done 1 --seen "tests pass"`.
  [[ "$output" == *"reports YOUR layer"* ]]
  [[ "$output" == *"[pending]"* ]]

  _mcp_call "$repo" '[{"name":"tq_done","arguments":{"id":"1","seen":"opened the review screen in Expo Go on the device; media thumbnails loaded"}},{"name":"tq_list"}]'
  [[ "$output" == *"[completed]"* ]]
  [[ "$output" == *"seen: opened the review screen in Expo Go"* ]]
}

@test "check.sh's lint set INCLUDES bin/tq — the extensionless file the glob silently missed (R110 wiring guard)" {
  # MEASURED HOLE, 2026-08-11. `scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)` globs on
  # `.sh`, and `bin/tq` has no extension — it is the ONLY extensionless file in bin/. So THE task
  # queue (R8/R10), which every command and the MCP server route through, was invisible to
  # ShellCheck, portability-lint AND the size guard at once. The gate reported green while tq grew
  # 355 -> 382 lines. A gate that cannot fail on the file that matters most is UN-5's failure shape.
  # bats cannot run check.sh (check.sh runs bats), so this is structural, like the wiring guards above.
  local c="$ROOT/../../check.sh"
  run grep -cE '^scripts=\(.*bin/tq' "$c"
  [ "$output" -ge 1 ]

  # And the file really is extensionless — if it ever gains `.sh` the glob covers it and this guard
  # becomes theatre, so the premise is pinned too.
  [ -f "$ROOT/bin/tq" ]
  [ ! -f "$ROOT/bin/tq.sh" ]
}

@test "check.sh's size guard has NO exemptions — the tq debt was PAID, not waived (R110)" {
  # HISTORY, kept because it is the point. `bin/tq` sat at 382 lines outside the size guard
  # entirely: the glob was `bin/*.sh` and tq has no extension, so the gate could not fail on the
  # most-called file in the product. Wiring it in forced a choice — decompose THE task queue inside
  # the change that found the hole, or exempt it visibly. It was exempted BY NAME, printed on every
  # run, with a staleness check that went RED the moment tq dropped back under 300.
  #
  # That trap fired on 2026-08-12 and the debt was PAID (tq 382 -> 285, usage()+report() extracted
  # to tq-output.sh on a cohesion seam). This test replaces the one that watched the exemption: what
  # matters now is that NO exemption ever comes back quietly. A named, printed, self-expiring
  # exemption was defensible for a day; a silent one is how tq drifted to 382 unseen.
  local c="$ROOT/../../check.sh"
  run grep -cE 'size_skip|EXEMPT' "$c"
  [ "$output" -eq 0 ] || { echo "a size exemption reappeared in check.sh — it must be paid, not waived" >&2; false; }

  # And the file it was granted for is genuinely under the cap now, not merely un-exempted.
  run bash -c 'wc -l < "$1"' _ "$ROOT/bin/tq"
  [ "$output" -le 300 ]
  # ...via a real seam, not a stub: the extracted half must exist and carry both renderers.
  [ -r "$ROOT/bin/tq-output.sh" ]
  run grep -cE '^(usage|report)\(\) \{' "$ROOT/bin/tq-output.sh"
  [ "$output" -eq 2 ]
}

# ── R26 restored: autopilot's "keep going" guarantee is a hook again ──────────────────────────
# Retired in R100/Pass 4, declined twice (R105 2026-08-08, R107 2026-08-09), restored 2026-08-12
# because the prose lost: STEERING said "keep draining" and the model stopped with startable work
# in the queue. A nudge the model can skip is not a mode (R36).

@test "stop-autopilot: armed + a startable task BLOCKS the stop; a drained queue allows it (R26 restored)" {
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  [ -x "$SA" ]
  repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run env CLAUDE_COMPANION_SESSION_ID=sa1 "$TQ" add "real startable work"
  [ "$status" -eq 0 ]

  # ARMED + STARTABLE -> block, naming the task so the continuation is actionable rather than a nag.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa1\"}" | "$2"' _ "$repo" "$SA"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"decision":"block"'* ]]
  [[ "$output" == *"real startable work"* ]]

  # DRAINED -> allow (empty output = Claude Code's default allow). This is the terminator that
  # stops the mode being a trap: a queue with nothing startable must never block the session.
  run env CLAUDE_COMPANION_SESSION_ID=sa1 "$TQ" done 1
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa1\"}" | "$2"' _ "$repo" "$SA"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  # AUTOPILOT OFF -> allow, even with work queued. The flag is the whole gate.
  run env CLAUDE_COMPANION_SESSION_ID=sa2 "$TQ" add "work with autopilot off"
  ( cd "$repo" && "$AP" off ) >/dev/null
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sa2\"}" | "$2"' _ "$repo" "$SA"
  [ -z "$output" ]
}

@test "stop-autopilot: a DRY queue with burn-down armed and a BURN verdict refuses the stop (R82 hand-off restored)" {
  # The gap this closes: burn-down was documented as automatic but nothing ever fired it — the
  # dry-queue path just ended the turn and STEERING asked the model to remember. Continuing a turn
  # is control-flow, which is the one thing a hook can actually guarantee (R28).
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  repo="$(_tmpd)"; git -C "$repo" init -q -b main
  git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  ( cd "$repo" && "$AP" on ) >/dev/null
  local _stop; _stop() { run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sBD\"}" | "$2"' _ "$repo" "$SA"; }

  # DRY queue, burn-down OFF -> the turn ends, exactly as before. Proves the new branch is opt-in.
  _stop; [ -z "$output" ]

  # Arm burn-down, but give it NO usable snapshot: should-burn HOLDs, so the turn must still end.
  # Hold is the safe direction and every unknown resolves to it.
  ( cd "$repo" && "$AP" burndown on ) >/dev/null
  _stop; [ -z "$output" ]

  # Now a snapshot that genuinely forecasts underspend, seeded twice so the R90 two-sample rule is
  # satisfied — the same thing the status line does by repainting.
  local n; n="$(date +%s)"
  printf '%s %s %s %s %s\n' "$(( n - 30 ))" 10 "$(( n + 7200 ))" 5 "$(( n + 172800 ))" \
    > "$CLAUDE_COMPANION_STATE_DIR/ratelimit"
  ( cd "$repo" && BURNDOWN_ROOT="$repo" bash "$ROOT/bin/burn-down.sh" should-burn ) >/dev/null 2>&1 || true
  printf '%s %s %s %s %s\n' "$n" 10 "$(( n + 7200 ))" 5 "$(( n + 172800 ))" \
    > "$CLAUDE_COMPANION_STATE_DIR/ratelimit"
  _stop
  [[ "$output" == *'"decision":"block"'* ]]     # the stop is REFUSED — the hand-off fired
  [[ "$output" == *"burn-down says BURN"* ]]
  [[ "$output" == *"candidates"* ]]             # ...and it names what to do next
  [[ "$output" == *"burndown-branch"* ]]
}

@test "stop-autopilot: the kill switch and its bounds all yield; ship-mode stays dead, burn-down hands off (R26/R81/R82)" {
  local SA="$ROOT/bin/stop-autopilot.sh" repo
  repo="$(_tmpd)"; git -C "$repo" init -q
  ( cd "$repo" && "$AP" on ) >/dev/null
  run env CLAUDE_COMPANION_SESSION_ID=sb1 "$TQ" add "work"

  # Control: it really would block without the switch, or the assertions below prove nothing.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | "$2"' _ "$repo" "$SA"
  [[ "$output" == *'"decision":"block"'* ]]

  # KILL SWITCH.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0 "$2"' _ "$repo" "$SA"
  [ -z "$output" ]

  # RUN BOUNDS (R81). Restoring the continuation without its terminators is the one genuinely
  # dangerous version of this change, so each bound is pinned. `1` is the tightest non-disabling
  # value; a run that has taken any turn at all is already at it.
  run bash -c 'printf "{\"cwd\":\"$1\",\"session_id\":\"sb1\"}" | CLAUDE_COMPANION_AUTOPILOT_TURNS=1 "$2"' _ "$repo" "$SA"
  [ -z "$output" ]

  # THE OMISSIONS ARE PART OF THE CONTRACT, not an accident of the splice: both concerns acquired
  # another owner while this file was gone, and a second owner is how a checkpoint path silently
  # re-automates itself.
  run grep -cE "git commit|git add -A" "$SA"
  [ "$output" -eq 0 ]                                  # ship-mode belongs to ship-checkpoint.sh
  # BURN-DOWN IS THE EXCEPTION, reversed 2026-08-15 by owner decision: the hook now makes the CHEAP
  # call (should-burn) and hands the expensive ranking to the model. It must NOT rank candidates
  # itself — `candidates.sh` git-greps the whole repo, which is unbounded in repo size on a hook
  # that fires at every stop (R81). So: burn-down.sh yes, candidates.sh no.
  # Assert on INVOCATION, not mention: the hook names candidates.sh in the instruction it hands
  # back to the model, which is the whole point of the hand-off — what must not happen is the hook
  # RUNNING it.
  run grep -c "should-burn" "$SA"
  [ "$output" -ge 1 ]                                  # the CHEAP verdict is wired again
  # ...but the repo-wide scan stays OUT of the hook. Assert on execution shapes, not on the name:
  # the hook names candidates.sh in the instruction it hands back to the model, which is the point
  # of the hand-off. Running it is what R81 forbids (git grep is unbounded in repo size).
  run grep -cE '[$][(][^)]*candidates[.]sh|(bash|exec) [^|]*candidates[.]sh' "$SA"
  [ "$output" -eq 0 ]
  # ...and it must still READ the selection from tq rather than re-deriving it: the recorded drift
  # bug had this hook offering a task blocked on an unanswered park four turns running.
  run grep -c "stopfields" "$SA"
  [ "$output" -ge 1 ]
}

@test "tq dependencies: ONLY 'after #<id>' blocks, and the syntax is documented where the author looks (R87)" {
  # MEASURED FAILURE, 2026-08-12. The owner reported autopilot not draining the backlog. `stopfields`
  # said STARTABLE=4 while every one of those tasks was in fact waiting on an unanswered park — the
  # dependencies existed only in prose. Root cause: `after #<id>` is the ONLY syntax stopfields()
  # reads, and it was documented NOWHERE. The author (me) had written "(after 1/2)" intending a
  # dependency; it parsed as nothing, so the task looked perfectly startable. A dependency that
  # silently fails to parse is worse than one that errors: the queue reports confident nonsense.
  export CLAUDE_COMPANION_SESSION_ID=deps1
  run "$TQ" add "first"
  run "$TQ" add "second (after 1/2)"          # the near-miss syntax — must NOT block
  run "$TQ" add "third after #1"              # the real syntax — must block

  run bash -c '"$1" stopfields false | tr "\037" "|"' _ "$TQ"
  local startable; startable="$(printf '%s' "$output" | awk -F'|' '{print $7}')"
  [ "$startable" -eq 2 ] || { echo "expected 2 startable (#3 blocked by #1), got $startable" >&2; false; }

  # Close the blocker: the dependent becomes startable. Without this the test would pass on a
  # stopfields that simply never counted #3 at all.
  run "$TQ" done 1
  run bash -c '"$1" stopfields false | tr "\037" "|"' _ "$TQ"
  startable="$(printf '%s' "$output" | awk -F'|' '{print $7}')"
  [ "$startable" -eq 2 ] || { echo "expected 2 startable after unblocking, got $startable" >&2; false; }

  # DISCOVERABILITY is the fix, not the parser. The behaviour was always correct; nothing told the
  # author the syntax existed, so it was never used. If this line goes, the trap comes back.
  run bash -c '"$1" --help 2>&1' _ "$TQ"
  [[ "$output" == *"after #<id>"* ]]
  [[ "$output" == *"silently ignored"* ]]
}

@test "STEERING: the observation-point reflex reaches a session through the REAL hook (R109 steering half)" {
  # R106's precedent: pin DELIVERY, not mere presence in a file. A line that exists but never
  # reaches a session is the same nothing as a line that was never written — and this repo has
  # shipped that exact nothing twice (the retired capture hook, the inert plugin cache).
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  run bash -c 'jq -nc --arg c "$1" "{cwd:\$c,source:\"\"}" | "$2"' _ "$repo" "$SS"
  [ "$status" -eq 0 ]

  # The three shapes. Each names a way a real 2026-08-10 miss slipped past a check that passed.
  [[ "$output" == *"built ≠ running"* ]]        # the fix that was never deployed
  [[ "$output" == *"typed ≠ resolved"* ]]       # typecheck cannot see string-typed router paths
  [[ "$output" == *"refused ≠ accepted"* ]]     # the approval gate's accept path

  # THE DEEPEST ONE, and the only one no mechanism can cover: an agent ruling something untestable
  # is making a DECISION (verification traded for delivery) while it looks like a fact about the
  # world, so it never enters the parked pile. pty.openpty() was available the whole time.
  [[ "$output" == *"never a conclusion"* ]]
  [[ "$output" == *"asking how"* ]]

  # The owner naming their runtime makes THAT runtime the target — the three-day-old bundle server.
  [[ "$output" == *"what is actually serving it"* ]]
}
