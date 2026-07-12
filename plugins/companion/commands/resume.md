---
description: Re-surface this repo's unfinished tasks from an earlier session and reinstate them
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/resume.sh"` to list this repo's still-open tasks carried over
from earlier sessions (the SessionStart hook does this automatically each new session — this is
the on-demand twin).

Then reinstate the ones still relevant into the current queue with `tq add "<subject>"` (skip
anything already done or no longer wanted), restoring any that were in progress with
`tq doing <id>` and picking up from its breadcrumb. Relay in one plain line what came back.
