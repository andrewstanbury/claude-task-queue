---
description: Review parked ❓ decisions (answer each with a recommendation) and ⏳ owner-blocked items, then resume
allowed-tools: Bash, TaskList, TaskGet, TaskUpdate, AskUserQuestion
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-status.sh"

You've come back from being away. Before pulling any new work, clear the **parked
pile**. Autopilot marks two distinct kinds of deferral:

- `❓ [parked]` — a **decision only you can make**. These are what you review and answer.
- `⏳ [blocked]` — the work is **waiting on a manual action only you can take** (a device,
  an external/paid service, an owner-only test, a step Claude can't run). Nothing to
  decide — you just need to *do* the thing before it can proceed.

Run this loop:

1. **Gather.** Read the current task list (TaskList) and split the open tasks into
   `❓` decisions and `⏳` owner-blocked items. If there are none of either, say so in
   one line and stop — there's nothing to review.

2. **Present the `❓` decisions, don't prose.** Walk them through **AskUserQuestion**, in
   batches of at most 4 questions per call (the tool's cap — make multiple calls if
   needed). For EACH item give 2–4 concrete options with your **recommendation as the
   FIRST option, labelled "(Recommended)"**. Base the recommendation on what the task's
   description already records.

3. **List the `⏳` blocked items plainly** (no AskUserQuestion — there's no choice to
   make). For each, state in one line what only you can unblock and why. These do NOT
   block editing and the queue drains around them; leave each `⏳` as-is so it resurfaces
   when the blocker clears — never imply autopilot will make progress it can't.

4. **Apply each `❓` answer:**
   - A decision that unblocks work → drop the `❓`, restore it to a normal queued task
     (TaskUpdate) so it gets worked.
   - "Not yet — I'll act on it" → the decision is really an owner action; re-tag it as
     `⏳ [blocked]` (TaskUpdate), folding the chosen intent into its description.
   - "Drop it" → delete the task and record the decision (memory / ROADMAP) so it isn't
     silently lost or re-proposed.

5. **Re-scope on contact with reality.** If, while applying an answer, the work turns
   out to be materially different from what the option implied (bigger blast radius, a
   hidden dependency, not verifiable here), STOP and say so plainly — re-present the
   real options rather than shipping something the owner didn't actually choose.

6. **Then resume.** Once the `❓` decisions are cleared, pull the now-unblocked work in
   dependency order (smallest blast-radius first) and continue — or, if the owner is
   heading back out, hand off to autopilot. Verify your own work (run the tests/build).
   Keep going until nothing is left but `❓ [parked]` / `⏳ [blocked]` items again.
