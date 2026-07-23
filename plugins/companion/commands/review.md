---
description: Walk the parked (❓) + blocked (⏳) backlog one at a time, recommendation-first, writing picks back to the queue
---

Run a **review**: walk the backlog of tasks that need *you* — the **parked (❓) decisions** and the
**blocked (⏳) owner-actions** — one at a time, recommendation-first, recording each pick before any
new work. This is the ritual that runs when autopilot is turned off (R38), and you can run it any
time to clear the pile of things waiting on your input.

It's judgment + workflow, not enforcement — it proposes, you choose, it records (R28). It reuses the
`/companion:advise` presentation loop (R29) — don't build a second machine. It's owner-present by
nature: autopilot's ask-guard blocks the questions, so it's meant for when autopilot is **off**
(turning it off is the trigger). It reviews **only** the pile that needs deciding — to *re-surface
carried-over tasks from an earlier session* first, run `/companion:resume` (session-pickup), then
this.

0. **Clear autopilot first.** If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`
   before anything else — while the persisted flag is on, the ask-guard blocks `AskUserQuestion` and
   this review can't ask a single question. (The `/companion:autopilot off` command already does
   this; on the plain-conversation "turn it off" path, do it here. Mirrors `/companion:advise` /
   `/companion:docs` / `/companion:cover`.)

1. **Gather the pile — parked + blocked only.** Run `"${CLAUDE_PLUGIN_ROOT}/bin/tq" list` (**not
   `report`** — the report truncates each subject to ~72 chars, and a parked item carries its options
   *in* the subject) and take only the tasks whose subject starts with **❓ (parked decision)** or
   **⏳ (owner-blocked action)**. **Ignore plain `📋 open` tasks** — they need doing, not deciding;
   presenting a menu for "implement X" is noise. If nothing is parked or blocked, say so in one line
   and stop — this is a clean no-op, not a reason to manufacture questions.

2. **Walk it one at a time, recommendation-first.** For each item, in smallest-blast / dependency
   order, present a **single `AskUserQuestion`** — number them ("N of M"), carry picks forward:
   - **❓ parked** — the subject already frames the choice; surface its recorded options + your
     recommendation. Options recommended-first, `(Recommended)` on your pick, each naming its
     trade-off / what it changes (cite an R-ID if an option touches or reverses a ledger requirement
     — 🔒 needs explicit sign-off). Always include a **"Defer — keep parked, ask me later"** option so
     a large pile never becomes a forced march.
   - **❓ decompose-park (R65, subject carries `decompose:`)** — the payload is a risk analysis +
     context questions, *not* options (options invented without the missing context would be
     premature). Run it as a short **interview**: ask the recorded questions (free-text answers are
     the expected path), then propose the decomposition — the minimal-blast children — as a
     recommendation-first menu. If the task is irreducibly high-blast, offer *bless it through as-is*
     (queued with the blessing recorded in the subject) or *keep it yours (⏳)*.
   - **⏳ blocked** — present the owner action and offer *Done (unblocked) / Still blocked / Drop it*,
     recommended by your read of whether it's actionable now.

   The owner can **bail at any point** — "review before new work" is the default, not a wall.
   Deferred and still-blocked items stay in the pile untouched for next time.

3. **Write each pick back to `tq` immediately** (so a crash mid-review loses nothing) using only the
   real verbs — `add [--done]` / `doing` / `done` / `cancel` / `note` (there is no subject-edit):
   - **Decision made on a ❓** → `tq note <id> "decided: <pick + one-line why>"`, then convert:
     `tq add "<the concrete decided task>" --done "<acceptance>"` (a fresh actionable task, no ❓
     prefix) and `tq done <id>` (or `tq cancel <id>` if the decision was "don't"). If the decision
     *is* the whole resolution, just `tq done <id>`.
   - **Decompose-park answered (R65)** → `tq note <id> "context: <the answers>"`, then `tq add` each
     minimal-blast child (`--done` acceptance on each) and `tq done <id>` — the original never
     survives as a high-blast open task. Blessed through instead → re-`add` it *without* the
     `decompose:` flag, blessing in the subject, and `done` the original.
   - **⏳ Done** → `tq add` the now-doable task (or `tq done <id>` if it's finished) and `done`/`cancel`
     the placeholder. **Still blocked** → leave it (optionally `tq note` the latest status). **Drop** →
     `tq cancel <id>`.
   - **Defer** → leave the item as-is (optionally `tq note <id> "deferred <what you're waiting on>"`).

4. **Close the loop.** Recap the picks in a short table (item → decision → what's now queued), then
   confirm the queue state with `tq report`. The picks **are** the go — flow straight into the newly
   queued work in order (the STEERING pause triggers still govern: stop only on a genuinely
   consequential item, not for a blanket second confirmation). If a decision would touch a locked
   requirement, offer to draft the ledger entry (per R5).
