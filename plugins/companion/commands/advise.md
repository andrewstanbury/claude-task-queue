---
description: Brutally-honest ground-up critique of a target, presented as recommendation-first options you pick one at a time, then queued
---

Run an **advise**: an independent, brutally-honest critique of a target — its current state vs.
what a ground-up redesign would recommend — decomposed into decisions you pick **one at a time**,
then queued. The target is `$ARGUMENTS` (a file, subsystem, decision, or free-text topic); with
none, advise on the **whole project**.

This is judgment + workflow, not enforcement — it never blocks or edits on its own; it proposes,
you choose (R28). It's owner-present by nature: autopilot's ask-guard blocks the questions, so
don't run it while autopilot is on.

1. **Scope + understand.** Resolve the target. Read what you genuinely need to critique it
   honestly: the relevant code, the requirements ledger (`REQUIREMENTS.md`), `docs/MAP.md`, and —
   if the target is the whole project — its complete current functionality. Restate in one line
   *what* you're advising on and *against what goal*. Default goal: "designed primarily for the
   agent that runs it, keeping a similar UX + code quality"; take an explicit goal from the
   arguments if one is given.

2. **Critique independently — a panel, not you.** The critique must come from contexts that did
   **not** build the thing; that independence is what makes it honest instead of self-justifying.
   Spawn a small panel of critic sub-agents, each a distinct lens — e.g. correctness/robustness ·
   simplicity & YAGNI · user experience · cost/efficiency · a steelman-then-attack generalist.
   Give each the target + goal; ask each for an honest assessment and a list of **deltas**
   (current → recommended), where each delta is a crisp problem, 2-4 concrete options, and a
   recommended option **with the one-line reason why**. If sub-agents aren't available, do it
   inline but adopt each lens explicitly in turn. **License every critic to conclude "this is
   already right — no change":** an advise that manufactures deltas just to have something to
   present trains exactly the fake pushback the steering doc forbids. Say so plainly when a
   dimension is already sound.

3. **Synthesize.** Dedupe and merge the panel's deltas into one ordered list, highest-leverage
   first. Drop any that don't survive your own scrutiny. For each survivor settle on 2-4 *distinct*
   options and your single recommendation + one-line why. Flag any option that would touch or
   reverse a ledger requirement, citing the R-ID (locked 🔒 needs explicit sign-off).

4. **Headline, then decide one at a time.** Give a short, brutally-honest summary — the
   current-vs-recommended headline, including "mostly already right" if that is the truth. Then go
   delta-by-delta: for each, state your recommendation and why in a line or two, then ask it as a
   **single `AskUserQuestion`** — options recommended-first, `(Recommended)` on your pick, and each
   option's description naming its trade-off / what it changes. One delta per question; number them
   ("N of M"); carry the picks forward.

5. **Close the loop.** Summarize the chosen options in a table. Then offer to (a) `tq add` each
   pick as a task (smallest blast-radius first; park anything ambiguous as `❓ [parked]`), and (b)
   draft a requirements-ledger entry recording the decisions. **Don't start the work unless they
   say go** — an advise produces decisions and a queue, not edits.
