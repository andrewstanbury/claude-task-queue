---
description: Recommend then scaffold the ideal tests for the flow contract — rank critical user flows by criticality × coverage gap, propose the test for each (one at a time, recommendation-first), and write the picks as golden/happy-path tests in the project's own runner, named so each flow's Tests line resolves through the anti-drift gate.
---

Run a **cover**: decide which user experiences are critical enough to deserve a durable safety net,
and for each **recommend the ideal test then scaffold the picks** — the test arm of the living
contract (R58, R61). It is the coverage twin of `/companion:advise`: advise critiques the design,
cover critiques the **test coverage of the UX contract**. Target is `$ARGUMENTS` (a path/pattern
name, or free-text scope); with none, cover the **whole flow contract** (`docs/flows/`).

**cover recommends *which* experiences deserve a test, then writes the ones you pick (R61).** The
buy-in still comes first — which experiences are worth a durable test is the owner's judgment, and a
test written without that buy-in is noise — so cover **asks before it writes**, one at a time,
recommendation-first. On a pick it then **scaffolds the test** (was: queued a "write this later"
task): a **black-box, happy-path/golden test in the project's OWN runner** (R9 — detect the runner
generically, never a companion-specific harness), driving the *user-visible* surface described in the
flow's `steps:`, and **named so the flow's `Tests` line resolves** — the test's `@test`/it
title is exactly the backtick name the flow page's `- [E] `<name>`` line carries, which the anti-drift
gate (R61) matches to a real title. It's judgment + workflow, not enforcement (R28) — it proposes, you
choose, it writes what you chose. Owner-present by nature (it asks): run it with autopilot **off**. It
reuses the `/companion:advise` recommendation-first loop — don't build a second machine.

**Golden mechanics — native-first, generic (R61).** A scaffolded golden test *drives* the flow
through the entry point in its `steps:`, captures the **user-visible output**, writes it to a
golden fixture (`goldens/<flow>.*` or the runner's own snapshot idiom) on first run, and **diffs** on
later runs; refresh via the project's own update flow (`jest -u`, `--snapshot-update`, etc. — delegate
to the model, don't invent one). There is **no separate ID** — the link IS the test's title (the flow
page's `Tests` line names it). **Honest ceiling:** a golden proves the output hasn't *silently
changed*, not that it's *correct* — and `[S]` judgment lines stay eyeball-only (👁), never scaffolded.

**Governing idea — a test earns its place only as a *durable* safety net.** Mirror the STEERING
rule (R48/R51): recommend a real test **only** where the experience is critical *and*
un-eyeball-able *and* currently unguarded — never as a per-path ritual. A green `check` already
covering a path is coverage; don't recommend a second one. License cover to conclude "the critical
paths are already covered — write nothing": a manufactured test recommendation is worse than
silence.

---

0. **Clear autopilot first.** If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`
   before anything else — the ask-guard blocks `AskUserQuestion` while it's on, and this command
   asks. (Mirrors `/companion:advise` / `/companion:docs`.)

1. **Read the contract + the current net.** Read the `docs/flows/` pages (each flow's `steps:` +
   its `Tests` lines — `[E]` with a resolving test name, `[S]` eyeball-only) and `docs/INVARIANTS.md`
   (the executable checks that already exist). Detect the repo's **test setup generically** (R9 — no
   framework allowlist: delegate recognition to the model, find the test runner/idiom by structure).
   Restate in one line
   what you're covering and against what contract.

2. **Rank by criticality × coverage gap.** For each flow (or a convention in `_patterns.md`), score two axes:
   - **Criticality** — blast-radius of it silently breaking (a safety/irreversible step ranks
     highest; a cosmetic `[S]` nicety lowest). An `[E]` step that guards against harm outranks an
     `[S]` convenience.
   - **Coverage gap** — is there already a green check for it (a resolving `- [E]` Tests line /
     `INVARIANTS.md`)? Fully-checked → gap 0 (skip it). No check + un-eyeball-able → gap high.

   The recommend-worthy set is **high criticality × high gap**. Drop everything already covered and
   everything a person can just eyeball. If nothing survives, say so in one line and stop.

3. **For each survivor, recommend the ideal test — one at a time, recommendation-first.** In
   criticality order (number them "N of M", carry picks forward), present a **single
   `AskUserQuestion`** whose options are concrete test *shapes* for that flow — best pick first and
   marked `(Recommended)`. Each option names **what it asserts**, the **idiom** it'd be written in
   (the repo's own runner), and its **cost** (a brittle end-to-end vs a cheap unit assertion). Always
   offer:
   - **"Write my own / different assertion"** (the free-text `Other`) — the owner describes the test.
   - **"Not worth a test — leave it to eyeball / steering"** → record nothing for that flow.
   - **"Defer"** → leave it for next time (a big pile is never a forced march).

   State, per flow, *why this test and not more* — the one durable behaviour it pins that nothing
   else guards.

4. **Scaffold the picks — in the project's own runner (R61).** For each chosen test, `tq add` it
   (smallest-blast first, `--done "<the assertion that must hold>"`) **and then write it**: a
   black-box happy-path/golden test that drives the flow's `steps:` entry point, asserts the
   user-visible result (snapshot to a golden where the output is large/structured, an inline
   assertion where it's small), and whose **title is exactly the name the flow's `- [E] `<name>`` line
   references** (R61 gate). Use the repo's own runner + idiom (R9) — detect it, don't impose one. Add
   (or flip to green) that `- [E]` line on the flow page once the test passes; if you only queued the
   test, leave the flow's Tests unchanged so coverage isn't overstated. If a flow's ideal guard is
   actually an **executable check** (a boundary an `INVARIANTS.md` row + `check.sh` assertion could
   hold), route it there instead — the tier Claude can't ignore. **Run the new test before moving on**
   (a scaffolded test that doesn't pass on today's code isn't coverage, it's a false alarm).

5. **Close the loop.** Recap in a short table — *flow → criticality × gap → recommended test (or
   "already covered" / "eyeball only") → where queued*. Then state plainly which critical flows remain
   **unguarded by choice** (the owner declined a test) so the gap is visible, not silent.
