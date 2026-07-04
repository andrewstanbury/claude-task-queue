---
description: Show what's on (autopilot / checkpoint / agents) and what work is still open
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-status.sh"

The readout above is this repo's task-queue control panel: which features are on, and
how much work is still open across sessions. Relay anything that needs your
attention; if a mode looks stale (e.g. autopilot still on when you're clearly back),
point it out.
