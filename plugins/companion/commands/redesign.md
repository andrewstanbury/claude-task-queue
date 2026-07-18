---
description: Whole-application contract-preserving redesign — rebuild the app to satisfy the logged UX + quality-attribute contract, as a sequence of bounded, check-gated passes
---

Run a **redesign** (R55): rebuild the **whole application** from the logged contract, as a
**sequence of bounded, check-gated passes** — **never** one unbounded rewrite. The intent-driven
regeneration the owner asked for. It **edits**, so every guardrail is mandatory. **Prototype until
proven on a real rebuild — say so.**

The **logged** contract is `docs/UX.md` (experience) + `docs/NFR.md` (quality attributes). The
**safety invariants are the executable checks** (`docs/INVARIANTS.md` + `check.sh`) every pass must
keep green — not a prose catalogue the owner maintains. Reuses `/companion:regen` as the per-module
engine.

0. **Clear autopilot first.** This edits code and rests on the owner's explicit picks. If autopilot
   is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off` first — the ask-guard would otherwise
   block every confirmation this flow depends on.

D0. **Verify the invariant net covers the app BEFORE the first pass (R54 sequencing — non-negotiable).**
    A whole-app redesign regenerates *every* module, so any safety invariant that lacks a check — and
    isn't recognized per-module — gets silently deleted while `check.sh` stays green. That is the exact
    R54 footgun. Before starting: confirm **every** invariant in `docs/INVARIANTS.md` has a green check
    (or is an explicitly owner-acknowledged G3/G4 manual-preserve). **If any invariant is uncovered,
    STOP** — add the check first (`/companion:document` or by hand). Do not begin a whole-app redesign
    on an incomplete net; per-module R3 recognition is a backstop, not the gate.

D1. **Log the contract first — UX + quality attributes only.** Ensure `docs/UX.md` (the experience)
    and `docs/NFR.md` (the quality attributes) exist and are current. If missing/stale, run
    `/companion:document` to populate **just those two** (UX + QAs — *not* a technical-requirements
    catalogue; the safety net is the checks from D0, not prose). Confirm with the owner before any edit.

D2. **Enumerate the app as bounded targets.** Break the application into bounded modules
    (file/subsystem, generically per R9). Order **lowest-blast / fewest-dependents first** so an early
    failure is cheap. Present the plan (the ordered target list) before starting.

D3. **Redesign each module as a bounded pass — run `/companion:regen` on it (R1–R5).** For each target
    in order, drive the full regen flow: gate on green checks → regenerate against UX+QAs → apply on a
    branch → re-check → auto-revert on red. Present each recommendation-first, and **allow "this module
    already satisfies the contract — skip"** (the honest verdict, not a manufactured rewrite). **A
    reddened check STOPS that pass** (auto-revert that module); ask the owner whether to continue the
    run or halt. There is **never a single unbounded whole-app rewrite** — one bounded, reversible pass
    at a time.

D4. **Whole-run safety.** All passes land on a branch, never the default in place; `check.sh` stays
    green between passes; the owner reviews. When the run completes, drive the app's real behavior to
    confirm the **UX is reproduced end-to-end** (not just green tests), then hand off to
    `/companion:ship-it`. Never silent, never without the owner's go.
