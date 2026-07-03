---
description: Pause/resume the interpret→present→approve review loop for this repo (on|off)
argument-hint: "on|off"
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-pause.sh" $ARGUMENTS

The review loop is now set as shown above (no argument = status).

When **paused**, substantive prompts run straight through in auto — no present-and-approve
checkpoint, and intent capture is suppressed too. When **active**, the loop intercepts
substantive work again. Confirm the new state to the owner in one plain line.
