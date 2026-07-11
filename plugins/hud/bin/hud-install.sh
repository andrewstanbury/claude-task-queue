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

# Self-resolving: pick the newest-installed hud-status.sh at run time. `ls -dt`
# orders by mtime (newest first) so an update always wins — no version parsing, and
# portable (sort -V is GNU-only; on macOS it collapses to empty and the line blanks).
cmd="bash -c 'exec \"\$(ls -dt ~/.claude/plugins/cache/andrewstanbury/hud/*/bin/hud-status.sh 2>/dev/null | head -1)\"'"

mkdir -p "$(dirname "$settings")" 2>/dev/null || true
[ -s "$settings" ] || printf '{}\n' > "$settings"

# NO refreshInterval: the beacon is a static ●, so nothing needs a sub-message timer, and
# Claude Code already repaints the status line event-driven (each message / after compact).
# Setting an interval only re-ran the whole bash+jq+git command on a clock — ~1800 idle
# wakeups/hour that spun handheld fans for no benefit. Omitting the key = event-driven only.
# Also strip any interval a PRIOR install wrote, so an upgrade actually removes it.
tmp="$(mktemp)"
if jq --arg c "$cmd" \
     '.statusLine = {type: "command", command: $c}' \
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
