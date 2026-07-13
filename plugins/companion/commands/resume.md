---
description: Re-surface this repo's unfinished tasks from an earlier session and reinstate them, then triage the pile
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/resume.sh"` to list this repo's still-open tasks carried over
from earlier sessions (the SessionStart hook does this automatically each new session — this is
the on-demand twin). Resume is a **triage handoff (R39)**: the script turns **autopilot off first**
(announced when it was on) so the resurfaced pile comes back to *you*, not to autopilot — relay
that one-line notice if it printed.

Then reinstate the ones still relevant into the current queue (skip anything already done or no
longer wanted), **preserving each item's classification** — a decision comes back parked
(`tq add "❓ [parked] <the choice + your options + your recommendation>"`), an owner-only action
comes back blocked (`tq add "⏳ [blocked] <action>"`), a plain doable task comes back open
(`tq add "<subject>"`). **Don't promote a parked decision into a plain open task** — that would let
the next drain autopilot the answer instead of asking you (R39/D). Restore anything that was in
progress with `tq doing <id>` and pick up from its breadcrumb. Relay in one plain line what came
back.

Then, because autopilot is now off, **run the parked-pile review (R38)** — follow
`/companion:review`: walk the `❓ [parked]` + `⏳ [blocked]` pile (including anything you just
re-parked) one item at a time, recommendation-first, and write each pick back to `tq` **before**
starting any new work. Clean no-op if nothing is parked or blocked.
