#!/usr/bin/env bash
# SessionStart hook — warn when a CONFIGURED MCP server won't actually work this
# session. Silent tool-unavailability is invisible to a non-technical owner (the
# tools just don't appear), so charter probes each declared server's reachability
# and surfaces the dead ones in plain language. Best-effort, bounded, non-blocking:
# probes only on a FRESH start (not every compact/resume — it spawns processes),
# self-disables when no servers are declared, and any error degrades to silence.
#
# Disable with CLAUDE_CHARTER_MCP_PROBE=0.

set -uo pipefail

# Missing jq → clean silent no-op (input parse + the final emit use jq; without it
# the hook would spray "jq: command not found" at every fresh session start).
command -v jq >/dev/null 2>&1 || exit 0

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/mcp-probe.sh
. "$PLUGIN_DIR/lib/mcp-probe.sh"
# shellcheck source=../lib/charter.sh
. "$PLUGIN_DIR/lib/charter.sh"

[ "${CLAUDE_CHARTER_MCP_PROBE:-1}" = "0" ] && exit 0

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; src=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Probe only on a fresh start — not on every compact/resume (it spawns servers).
case "$src" in compact | resume) exit 0 ;; esac

root="$(charter_root_for_cwd "$cwd")"
down="$(mcp_probe_all "$root" 2>/dev/null || true)"
[ -n "$down" ] || exit 0

list=""
while IFS=$'\t' read -r name reason; do
  [ -n "$name" ] || continue
  if [ -z "$list" ]; then list="• $name — $reason"; else list="$list"$'\n'"• $name — $reason"; fi
done <<< "$down"

msg="[charter] MCP check — these configured tool servers didn't respond at startup, so their tools may be silently unavailable this session:
$list
Tell the owner in plain language what's affected and that this is an environment/setup issue (not their project's code) — e.g. the tool isn't installed, or its config/credentials need attention — then carry on. Disable with CLAUDE_CHARTER_MCP_PROBE=0."

jq -cn --arg c "$msg" '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
exit 0
