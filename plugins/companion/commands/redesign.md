---
description: Whole-application contract-preserving redesign — rebuild the app to satisfy the logged UX + quality-attribute contract, as a sequence of bounded, check-gated passes (runs docs first)
---

Run a **redesign** (R55): rebuild the **whole application** from the logged contract, as a
**sequence of bounded, check-gated passes** — **never** one unbounded rewrite. The intent-driven
regeneration the owner asked for. It **edits**, so every guardrail is mandatory. **Prototype until
proven on a real rebuild — say so.**

The **logged** contract is `docs/flows/` (experience) + `docs/flows/_quality-bar.md` (quality attributes). The
**safety invariants are the executable checks** (`docs/INVARIANTS.md` + `check.sh`) every pass must
keep green — not a prose catalogue the owner maintains. The **per-module rebuild engine is inlined
below** (D3) — it was the standalone `/companion:regen`, folded into redesign 2026-07-18 (owner
sign-off): a bounded single-target rebuild only ever ran as one redesign pass, so it lives here now.

0. **Clear autopilot first.** This edits code and rests on the owner's explicit picks. If autopilot
   is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off` first — the ask-guard would otherwise
   block every confirmation this flow depends on. (Never leave a code-editing gate resting on
   advisory prose + a side-effect of another hook.)

D0. **Verify the invariant net covers the app BEFORE the first pass (R54 sequencing — non-negotiable).**
    A whole-app redesign regenerates *every* module, so any safety invariant that lacks a check — and
    isn't recognized per-module — gets silently deleted while `check.sh` stays green. That is the exact
    R54 footgun. Before starting: confirm **every** invariant in `docs/INVARIANTS.md` has a green check
    (or is an explicitly owner-acknowledged G3/G4 manual-preserve). **If any invariant is uncovered,
    STOP** — add the check first (`/companion:docs` or by hand). Do not begin a whole-app redesign
    on an incomplete net; per-module R3 recognition is a backstop, not the gate.

D1. **Log the contract first — `/companion:docs` is a REQUIRED first step (R41/R55).** The
    redesign rebuilds against the *logged* UX + quality attributes, so those must exist and be current
    before a single module is touched. **Run `/companion:docs` first** to record/refresh
    `docs/flows/` (the experience) + `docs/flows/_quality-bar.md` (the quality attributes) — **just those two**, not a
    technical-requirements catalogue (the safety net is the checks from D0, not prose). **Refuse to
    proceed** if the contract is missing or stale and the owner declines to log it: a redesign with no
    contract to preserve is an unbounded rewrite, exactly what this command forbids. `docs` stays
    its own command (it also feeds `/companion:advise`); redesign *requires* it, doesn't replace it.

D2. **Enumerate the app as bounded targets.** Break the application into bounded modules
    (file/subsystem, generically per R9). Order **lowest-blast / fewest-dependents first** so an early
    failure is cheap. Present the plan (the ordered target list) before starting.

D3. **Redesign each module as a bounded, check-gated pass (the inlined engine, R1–R5).** For each
    target in order, drive the full per-module flow — never a single unbounded whole-app rewrite:

    - **R1 · Bound it.** The pass target is one module (file / subsystem) from D2 — never the whole
      repo at once; the blast radius must stay isolable by the checks.
    - **R2 · Load the contract.** Read `docs/flows/` (the user-facing behavior this module must
      reproduce), `docs/flows/_quality-bar.md` (the quality attributes to meet — *and* what's explicitly
      **incidental**, so fair to change), and `docs/INVARIANTS.md` (the must-holds touching it).
    - **R3 · Checks first, or stop (R54, non-negotiable).** Identify every invariant check touching
      the module and run the project's gate (`./check.sh` or `.companion/check.sh`, wherever it
      lives — R64). **Refuse to regenerate** the module if any relevant invariant
      check is **missing or red** — an unpinned invariant is exactly what a rebuild silently deletes;
      add the check first, don't proceed. List the **manual-preserve** items (G3 `tq` atomicity /
      G4 never-commit-default — no full check) and require the owner to acknowledge them; do not let
      "the checks catch it" imply full coverage.
    - **R4 · Regenerate against the contract.** Rebuild the module from scratch with the objective:
      *minimize implementation surface, subject to (reproduce the flows ∧ meet the quality bar ∧ preserve
      every invariant + manual-preserve item).* Incidental implementation (tech/structure — e.g. the
      bash/jq/≤300 choice the quality bar marks disposable) is fair to change. Present recommendation-first:
      the rebuilt module + a diff + which contract item each part satisfies + your brutal-honest read
      — including *"this module already satisfies the contract — skip,"* an allowed, encouraged verdict.
    - **R5 · Confirm, apply on a branch, re-check.** Only on the owner's explicit pick: apply on a
      branch (never the default in place), then **re-run the gate. If ANY check reddens, STOP,
      auto-revert that module on the branch, and report** — never present red work as done, never
      leave red work for the owner to clean up. Then drive the module's real behavior to confirm the
      UX is *reproduced*. **A reddened check STOPS that pass**; ask the owner whether to continue the
      run or halt.

D4. **Whole-run safety.** All passes land on a branch, never the default in place; the gate stays
    green between passes; the owner reviews. When the run completes, drive the app's real behavior to
    confirm the **UX is reproduced end-to-end** (not just green tests), then hand off to
    `/companion:ship-it`. Never silent, never without the owner's go.
