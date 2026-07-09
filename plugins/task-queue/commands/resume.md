---
description: Bring my task-queue back after quitting — reload this repo's open tasks
allowed-tools: Bash, TaskList, TaskGet, TaskCreate, AskUserQuestion
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-away.sh" off; "${CLAUDE_PLUGIN_ROOT}/bin/tq-restore.sh"

Resuming means you're **back at the keyboard**, so the first line above turned
**autopilot OFF** (idempotent if it was already off) and printed a digest of anything
autopilot parked — the normal review loop is back on. The rest is this repo's "put me
back where I was": the open tasks that carry over from an earlier session.

Act on it now, in this order:

1. If tasks carried over, REINSTATE them with TaskCreate (reading their full
   descriptions off disk first) so the live queue reflects the earlier session before
   you do anything else.
2. If any reinstated tasks are parked `❓ [parked]` decisions, review them FIRST — as a
   blocking AskUserQuestion, each with your recommendation as the first option — before
   pulling any new work (this is the `/task-queue:review` loop; run it if the pile is
   large). Relay `⏳ [blocked]` owner-actions plainly.
3. Relay in one plain sentence what came back.

Note honestly: this cannot reload the previous conversation itself — that needs
relaunching with `claude --resume`.
