---
description: Recommend the ideal tests for the UX contract — rank critical user-experience paths by criticality × coverage gap, propose the test to write for each (one at a time, recommendation-first), and queue your picks. Recommends only — never writes test files.
---

Run a **cover**: decide which user experiences are critical enough to deserve a durable safety net,
and for each recommend the *ideal test to write* — the test-recommendation arm of the living
contract (R58). It is the coverage twin of `/companion:advise`: advise critiques the design, cover
critiques the **test coverage of the UX contract**. Target is `$ARGUMENTS` (a path/pattern name, or
free-text scope); with none, cover the **whole UX contract** (`docs/UX.md`).

**cover recommends, it never writes.** It proposes tests and queues the ones you pick as `tq`
tasks — it does **not** emit test files (the owner writes tests manually, or a later task does). This
is deliberate: which experiences are worth a test is a judgment the owner owns, and a test written
without that buy-in is noise. It's judgment + workflow, not enforcement (R28) — it proposes, you
choose. Owner-present by nature (it asks): run it with autopilot **off**. It reuses the
`/companion:advise` recommendation-first loop — don't build a second machine.

**Governing idea — a test earns its place only as a *durable* safety net.** Mirror the STEERING
rule (R48/R51): recommend a real test **only** where the experience is critical *and*
un-eyeball-able *and* currently unguarded — never as a per-path ritual. A green `check` already
covering a path is coverage; don't recommend a second one. License cover to conclude "the critical
paths are already covered — write nothing": a manufactured test recommendation is worse than
silence.

---

0. **Clear autopilot first.** If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`
   before anything else — the ask-guard blocks `AskUserQuestion` while it's on, and this command
   asks. (Mirrors `/companion:advise` / `/companion:document`.)

1. **Read the contract + the current net.** Read `docs/UX.md` (the UX paths + patterns — each row's
   `[E]`/`[S]` kind and its `Check` column) and `docs/INVARIANTS.md` (the executable checks that
   already exist). Detect the repo's **test setup generically** (R9 — no framework allowlist:
   delegate recognition to the model, find the test runner/idiom by structure). Restate in one line
   what you're covering and against what contract.

2. **Rank by criticality × coverage gap.** For each UX path / design pattern, score two axes:
   - **Criticality** — blast-radius of it silently breaking (a safety/irreversible step ranks
     highest; a cosmetic `[S]` nicety lowest). An `[E]` row that guards against harm outranks an
     `[S]` convenience.
   - **Coverage gap** — is there already a green check for it (the `Check` column / `INVARIANTS.md`)?
     Fully-checked → gap 0 (skip it). No check + un-eyeball-able → gap high.

   The recommend-worthy set is **high criticality × high gap**. Drop everything already covered and
   everything a person can just eyeball. If nothing survives, say so in one line and stop.

3. **For each survivor, recommend the ideal test — one at a time, recommendation-first.** In
   criticality order (number them "N of M", carry picks forward), present a **single
   `AskUserQuestion`** whose options are concrete test *shapes* for that path — best pick first and
   marked `(Recommended)`. Each option names **what it asserts**, the **idiom** it'd be written in
   (the repo's own runner), and its **cost** (a brittle end-to-end vs a cheap unit assertion). Always
   offer:
   - **"Write my own / different assertion"** (the free-text `Other`) — the owner describes the test.
   - **"Not worth a test — leave it to eyeball / steering"** → record nothing for that path.
   - **"Defer"** → leave it for next time (a big pile is never a forced march).

   State, per path, *why this test and not more* — the one durable behaviour it pins that nothing
   else guards.

4. **Queue the picks — recommend, don't write.** For each chosen test, `tq add` a task describing
   the test to write, its target path, and its acceptance (`--done "<the assertion that must hold>"`)
   — smallest-blast first. If a path's ideal guard is actually an **executable check** (a boundary an
   `INVARIANTS.md` row + `check.sh` assertion could hold), say so and route it there instead of a
   test file — the tier Claude can't ignore. **Don't write any test or check now** — cover produces a
   queue, not edits.

5. **Close the loop.** Recap in a short table — *UX path → criticality × gap → recommended test (or
   "already covered" / "eyeball only") → where queued*. Then state plainly which critical paths remain
   **unguarded by choice** (the owner declined a test) so the gap is visible, not silent.
