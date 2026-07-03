---
description: Show task-queue's current state for this repo — modes, open work, ❓ awaiting you
argument-hint: ""
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-status.sh"

The readout above is task-queue's **control plane** for this repo — which modes are
on (review loop / away / checkpoint / agent) and how much work is still open — NOT a
re-listing of your task list (Claude Code renders that natively). Relay it in one or
two plain-language lines, and if anything looks off (e.g. away-mode still on when the
owner is back, or a checkpoint armed with a snapshot ready to restore), point it out.
