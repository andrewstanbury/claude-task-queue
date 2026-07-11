---
description: Turn autopilot on or off (keep working autonomously while you're away)
---

Toggle autopilot for this repo by running the toggle script, passing the argument the user
gave (`on`, `off`, or nothing to report status):

`"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" <on|off|status>`

- **on** — the owner is stepping away. Run fully autonomous: keep draining the `tq` queue,
  don't ask, do all reversible work, and PARK what needs them (`❓ [parked]` decision /
  `⏳ [blocked]` owner-action). Enforced: the Stop hook auto-continues the queue and the
  ask-guard blocks AskUserQuestion while it's on. The flag persists across restarts.
- **off** — normal review loop resumes. Review any parked `❓` items first.

Relay the script's one-line confirmation to the user.
