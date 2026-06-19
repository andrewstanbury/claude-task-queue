#!/usr/bin/env bats
#
# Tests for charter's MCP reachability probe (SessionStart). Fakes MCP servers
# with tiny stub commands on PATH and a controlled config; bounded by a 1s
# per-server timeout so the suite stays fast.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  PROBE="$ROOT/bin/charter-mcp-probe.sh"
  # shellcheck source=../lib/mcp-probe.sh
  . "$ROOT/lib/mcp-probe.sh"

  TMP="$(mktemp -d)"
  REPO="$TMP/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  BIN="$TMP/bin"; mkdir -p "$BIN"; PATH="$BIN:$PATH"

  # Never touch the real ~/.claude.json during tests.
  export CLAUDE_MCP_HOME_CONFIG="$TMP/home.json"
  export CLAUDE_CHARTER_MCP_TIMEOUT=1

  # A healthy stdio server: answers the initialize handshake with a JSON-RPC result.
  cat > "$BIN/good-mcp" <<'EOF'
#!/usr/bin/env bash
read -r _ || true
printf '{"jsonrpc":"2.0","id":1,"result":{"protocolVersion":"x"}}\n'
EOF
  # A server that starts but never speaks MCP (times out).
  cat > "$BIN/hang-mcp" <<'EOF'
#!/usr/bin/env bash
sleep 5
EOF
  chmod +x "$BIN/good-mcp" "$BIN/hang-mcp"
}

teardown() { rm -rf "$TMP"; }

mcp_json() { printf '%s' "$1" > "$REPO/.mcp.json"; }

run_probe() {
  local src="${1:-startup}" json
  json="$(jq -nc --arg c "$REPO" --arg s "$src" '{cwd:$c, source:$s}')"
  printf '%s' "$json" | "$PROBE" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "silent when no MCP servers are declared" {
  run run_probe startup
  [ -z "$output" ]
}

@test "warns when a stdio server's command is missing (silent-unavailability)" {
  mcp_json '{"mcpServers":{"ghost":{"command":"definitely-not-a-real-cmd-xyz"}}}'
  run run_probe startup
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"command not found"* ]]
  [[ "$output" == *"silently unavailable"* ]]   # plain-language owner framing
}

@test "a healthy stdio server is NOT flagged" {
  mcp_json '{"mcpServers":{"fine":{"command":"good-mcp"}}}'
  run run_probe startup
  [ -z "$output" ]
}

@test "warns when a server starts but never speaks MCP (broken/mis-configured)" {
  mcp_json '{"mcpServers":{"stuck":{"command":"hang-mcp"}}}'
  run run_probe startup
  [[ "$output" == *"stuck"* ]]
  [[ "$output" == *"no MCP response"* ]]
}

@test "an unreachable http endpoint is flagged as down" {
  mcp_json '{"mcpServers":{"remote":{"type":"http","url":"http://127.0.0.1:1/mcp"}}}'
  run run_probe startup
  [[ "$output" == *"remote"* ]]
  [[ "$output" == *"unreachable"* ]]
}

@test "an HTTP auth challenge counts as reachable, NOT down" {
  # Stub curl to report a 401 (endpoint up, just needs creds) — must not warn.
  cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
echo 401
EOF
  chmod +x "$BIN/curl"
  run mcp_probe_http "authed" '{"url":"https://example.test/mcp"}' 1
  [ -z "$output" ]
}

@test "discovers servers from ~/.claude.json (project-scoped block)" {
  printf '%s' '{"projects":{"'"$REPO"'":{"mcpServers":{"home-srv":{"command":"definitely-not-a-real-cmd-xyz"}}}}}' \
    > "$CLAUDE_MCP_HOME_CONFIG"
  run run_probe startup
  [[ "$output" == *"home-srv"* ]]
}

@test "disabled with CLAUDE_CHARTER_MCP_PROBE=0 is silent even with a dead server" {
  mcp_json '{"mcpServers":{"ghost":{"command":"definitely-not-a-real-cmd-xyz"}}}'
  CLAUDE_CHARTER_MCP_PROBE=0 run run_probe startup
  [ -z "$output" ]
}

@test "does not probe on compact/resume (only a fresh start spawns servers)" {
  mcp_json '{"mcpServers":{"ghost":{"command":"definitely-not-a-real-cmd-xyz"}}}'
  run run_probe compact
  [ -z "$output" ]
  run run_probe resume
  [ -z "$output" ]
}

@test "discovery returns {} when nothing is declared" {
  run mcp_discover "$REPO"
  [ "$output" = "{}" ]
}
