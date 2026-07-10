#!/usr/bin/env bash
# charter — MCP reachability probe (SessionStart support lib).
#
# Reads the MCP servers DECLARED for this project (read-only) and checks each is
# actually reachable, so a non-technical owner is warned when a configured tool
# silently won't be available this session — the failure mode where MCP tools
# just don't appear and nobody notices. Best-effort & bounded: every probe has a
# hard per-server timeout, all run in parallel, and any internal error degrades
# to silence (it must never delay or break session start).
#
# Catches the common silent failures:
#   • stdio server whose command/package is missing or won't start (broken install)
#   • remote (http/sse) server whose endpoint is unreachable / DNS-dead
# Deliberately NOT treated as "down": an HTTP auth challenge (401/403) — the
# endpoint IS reachable; missing credentials are the owner's separate concern, and
# treating it as down would false-alarm every interactively-authed server.

set -uo pipefail

mcp_have() { command -v "$1" >/dev/null 2>&1; }

# Run a command under a hard wall-clock bound, portably. Prefers GNU `timeout`
# (Linux), then `gtimeout` (Homebrew coreutils), and falls back to perl's alarm —
# present on stock macOS, which ships NEITHER `timeout` nor `gtimeout` — so the probe
# still BOUNDS the spawn there instead of skipping the health check entirely. The perl
# form leaves a pending SIGALRM across exec (default disposition terminates), which is
# the classic portable timeout. Returns 127 when no mechanism exists.
mcp_bounded() {  # mcp_bounded SECONDS cmd...
  local t="$1"; shift
  if   mcp_have timeout;  then timeout  -k 1 "$t" "$@"
  elif mcp_have gtimeout; then gtimeout -k 1 "$t" "$@"
  elif mcp_have perl;     then perl -e 'my $t=shift; alarm $t; exec @ARGV or exit 127' "$t" "$@"
  else return 127; fi
}
mcp_can_bound() { mcp_have timeout || mcp_have gtimeout || mcp_have perl; }

# The MCP `initialize` request every probe sends — a minimal valid JSON-RPC
# handshake. A server that answers it (result OR error) is speaking the protocol.
MCP_INIT_REQ='{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"charter-mcp-probe","version":"1"}}}'

