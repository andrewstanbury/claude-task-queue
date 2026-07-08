---
description: Review parked (❓) tasks — answer each with a recommendation, then resume
allowed-tools: Bash, TaskList, TaskGet, TaskUpdate, AskUserQuestion
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-status.sh"

You've come back from being away. Before pulling any new work, clear the **parked
pile** — the `❓ [parked]` tasks the queue set aside for a decision only you can make.
Run this loop:

1. **Gather.** Read the current task list (TaskList) and collect every open task whose
   subject starts with `❓` (or is otherwise marked parked). If there are none, say so
   in one line and stop — there's nothing to review.

2. **Present, don't prose.** Walk the parked items through **AskUserQuestion**, in
   batches of at most 4 questions per call (the tool's cap — make multiple calls if
   needed). For EACH item give 2–4 concrete options with your **recommendation as the
   FIRST option, labelled "(Recommended)"**. Base the recommendation on what the task's
   description already records. Order the batches **decision-ready first** (answering
   unblocks autonomous work) and **externally-blocked last** (needs a device, a
   backend/infra change, an external service, or a hands-on action from the owner).

3. **Be honest about what an answer unblocks.** For an externally-blocked item, one
   option must be to **keep it parked** with its blocker tag — answering records your
   intent/design choice but the work still can't run autonomously, so it should
   resurface when the blocker clears rather than be falsely auto-attempted. Never imply
   autopilot will make progress it can't.

4. **Apply each answer:**
   - A decision that unblocks work → drop the `❓`, restore it to a normal queued task
     (TaskUpdate) so it gets worked.
   - "Keep parked" → leave it parked, but fold the chosen decision into its description
     and tag the blocker (device / backend / owner-action / launch-gate) so a later
     session knows exactly when it becomes actionable.
   - "Drop it" → delete the task and record the decision (memory / ROADMAP) so it isn't
     silently lost or re-proposed.

5. **Re-scope on contact with reality.** If, while applying an answer, the work turns
   out to be materially different from what the option implied (bigger blast radius, a
   hidden dependency, not verifiable here), STOP and say so plainly — re-present the
   real options rather than shipping something the owner didn't actually choose.

6. **Then resume.** Once the pile is cleared, pull the now-unblocked work in dependency
   order (smallest blast-radius first) and continue — or, if the owner is heading back
   out, hand off to autopilot. Verify your own work (run the tests/build). Keep going
   until nothing is left but `❓ [parked]` items again.
