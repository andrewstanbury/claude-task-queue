---
description: Turn agents on/off — split big jobs across parallel helpers to go faster
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-agent.sh" toggle

The toggle above already printed the new **agents** state — that IS the confirmation.
Acknowledge in at most one short line; do **not** restate what the mode does.
(Zero-token alternative: run the `! …/tq-agent.sh toggle` line yourself — no model turn.)