# Merge .mcpServers from every place Claude Code reads them, for THIS repo:
#   ~/.claude.json   (global .mcpServers + this project's project-scoped block)
#   <root>/.mcp.json (the committed project file)
#   <root>/.claude/settings.json + settings.local.json
# Prints a compact JSON object {name: serverConfig}; "{}" when none.
mcp_discover() {
  local root="$1" home_cfg="${CLAUDE_MCP_HOME_CONFIG:-$HOME/.claude.json}"
  local files=() merged
  [ -f "$home_cfg" ] && files+=("$home_cfg")
  [ -f "$root/.mcp.json" ] && files+=("$root/.mcp.json")
  [ -f "$root/.claude/settings.json" ] && files+=("$root/.claude/settings.json")
  [ -f "$root/.claude/settings.local.json" ] && files+=("$root/.claude/settings.local.json")
  [ "${#files[@]}" -gt 0 ] || { printf '{}'; return 0; }
  merged="$(jq -s --arg root "$root" '
      reduce .[] as $f ({};
        . + (($f.mcpServers) // {})
          + (($f.projects[$root].mcpServers) // {}))
    ' "${files[@]}" 2>/dev/null)" || merged=""
  [ -n "$merged" ] && [ "$merged" != "null" ] || merged="{}"
  printf '%s' "$merged"
}

# Probe ONE stdio server. Spawns it, sends the initialize handshake, and reads the
# reply under a hard timeout. Prints "<name>\t<reason>" if DOWN, nothing if up.
# Skipped silently when no bounded-run mechanism (timeout/gtimeout/perl) exists —
# spawning a server unbounded at session start could hang the turn, which is worse
# than a missed warning.
mcp_probe_stdio() {
  local name="$1" cfg="$2" t="$3" cmd out
  cmd="$(printf '%s' "$cfg" | jq -r '.command // empty' 2>/dev/null)"
  [ -n "$cmd" ] || return 0          # malformed entry — don't false-warn
  mcp_can_bound || return 0
  local args=() envs=() runline=(env)
  while IFS= read -r a; do args+=("$a"); done \
    < <(printf '%s' "$cfg" | jq -r '.args[]? // empty' 2>/dev/null)
  while IFS= read -r e; do envs+=("$e"); done \
    < <(printf '%s' "$cfg" | jq -r '(.env // {}) | to_entries[] | "\(.key)=\(.value)"' 2>/dev/null)
  [ "${#envs[@]}" -gt 0 ] && runline+=("${envs[@]}")
  runline+=("$cmd")
  [ "${#args[@]}" -gt 0 ] && runline+=("${args[@]}")
  out="$(printf '%s\n' "$MCP_INIT_REQ" \
          | mcp_bounded "$t" "${runline[@]}" 2>/dev/null \
          | head -c 65536)" || true
  if printf '%s' "$out" | grep -q '"jsonrpc"' \
     && printf '%s' "$out" | grep -Eq '"(result|error)"'; then
    return 0                          # spoke MCP → reachable
  fi
  if ! mcp_have "$cmd" && [ ! -x "$cmd" ]; then
    printf '%s\tcommand not found: %s\n' "$name" "$cmd"
  else
    printf '%s\tno MCP response (server may be broken or mis-configured)\n' "$name"
  fi
}

# Probe ONE remote (http/sse) server. Any HTTP status = reachable (incl. 401/403);
# only a connection-level failure (curl code 000) is DOWN. Skipped when curl is
# absent. Prints "<name>\t<reason>" if DOWN.
mcp_probe_http() {
  local name="$1" cfg="$2" t="$3" url code hdrs=()
  url="$(printf '%s' "$cfg" | jq -r '.url // empty' 2>/dev/null)"
  [ -n "$url" ] || return 0
  mcp_have curl || return 0
  while IFS= read -r h; do hdrs+=(-H "$h"); done \
    < <(printf '%s' "$cfg" | jq -r '(.headers // {}) | to_entries[] | "\(.key): \(.value)"' 2>/dev/null)
  local curlargs=(-s -o /dev/null -w '%{http_code}' --max-time "$t" -X POST
                  -H 'content-type: application/json'
                  -H 'accept: application/json, text/event-stream')
  [ "${#hdrs[@]}" -gt 0 ] && curlargs+=("${hdrs[@]}")
  code="$(curl "${curlargs[@]}" -d "$MCP_INIT_REQ" "$url" 2>/dev/null)" || code="000"
  [ -n "$code" ] || code="000"
  [ "$code" = "000" ] && printf '%s\tunreachable: %s\n' "$name" "$url"
  return 0
}

# Route one server config to the right transport probe.
mcp_probe_one() {
  local name="$1" cfg="$2" t="${CLAUDE_CHARTER_MCP_TIMEOUT:-3}" type
  type="$(printf '%s' "$cfg" | jq -r '.type // (if .url then "http" else "stdio" end)' 2>/dev/null)"
  case "$type" in
    http|sse|streamable-http|ws) mcp_probe_http  "$name" "$cfg" "$t" ;;
    *)                           mcp_probe_stdio "$name" "$cfg" "$t" ;;
  esac
}

# Probe EVERY declared MCP server for <root>, in parallel, each hard-bounded.
# Prints "<name>\t<reason>" per DOWN server; silent when all up / none declared /
# disabled. Bounded to CLAUDE_CHARTER_MCP_MAX servers (default 25).
mcp_probe_all() {
  local root="$1"
  [ "${CLAUDE_CHARTER_MCP_PROBE:-1}" = "0" ] && return 0
  local servers names name cfg tmp pids=() max="${CLAUDE_CHARTER_MCP_MAX:-25}" i=0
  servers="$(mcp_discover "$root")"
  [ -n "$servers" ] && [ "$servers" != "{}" ] || return 0
  names="$(printf '%s' "$servers" | jq -r 'keys[]' 2>/dev/null)" || return 0
  [ -n "$names" ] || return 0
  tmp="$(mktemp -d 2>/dev/null)" || return 0
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    i=$((i + 1)); [ "$i" -gt "$max" ] && break
    cfg="$(printf '%s' "$servers" | jq -c --arg n "$name" '.[$n]' 2>/dev/null)"
    mcp_probe_one "$name" "$cfg" > "$tmp/$i" 2>/dev/null &
    pids+=("$!")
  done <<< "$names"
  [ "${#pids[@]}" -gt 0 ] && wait "${pids[@]}" 2>/dev/null
  cat "$tmp"/* 2>/dev/null
  rm -rf "$tmp" 2>/dev/null
}
