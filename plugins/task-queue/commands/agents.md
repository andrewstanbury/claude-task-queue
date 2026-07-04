---
description: Turn agents on/off — split big jobs across parallel helpers to go faster
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-agent.sh" toggle

The line above flipped **agents** for this repo and printed the new state — relay it
in one plain sentence.

Agents **ON** = I may fan independent, low-blast-radius tasks out to parallel helpers
(subagents) for speed — it costs more tokens, so it's opt-in. **OFF** = I work
everything inline (the default).
