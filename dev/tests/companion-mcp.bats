#!/usr/bin/env bats
#
# THE PORTABLE SURFACE - the MCP server tools and ship-checkpoint.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper


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
