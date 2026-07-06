---
description: Turn checkpoint on/off — auto-save every edit so a crash can't lose work
argument-hint: "[on|off]"
allowed-tools: Bash
---

! action="$ARGUMENTS"; "${CLAUDE_PLUGIN_ROOT}/bin/tq-checkpoint.sh" "${action:-on}"

The command above already printed the new **checkpoint** state — that IS the confirmation
(bare = turn it ON; add `off` to turn it off). Acknowledge in at most one short line; do
**not** restate what the mode does.
(Zero-token alternative: run the `! …/tq-checkpoint.sh on` line — or `off` — yourself, no model turn.)
