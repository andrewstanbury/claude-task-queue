#!/usr/bin/env bash
# hud-install — wire hud's status line into ~/.claude/settings.json, once.
#
# Claude Code can't auto-activate a plugin status line (it must live in
# settings.json), so this is the one manual step — run via /hud:setup. It writes a
# VERSION-RESILIENT command (always execs the newest installed hud), so it
# survives hud updates instead of pinning a version folder. Idempotent; preserves
# every other setting (jq merge). Override the target with CLAUDE_SETTINGS.

set -uo pipefail

settings="${CLAUDE_SETTINGS:-$HOME/.claude/settings.json}"

# Self-resolving: pick the highest-version installed hud-status.sh at run time.
cmd="bash -c 'exec \"\$(ls -d ~/.claude/plugins/cache/andrewstanbury/hud/*/bin/hud-status.sh 2>/dev/null | sort -V | tail -1)\"'"

mkdir -p "$(dirname "$settings")" 2>/dev/null || true
[ -s "$settings" ] || printf '{}\n' > "$settings"

# refreshInterval=1 (second): hud's beacon is an animated spinner, so it needs a timer
# to advance one frame per second. This wakes jq+git once a second on idle — a battery
# trade the owner opted into for a live status line. (jq numbers are unquoted → real 1.)
tmp="$(mktemp)"
if jq --arg c "$cmd" \
     '.statusLine = {type: "command", command: $c, refreshInterval: 1}' \
     "$settings" > "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
  mv "$tmp" "$settings"
  printf 'hud: status line wired into %s (version-resilient — survives hud updates).\n' "$settings"
  printf 'Restart Claude Code (or wait for the next status-line refresh) to see it.\n'
else
  rm -f "$tmp"
  printf 'hud: could not update %s (not valid JSON?). Add this statusLine manually:\n' "$settings" >&2
  printf '  "statusLine": { "type": "command", "command": %s }\n' "$(printf '%s' "$cmd" | jq -Rs .)" >&2
  exit 1
fi
