---
description: Wire hud's status line into settings.json (one-time, version-resilient)
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/hud-install.sh"

The hud status line above is now wired into your `~/.claude/settings.json` with a
**version-resilient** command — it always runs the newest installed hud, so it
keeps working across future hud updates (no pinned version path). If it reports a
problem, follow the manual one-liner it printed. Restart Claude Code to see the
status line.
