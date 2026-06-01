---
description: Reconcile open/proposed work against recorded decisions and the roadmap
argument-hint: ""
allowed-tools: Bash, Read, Grep, Glob
---

! "${CLAUDE_PLUGIN_ROOT}/bin/charter-align.sh"

The anchors above are deterministic facts (where decisions/ADRs and the
roadmap/backlog live, plus what recently landed). The companion's alignment
checks otherwise only fire when work is *captured* — this command lets you check
alignment on demand, **before** committing to the work. **Clean ≠ correct:** a
well-made change can still be the wrong thing, contradict a recorded decision,
or drift from what's-next.

**Reconcile the current open work against the recorded direction** and report:

1. **Decision contradictions** — read the decisions/ADR doc above. Does any open
   or proposed task reverse or contradict a recorded choice? If so, name the
   decision and the conflict — that work needs an explicit decision change first,
   not a quiet override.
2. **Roadmap drift** — read the roadmap/backlog. Is the open work advancing a
   recorded Now/Next item, or has it drifted onto something undocumented? Flag
   work that isn't on the map (it may be right — but it should be recorded), and
   Now/Next items that nothing is moving.
3. **Reconcile what landed** — for each "recently landed" commit, say which
   roadmap/decisions entry it should now mark **done** or supersede, so the docs
   stay the honest record.

Rules of engagement:
- **Read-only.** Inspect the docs and the task list; change nothing here. If a
  fix is warranted (record a decision, update the roadmap), propose it and offer
  to do it as a follow-up.
- **Anchors missing?** If there are no recorded decisions or roadmap, say so
  plainly — alignment can only be judged against the conversation and the code,
  and the real fix is to capture the direction (charter nudges this at session
  start).
- **Plain language, proportional.** The owner may be non-technical. Lead with
  genuine **contradictions/drift** (the expensive failures); don't manufacture
  misalignment where the work plainly fits. End with a short, prioritized list of
  what to realign and offer to do it.
