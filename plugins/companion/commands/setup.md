---
description: Wire the companion status line into your settings.json (one-time)
---

Wire the companion's status line into the user's Claude Code settings so it renders in the
CLI. The status line shows: 🛡 secret gate · model · ⇡ input ⇣ output tokens · 📋 open tasks ·
project · branch (+ *changes).

Do this:

1. Resolve the absolute path to the status line script: `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`
   (expand `${CLAUDE_PLUGIN_ROOT}` to its real value — the status line runs outside the hook
   environment, so the stored command must be an absolute path, not the variable).
2. Read the user's `~/.claude/settings.json` (create `{}` if absent).
3. Set `.statusLine` to `{ "type": "command", "command": "bash <ABSOLUTE_PATH>" }`. If a
   `statusLine` already exists, show the current value and confirm before replacing it.
4. Write it back (valid JSON, preserving other keys). Confirm in one line that it's wired and
   will appear on the next render.

No `refreshInterval` — the status line is event-driven (Claude Code repaints it each message),
which keeps it fresh at zero idle cost.
