---
description: Resume an earlier session — re-surface this repo's carried-over tasks, then review the parked/blocked pile one at a time, recommendation-first, writing your picks back to the queue before new work
---

Run a **session resume**: re-surface this repo's tasks carried over from an earlier session, then
**review** the parked/blocked pile one at a time, recommendation-first, recording each pick before
any new work. This is the ritual that runs when autopilot is turned off (R38), and you can run it
any time. Named `resume` because the session-pickup is its first move — it is the **single entry
point** for the pickup **and** the parked-pile review (R38/R39; it absorbed the standalone `review`
command, renamed 2026-07-18, and the earlier `resume` fold).

It's judgment + workflow, not enforcement — it proposes, you choose, it records (R28). It reuses
the `/companion:advise` presentation loop (R29). It's owner-present by nature: autopilot's ask-guard
blocks the questions, so it's meant for when autopilot is **off** (turning it off is the trigger).

0. **Clear the flag first (conversational path).** If you got here because the owner asked in plain
   language to turn autopilot off (not via `/companion:autopilot off`, which already does this), run
   `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off` **before** anything else — while the persisted flag
   is still on, the ask-guard blocks `AskUserQuestion` and the review can't ask a single question.

1. **Re-surface earlier-session tasks (session pickup — the former `/companion:resume`, R39).** Run
   `"${CLAUDE_PLUGIN_ROOT}/bin/resume.sh"`: it turns **autopilot off first** — announced in one line
   when it was on (relay that notice; never a silent clobber of a persisted intent — re-arm is a
   manual `/companion:autopilot on`), quiet no-op when already off — and lists this repo's still-open
   tasks carried over from earlier sessions (the SessionStart hook does this automatically each new
   session; this is the on-demand twin). Reinstate the ones still relevant (skip anything already
   done or no longer wanted), **preserving each item's classification** — a decision comes back
   parked (`tq add "❓ [parked] <the choice + options + your recommendation>"`), an owner-only action
   blocked (`tq add "⏳ [blocked] <action>"`), a plain doable task open (`tq add "<subject>"`).
   **Never promote a parked decision into a plain open task** — that would let the next drain
   autopilot the answer instead of asking you (R39·D). Restore anything in progress with
   `tq doing <id>` and pick up from its breadcrumb. Clean no-op if nothing carried over — go
   straight to the pile.

2. **Gather the pile — parked + blocked only.** Run `"${CLAUDE_PLUGIN_ROOT}/bin/tq" list` (**not
   `report`** — the report truncates each subject to ~72 chars, and a parked item carries its options
   *in* the subject) and take only the tasks whose subject starts with **❓ (parked decision)** or
   **⏳ (owner-blocked action)** — including anything you just re-parked in step 1.
   **Ignore plain `📋 open` tasks** — they need doing, not deciding; presenting a menu for
   "implement X" is noise. If nothing is parked or blocked, say so in one line and stop — this is
   a clean no-op, not a reason to manufacture questions.

3. **Walk it one at a time, recommendation-first.** For each item, in smallest-blast / dependency
   order, present a **single `AskUserQuestion`** — number them ("N of M"), carry picks forward:
   - **❓ parked** — the subject already frames the choice; surface its recorded options + your
     recommendation. Options recommended-first, `(Recommended)` on your pick, each naming its
     trade-off / what it changes (cite an R-ID if an option touches or reverses a ledger
     requirement — 🔒 needs explicit sign-off). Always include a **"Defer — keep parked, ask me
     later"** option so a large pile never becomes a forced march.
   - **⏳ blocked** — present the owner action and offer *Done (unblocked) / Still blocked / Drop it*,
     recommended by your read of whether it's actionable now.

   The owner can **bail at any point** — "review before new work" is the default, not a wall.
   Deferred and still-blocked items stay in the pile untouched for next time.

4. **Write each pick back to `tq` immediately** (so a crash mid-review loses nothing) using only the
   real verbs — `add [--done]` / `doing` / `done` / `cancel` / `note` (there is no subject-edit):
   - **Decision made on a ❓** → `tq note <id> "decided: <pick + one-line why>"`, then convert:
     `tq add "<the concrete decided task>" --done "<acceptance>"` (a fresh actionable task, no ❓
     prefix) and `tq done <id>` (or `tq cancel <id>` if the decision was "don't"). If the decision
     *is* the whole resolution, just `tq done <id>`.
   - **⏳ Done** → `tq add` the now-doable task (or `tq done <id>` if it's finished) and `done`/`cancel`
     the placeholder. **Still blocked** → leave it (optionally `tq note` the latest status). **Drop** →
     `tq cancel <id>`.
   - **Defer** → leave the item as-is (optionally `tq note <id> "deferred <what you're waiting on>"`).

5. **Close the loop.** Recap the picks in a short table (item → decision → what's now queued), then
   confirm the queue state with `tq report`. Only **after** the review do you resume normal work —
   and only if the owner says go. If a decision would touch a locked requirement, offer to draft the
   ledger entry (per R5).
