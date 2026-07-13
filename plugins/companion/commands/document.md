---
description: Scan an existing repo and record its load-bearing, undocumented decisions — as checks where possible, honestly-graded ledger entries otherwise — so advise stops guessing and can't reverse a critical choice that was never written down
---

Run a **document**: excavate the decisions an existing repo *depends on but never wrote down*,
and record them in the doc `advise` already reads — so `/companion:advise` stops guessing and
stops proposing to remove or redesign something critical that simply wasn't communicated.

`document` is the **producer** side of advise (R41): advise (R29) *consumes* `REQUIREMENTS.md`;
`document` *populates* it. It is judgment + workflow, not enforcement — it proposes, you choose, it
records (R28). It's owner-present by nature (it asks questions), so it's meant for when autopilot is
**off**. It reuses the `/companion:advise` recommendation-first loop (R29) — don't build a second
machine.

**The governing idea — record for the agent that will consume it.** Rank every finding by
*reliability to Claude*, and record it at the highest tier it can reach:

> **executable check** (Claude *can't* ignore it) › **🔒 ledger entry** (read, treated as a
> constraint) › **🔓 ledger entry** (read, but challengeable) › **dropped** (incidental — recording
> it just adds contradiction surface and tokens, R3).

Two honesty rules make this safe rather than a fabrication machine:
- **Strength-of-why sets the lock.** A decision with a *real, articulated why* → **🔒** (advise must
  not silently reverse it). A decision whose why is weak or unknown → **🔓** (advise *may* challenge
  it — it was never a real constraint). Never launder a guess into a 🔒.
- **Tag provenance** — `stated` (the owner supplied the reason) · `inferred` (Claude *assumed* it and
  the owner *confirmed* the assumption by picking it) · `unknown` (no reason available → 🔓). Claude's
  guesses are surfaced as multiple-choice options with a top pick, but **only the owner's active pick
  records one** — an unchosen assumption never becomes a 🔒. A labeled **`unknown → 🔓`** is *better*
  than a confident-but-wrong 🔒; confident-and-wrong is the worst possible input to an agent.

---

0. **Clear autopilot first.** If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`
   before anything else — while the flag is on, the ask-guard blocks `AskUserQuestion` and this
   command can't ask a single question. (Mirrors `/companion:review` step 0.)

1. **Scan — read-only, no questions.** Detect the repo's structure **generically** (R9 — no
   language/framework allowlists; delegate recognition to the model, detect structure generically).
   Spawn a small panel of scanner sub-agents, each a distinct lens for what is **load-bearing *and*
   likely-undocumented**:
   - **invariants / constraints** the code clearly relies on (a single-writer, a dependency
     boundary, an ordering/idempotency assumption, an encoding that must match across readers);
   - **architectural / design choices** (why it's structured this way — a pattern chosen on purpose);
   - **technical requirements** (performance budgets, size limits, compatibility targets, data-safety);
   - **landmines** — code that *looks* removable or refactorable but is actually holding something
     up: the exact thing advise would delete. Weight these highest.

   Give each lens the repo + the goal. **Each must first read the existing ledger + `docs/` and skip
   anything already recorded** — this command adds to ground truth, it doesn't restate it. Each
   candidate returns: the observed fact · evidence (`file:line`) · estimated **blast-radius** · a
   confidence · and an *inferred* why **explicitly marked as inference, never as fact.** License each
   lens to find nothing — a manufactured "decision" is worse than silence.

2. **Rank → a silent candidate report (Pass 1).** Merge and dedupe the panel, drop anything already
   in the ledger, and rank by *blast-radius × how likely advise is to touch it*. Write the ranked
   list to a short **scratch report** (not the ledger yet) and hand it to the owner to prune. **Ask
   nothing in this pass** — this is what keeps the ledger dense and high-signal (R3). If the scan
   surfaced nothing load-bearing that isn't already documented, say so in one line and stop.

3. **Triage the survivors one at a time (Pass 2) — the owner owns the rationale.** For each
   survivor, in blast-radius order (number them "N of M", carry picks forward), present a **single
   `AskUserQuestion` whose options ARE your candidate rationales** — your assumptions about *why* the
   thing is the way it is, **best-guess first and marked `(Recommended)`**, each a concrete reason.
   The point is to **put the onus on the owner to fill in the why**, not to assume one: you surface
   your guesses transparently, the owner **picks, overrides, or declines**. Every such question MUST
   also offer:
   - **An open-ended "I'll write my own rationale" option — ALWAYS, on every single question**
     (delivered as `AskUserQuestion`'s free-text "Other"): the owner types their own reason →
     provenance `stated` → **🔒**. Never present a closed set of guesses with no way to supply a
     different reason — the owner must always be able to write the why in their own words.
   - **"No clear why / I don't know"** → provenance `unknown` → **🔓** (advise may challenge it).
   - **"Not actually load-bearing — drop it"** → record nothing.
   - **"Defer — decide later"** → leave it for next time (R38's escape; a big pile is never a forced march).

   A **picked assumption** → provenance `inferred` (you guessed, the owner confirmed) → **🔒**. The
   owner's **active pick is what records it** — an assumption the owner never chose is *never* written
   as a 🔒 (the anti-laundering rule; this is why presenting guesses is safe). **Challenge a claimed
   🔒 once** before accepting — *"is that why still true? what breaks if it's reversed?"* — so legacy
   rationale gets thought through, not waved through; if the owner can't stand behind it, it's a 🔓.

   Then **record at the highest reliable tier**: if the confirmed constraint is *mechanizable* (a
   boundary, budget, forbidden pattern, an invariant a test could assert), also emit a `check.sh`
   assertion / lint — the tier Claude can't ignore — alongside the ledger entry.

4. **Record each pick at its tier — in the docs advise already reads.**
   - **Executable check** → add the assertion to `check.sh` (or the project's lint), plus a one-line
     ledger pointer to it. Verify it passes on the current tree before moving on.
   - **🔒 / 🔓 judgment constraint** → a **terse** `REQUIREMENTS.md` entry (R3 — dense, not an essay):
     the constraint · its **status** (🔒/🔓) · **provenance** (stated/inferred/unknown) · the **why**
     (or an explicit "why unknown"). If a decision touches an existing locked requirement, cite the
     R-ID (R5).
   - A **gotcha** belongs in `docs/LESSONS.md`; a **coined term** in `docs/GLOSSARY.md` (R37) — not
     the ledger. Keep the ledger to *requirements*.

5. **Close the loop.** Recap in a short table — *item → tier (check / 🔒 / 🔓 / dropped) → where
   recorded*. Then state plainly **what stayed 🔓** (the constraints with no real why): advise is now
   free to challenge exactly those, and must not silently reverse the 🔒s. Only after this is advise
   standing on documented ground instead of guessing.
