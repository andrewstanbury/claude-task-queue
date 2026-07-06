---
description: Turn checkpoint on/off — auto-save every edit so a crash can't lose work
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-checkpoint.sh" toggle

The toggle above already printed the new **checkpoint** state — that IS the confirmation.
Acknowledge in at most one short line; do **not** restate what the mode does.
(Zero-token alternative: run the `! …/tq-checkpoint.sh toggle` line yourself — no model turn.)
