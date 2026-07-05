---
description: Turn autopilot on/off — keep working on my own while you're away
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-away.sh" toggle

The line above flipped **autopilot** for this repo and printed the new state — relay
it in one plain sentence.

Autopilot **ON** = I keep working the queue on my own without stopping to ask (for
when you step away); the queue auto-continues, AskUserQuestion is blocked, and I
**park the decisions you'll want to make** — important direction and design/structural
choices, plus anything irreversible (delete / push / send / spend) — as `❓` items so
you come back to a reviewable pile. I decide the routine, low-stakes calls myself and
keep working.
Autopilot **OFF** = I stop auto-driving the queue and print the parked pile in full,
each with my recommendation — we clear those decisions **first**, before I pull any
new queue work, so you unblock the backlog in one pass. Flip autopilot back on (or say
"keep going") and I resume draining the queue. You never *need* this command — just say
"keep going while I'm gone" / "I'm back" and I'll set it.
