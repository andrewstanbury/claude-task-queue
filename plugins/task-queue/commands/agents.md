---
description: Turn agents on/off — split big jobs across parallel helpers to go faster
argument-hint: "[on|off]"
allowed-tools: Bash
---

! action="$ARGUMENTS"; "${CLAUDE_PLUGIN_ROOT}/bin/tq-agent.sh" "${action:-on}"

The command above already printed the new **agents** state — that IS the confirmation
(bare = turn it ON; add `off` to turn it off). Acknowledge in at most one short line; do
**not** restate what the mode does.
(Zero-token alternative: run the `! …/tq-agent.sh on` line — or `off` — yourself, no model turn.)
