---
description: Agent-mode — fan independent, low-blast-radius tasks out to subagents (on|off)
argument-hint: "on|off"
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-agent.sh" $ARGUMENTS

Agent-mode is now set as shown above (no argument = status).

When **on**, default to fanning independent, non-conflicting tasks out to subagents when
it pays off in speed (parallel reads/audits, disjoint per-item transforms, parallel
verification) — keeping coupled or high-fan-in work inline. Off by default (subagents cost
more tokens). Confirm the new state to the owner in one plain line.
