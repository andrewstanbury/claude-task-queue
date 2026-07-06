---
description: Turn autopilot on/off — keep working on my own while you're away
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-away.sh" toggle

The toggle above printed the new **autopilot** state. Then:

- If it turned **ON** — acknowledge in one short line and keep draining the queue on
  your own: decide routine, low-stakes, cheap-to-undo calls yourself (recommended
  option, recorded); PARK anything consequential or irreversible as a `❓` task; and if
  a decision blocks all progress and can't be parked, take your recommended default and
  record it rather than stalling. Never wait on the absent owner.
- If it turned **OFF** — present the parked `❓` pile in full, each with your
  recommendation, so those clear before any new queue work is pulled.

(Zero-token alternative for the flip itself: run the `! …/tq-away.sh toggle` line
yourself — no model turn. The OFF review still costs a turn because it's real work.)
