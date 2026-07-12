---
description: Turn autopilot on or off (keep working autonomously while you're away)
---

Toggle autopilot for this repo by running the toggle script, passing the argument the user
gave (`on`, `off`, `status`, or `ship on|off|status`):

`"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" <on|off|status | ship on|off|status>`

- **on** — the owner is stepping away. Run fully autonomous: keep draining the `tq` queue,
  don't ask, do all reversible work, and PARK what needs them (`❓ [parked]` decision /
  `⏳ [blocked]` owner-action; a visual/design/direction choice is parked too, not decided — R33).
  Enforced: the Stop hook auto-continues the queue and the ask-guard blocks AskUserQuestion while
  it's on. The flag persists across restarts.
- **off** — normal review loop resumes. Review any parked `❓` items first.
- **ship on|off** — toggle **ship-mode** (R34). While ship-mode *and* autopilot are on, the Stop
  hook auto-commits each turn's work to an `autopilot/*` branch (reversible; **never the default
  branch, never a push**), so completed work is captured for the owner to review + `/companion:ship-it`
  on return. Shown as 📦 on the status line.

Relay the script's one-line confirmation to the user.
