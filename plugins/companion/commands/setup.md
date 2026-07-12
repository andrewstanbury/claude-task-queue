---
description: Wire the companion status line into your settings.json (one-time)
---

Wire the companion's status line into the user's Claude Code settings so it renders in the
CLI. The status line shows: ⠋ animated beacon · 🛡 secret gate · model · ✈️ autopilot · ⇡ input
⇣ output tokens · 📋 open · ❓ parked · ⏳ blocked tasks · project · branch (+ *changes · ↑ahead
↓behind).

Do this:

1. Resolve the absolute path to the status line script: `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`
   (expand `${CLAUDE_PLUGIN_ROOT}` to its real value — the status line runs outside the hook
   environment, so the stored command must be an absolute path, not the variable).
2. Read the user's `~/.claude/settings.json` (create `{}` if absent).
3. Set `.statusLine` to `{ "type": "command", "command": "bash <ABSOLUTE_PATH>", "refreshInterval": 3 }`.
   If a `statusLine` already exists, show the current value and confirm before replacing it.
4. Write it back (valid JSON, preserving other keys). Confirm in one line that it's wired and
   will appear on the next render.

`refreshInterval: 3` (seconds, R32) — the beacon animates only when there's work in motion, so it
needs *a* timer, but not a per-second one: at 3s it still advances (nobody reads a spinner at 1 Hz)
while cutting the idle cost — the jq + `git status` wake — ~3× versus 1s. (A no-color terminal shows
a static ● and doesn't need the timer at all.)
