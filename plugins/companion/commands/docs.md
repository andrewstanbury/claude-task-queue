---
description: Record a repo's undocumented load-bearing decisions as checks or graded ledger entries (feeds advise/redesign)
---

Run a **docs sweep**: excavate the decisions an existing repo *depends on but never wrote down*,
and record them in the doc `advise` already reads — so `/companion:advise` stops guessing and
stops proposing to remove or redesign something critical that simply wasn't communicated.

`docs` is the **producer** side of advise (R41): advise (R29) *consumes* `REQUIREMENTS.md`;
`docs` *populates* it. It is judgment + workflow, not enforcement — it proposes, you choose, it
records (R28). It's owner-present by nature (it asks questions), so it's meant for when autopilot is
**off**. It reuses the `/companion:advise` recommendation-first loop (R29) — don't build a second
machine.

**`docs` is the batch backstop; the just-in-time twin is a STEERING nudge.** The preferred path
is to capture a decision's *why* **the moment it's made** during normal work (the "load-bearing
decision just made → log the why now" nudge — provenance `stated`, the why still fresh). `docs`
then earns its place for what JIT can't catch: decisions made **before** the record existed, and
**autopilot runs** where no one was present to answer. Batch is reconstruction; JIT is recording —
prefer JIT, run `docs` to sweep up the rest.

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

**Two axes, not one (R54).** The tier above is *reliability*. Each item also has a **contract
pillar** that decides **which doc it lands in** — the routing (safety-invariant → `INVARIANTS.md` +
check · UX → `docs/flows/` · quality → `_quality-bar.md` · incidental → dropped) is enumerated once,
canonically, in **step 4**. Three rules govern that routing:
- **A why is mandatory at contract tier (R70).** A quality attribute enters `_quality-bar.md` (or a
  `quality:` field) only with a stated/owner-confirmed *why* — "fast" with no why is a vibe, not a
  contract a rebuild can honor; no why → incidental/🔓, never quality-bar. Anti-laundering applies
  **doubly** to `agreed-NFR`: only an *actively agreed* attribute is contract; an inferred one is incidental.
- **Swap-survivability (R70).** A contract item is stack-independent only when its `[E]` test is
  **black-box at the boundary** — invoke the surface, assert the observable output, never import
  internals — so the suite runs unchanged against a reimplementation (`/companion:cover` mechanizes it).
  Honesty ceiling (Hyrum's law): the *complete* contract is unenumerable — the claim is "the *agreed*
  contract survives, the rest is *declared* disposable," never "swapping is risk-free."
- **Redesign logs UX + quality ONLY (R55).** Feeding a `/companion:redesign`: log UX + quality
  attributes; safety-invariants route to a **check** (not a prose catalogue); technical/incidental is
  disposable. Don't build a technical-requirements catalogue.

This routing is what lets `advise`/`redesign` **regenerate against the contract** (R54), not just read
the ledger. Homes (R64): all contract docs live under `docs/`; a generated gate goes to
`.companion/check.sh`, never the repo root — detailed in step 4.

---

0. **Clear autopilot first.** If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`
   before anything else — while the flag is on, the ask-guard blocks `AskUserQuestion` and this
   command can't ask a single question. This is a **mechanical unblock** — **defer the R38 parked-pile
   review** until after this command; just note the ❓/⏳ count in one line, don't walk the pile first.

1. **Scan — read-only, no questions.** Detect the repo's structure **generically** (R9 — no
   language/framework allowlists; delegate recognition to the model, detect structure generically).
   Spawn a small panel of scanner sub-agents, each a distinct lens for what is **load-bearing *and*
   likely-undocumented**:
   - **the boundary, outside-in (R70)** — enumerate every input the system accepts and every
     output it emits at its edge: CLI surfaces + exit codes, file/store formats read or written,
     wire/injection shapes, env contracts — anything an external consumer (human *or* program)
     could depend on. This lens starts from the edge and works inward, where the others start
     from the code; it's what makes the recorded contract survive a full stack swap.
   - **invariants / constraints** the code clearly relies on (a single-writer, a dependency
     boundary, an ordering/idempotency assumption, an encoding that must match across readers);
   - **architectural / design choices** (why it's structured this way — a pattern chosen on purpose);
   - **technical requirements** (performance budgets, size limits, compatibility targets, data-safety);
   - **landmines** — code that *looks* removable or refactorable but is actually holding something
     up: the exact thing advise would delete. Weight these and the boundary lens highest.

   Give each lens the repo + the goal. **Run the panel in the background (R71):** spawn the
   scanners as background sub-agents, announce in one line that the scan is running and the owner
   can keep working, and end the turn — build the Pass-1 report when the results arrive (the
   triage in Pass 2 is the only part that needs the owner live). **Each must first read the
   existing ledger + `docs/` and skip
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
   boundary, budget, forbidden pattern, an invariant a test could assert), also emit a gate
   assertion / lint — the tier Claude can't ignore — alongside the ledger entry.

4. **Record each pick at its tier — in the docs advise already reads.**
   - **Executable check** → add the assertion to the project's own gate wherever it lives (its
     `check.sh` / lint / test script); if the repo has none, create **`.companion/check.sh`** (R64 —
     plugin-generated files never land at the repo root). Add a one-line ledger pointer to it.
     Verify it passes on the current tree before moving on.
   - **🔒 / 🔓 judgment constraint** → a **terse** `REQUIREMENTS.md` entry (R3 — dense, not an essay):
     the constraint · its **status** (🔒/🔓) · **provenance** (stated/inferred/unknown) · the **why**
     (or an explicit "why unknown"). If a decision touches an existing locked requirement, cite the
     R-ID (R5).
   - A **gotcha** belongs in `docs/LESSONS.md`; a **coined term** in `docs/GLOSSARY.md` (R37) — not
     the ledger. Keep the ledger to *requirements*.
   - **Route by R54 pillar** (the second axis): a confirmed **safety-invariant** → `docs/INVARIANTS.md`
     as an enumerated row + its check; a **UX-contract** item → the right **`docs/flows/<flow>.md`**
   spec (R66 machine shape) — a `steps:` line (what the consumer walks through, in order; for a
   machine-facing interface flow the steps ARE the I/O sequence — input accepted → output emitted →
   exit code), tagged in `tests:` as
   `[E]` (a resolving test name — black-box at the boundary for interface flows, R70) or `[S]`
   (👁 eyeball-only); if it exercises a recurring **convention**,
   add it to `docs/flows/_patterns.md` **once** and reference it by name from the flow (restating
   drifts). Keep the flows index `Slash commands (N)` count honest. An **owner-agreed quality
   attribute** → `docs/flows/_quality-bar.md` (or the flow's own `quality:` field; "would a redesign build
   differently?" filter); an **incidental** one → left disposable (a regen may change it), a 🔓 ledger
   pointer at most. Keep each fact in **one** canonical pillar doc (R2), cross-referenced by name.

5. **Close the loop.** Recap in a short table — *item → tier (check / 🔒 / 🔓 / dropped) → **pillar**
   (UX / NFR / invariant / incidental) → where recorded*. Then state plainly **what stayed 🔓** (the
   constraints with no real why) and **what's incidental** (disposable — a regen may redesign it):
   advise is now free to challenge the 🔓s and redesign the incidental, must not silently reverse the
   🔒s, and must reproduce the contract pillars. Only after this is advise standing on documented
   ground instead of guessing.
