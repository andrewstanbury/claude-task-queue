---
description: Turn checkpoint on/off — auto-save every edit so a crash can't lose work
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-checkpoint.sh" toggle

The line above flipped **checkpoint** for this repo and printed the new state — relay
it in one plain sentence.

Checkpoint **ON** = every edit is snapshotted to a hidden git ref off your branch
(history stays clean, nothing is pushed), so a crash can't lose uncommitted work —
recover with `/task-queue:restore`. **OFF** = no auto-saving. You can also just say
"make a safety net" / "stop checkpointing".
