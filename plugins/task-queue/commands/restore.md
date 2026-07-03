---
description: Recover the working tree from the last crash-checkpoint snapshot
argument-hint: ""
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-checkpoint.sh" restore

The command above overlaid your last checkpoint snapshot onto the working tree —
recovering tracked + untracked edits a crash may have lost. The checkpoint ref is left
in place (restore is re-runnable). Tell the owner what was recovered in plain language;
if it reported "no checkpoint to restore", there was nothing snapshotted (checkpoint was
never armed, or no edits happened since) — say so plainly.
