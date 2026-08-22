---
description: "(no args) — answer the whole parked (❓) + blocked (⏳) pile up front, recommendation-first, then resume autopilot if it was on"
---

Run a **review**: clear the backlog of tasks that need *you* — the **parked (❓) decisions** and the
**blocked (⏳) owner-actions** — by asking **the whole pile up front**, recommendation-first, and
recording every pick before any new work. Run it any time; it is also what runs when autopilot is
turned off (R38).

**A review is transparent to autopilot (R83).** It disarms to ask anything — autopilot means don't
ask (R100: advisory now, not enforced, but the discipline still holds) — then re-arms itself at
the end and carries straight on draining. Reviewing is no longer a decision to stop working.

It's judgment + workflow, not enforcement — it proposes, you choose, it records (R28). It reuses the
`/companion:advise` presentation loop (R29) — don't build a second machine. It reviews **only** the
pile that needs deciding — to *re-surface carried-over tasks from an earlier session* first, run
`/companion:resume` (session-pickup), then this.

0. **Pause autopilot, don't kill it.** Call the **`autopilot_toggle`** MCP tool with `action: "pause"`
   before anything else — a review asks, and autopilot means don't (R100: advisory now, not enforced, but
   the sequencing is still right). `pause` records that autopilot **was** armed so step 5
   can put it back; it is a clean no-op when autopilot was already off. Never use `off` here —
   that is the owner's word, and it deliberately cancels any pending resume.

1. **Gather the pile — call the `review_pile` MCP tool** (or `bin/review-pile.sh`). It returns one
   TSV row per item needing you: `<class>\t<id>\t<subject>`, already filtered to ❓/⏳ and already
   classified. **That classification is the logic half of this command and it lives outside Claude
   Code on purpose** (R100 portability) — so any MCP client can drive a review, while the arrow-key
   presentation below stays native. Do NOT re-derive the pile from `tq_list`; a second filter is how
   the two drift.
   The classes tell you HOW to ask: `blocked` = an owner ACTION (never a menu to accept) ·
   `decompose` = questions, so interview (R65) · `options-rec` = a real pick exists, sweep-eligible ·
   `options` = a full menu is owed. Empty output → say so in one line and stop; that is a clean
   no-op, not a reason to manufacture questions.

2. **Ask the whole pile UP FRONT, recommendation-first.** Do not drip-feed one question per turn:
   batch them into as few `AskUserQuestion` calls as the tool allows (**up to 4 questions per
   call**), in smallest-blast / dependency order, and keep issuing batches until every item has
   been put to the owner. State the total up front ("12 parked, 3 blocked — here are the first
   4"). The point is that the owner sits down **once** and comes back to a drained queue, rather
   than being interrupted fifteen times.

   Only split an item out of a batch when it genuinely cannot be answered alongside the others —
   a decompose-park interview (below), or a choice whose options depend on how an earlier one in
   the same batch was answered. In that case ask the independent ones first, then the dependent.

   **2a. OPEN WITH THE ACCEPT SWEEP — `multiSelect: true` (owner-asked 2026-08-12).** Most parks
   arrive carrying a `rec:` the owner simply agrees with, and making them arrow through a separate
   4-option menu to say "yes, your pick" is the interruption this command exists to remove. So when
   **two or more** eligible parks are in the pile, ask **first**:

   > *"Which of my recommendations should I just apply?"* — `multiSelect: true`, one option per
   > park. **Label** = `#<id> <the choice in a few words>`. **Description** = the recorded `rec:`
   > and its real cost, plus `⚠ IRREVERSIBLE` when the park is not marked `rev:`, so a batch tick
   > never hides a one-way door.

   The tool takes **2–4 options per question and up to 4 questions per call**, so group the pile
   into questions of 4 — that is **16 parks accepted in a single interaction**, against 4 under
   the per-item path alone. Keep issuing batches until the pile is covered.

   **Unselected is NOT rejected — it is "ask me properly".** A multiSelect returns only the
   *presence* of a yes, never a no, so treating an unticked box as a decision would silently
   invent one. Every park the owner does not tick falls through to its own full single-select
   question below, options intact. Say this in one line when you ask, so ticking nothing is
   understood as "walk me through them", not "reject everything".

   **NOT eligible for the sweep**, and each for its own reason: **⏳ blocked** items (an owner
   action is not a recommendation to accept), **decompose-parks** (R65 — they carry questions, not
   options, so there is nothing to accept yet), and any park whose `rec:` is missing or is a thin
   guess rather than a real pick. Those go straight to the per-item path.

   For each item:
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
   - **⏳ blocked — MANUAL WORK ONLY THE OWNER CAN DO** (deploy, purchase, physical check, an
     approval in a system you cannot reach). This is their to-do list, so present it as one: state
     the action plainly and offer *Done (unblocked) / Still blocked / Drop it*, recommended by your
     read of whether it is actionable now. If an item is really a decision you could implement once
     answered, it was mis-filed — re-file it as `❓` rather than asking them to go do something.

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
   - **Defer** → leave the item as-is and **always** `tq note <id> "deferred <what you're waiting on>"`.
     Not optional: that note is the ONLY record that the owner has actually SEEN this park, and
     `candidates.sh` rank 1 now requires it before burn-down may build a park unattended. Skip it and
     a park the owner genuinely deferred is treated as never-reviewed (safe, but it loses the tier);
     the note is what separates "chosen and set aside" from "the model wrote this and nobody looked".

4. **Close the loop.** Recap the picks in a short table (item → decision → what's now queued), then
   confirm the queue state with `tq report`. If a decision would touch a locked requirement, offer
   to draft the ledger entry (per R5).

5. **Resume autopilot and keep going.** Call **`autopilot_toggle`** with `action: "resume"`. If
   the review paused it, this re-arms it and you carry on draining the newly-queued work
   immediately — the picks **are** the go, so do not ask for a second blanket confirmation. If
   autopilot was off when the review started, `resume` is a no-op and you simply continue in the
   normal loop. Either way, say in one line which mode you are now in, so the owner is never
   guessing whether work is still happening.
