---
description: Turn autopilot on/off — keep working on my own while you're away
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-away.sh" toggle

The line above flipped **autopilot** for this repo and printed the new state — relay
it in one plain sentence.

Autopilot **ON** = I keep working the queue on my own without stopping to ask (for
when you step away); the queue auto-continues, AskUserQuestion is blocked, and
anything that genuinely needs you is parked as a `❓` item for when you're back.
Autopilot **OFF** = the normal review loop, where I check in on the consequential
calls. You never *need* this command — just say "keep going while I'm gone" / "I'm
back" and I'll set it.
