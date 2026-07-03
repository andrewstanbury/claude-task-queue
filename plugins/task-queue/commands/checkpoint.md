---
description: Crash-checkpoint — auto-snapshot working-tree edits to a hidden ref (on|off)
argument-hint: "on|off"
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-checkpoint.sh" $ARGUMENTS

Crash-checkpoint is now set as shown above (no argument = status).

When **on**, task-queue snapshots your working tree (tracked + untracked) to a hidden
ref (`refs/tq/checkpoint`) after each edit — off your branch, so history stays clean and
nothing is pushed. If a crash loses uncommitted edits, recover them with
`/task-queue:restore`. Confirm the new state to the owner in one plain line.
