---
description: Turn autopilot on or off (keep working the queue autonomously, without stopping to ask)
---

Toggle autopilot for this repo by running the toggle script, passing the argument the user
gave (`on`, `off`, `status`, or `ship on|off|status`):

`"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" <on|off|status | ship on|off|status>`

- **on** — **keep going without stopping** (R36) — *not* "the owner is away"; they may be present,
  queuing up more tasks and keeping it on deliberately. Run autonomous: keep draining the `tq`
  queue, don't stop to ask, do all reversible work, and PARK what needs the owner's judgment
  (`❓ [parked]` decision / `⏳ [blocked]` owner-action; a visual/design/direction choice is parked
  too, not decided — R33). Enforced: the Stop hook auto-continues the queue and the ask-guard blocks
  AskUserQuestion (asking = stopping) while it's on. The flag persists across restarts.
- **off** — normal review loop resumes. **Immediately run the parked-pile review** (R38): walk the
  `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first, and record each pick back
  to `tq` **before** any new work — follow `/companion:resume` (defer/bail allowed; no-op if the pile
  is empty). Do this whether the owner turned autopilot off by this command or in plain conversation.
- **ship on|off** — toggle **ship-mode** (R34). While ship-mode *and* autopilot are on, the Stop
  hook auto-commits each turn's work to an `autopilot/*` branch (reversible; **never the default
  branch, never a push**), so completed work is captured for the owner to review + `/companion:ship-it`
  on return. Shown as 📦 on the status line.

Relay the script's one-line confirmation to the user.
