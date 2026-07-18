---
description: Contract-preserving ground-up regeneration of ONE bounded target — rebuild it to satisfy the logged UX + quality-attribute contract, gated on the safety checks and applied on a branch
---

Run a **regen** (R54): rebuild a single bounded target from the ground up so it still satisfies the
recorded contract, treating the existing implementation as disposable. Unlike `/companion:advise`
(read-only critique), regen **edits** — so every guardrail below is **mandatory, not optional**.
`$ARGUMENTS` is the target. **Still a prototype until proven on a real rebuild — say so when you run it.**

The **logged** contract is `docs/UX.md` (experience) + `docs/NFR.md` (quality attributes); the
**safety net** is the existing checks (`docs/INVARIANTS.md` + `check.sh`) — not a prose catalogue —
that the rebuild must keep green.

0. **Clear autopilot first.** regen edits code, and its safety rests on the owner's explicit picks
   (R3/R5). If autopilot is on, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off` before anything
   else — while it's on the ask-guard blocks the confirmations this flow depends on. (Mirrors
   `/companion:document` + `/companion:review`; never leave a code-editing gate resting on advisory
   prose + a side-effect of another hook.)

R1. **Bound it or refuse.** `<target>` must be a single file / module / subsystem. **Refuse a
    whole-repo regen** — the blast radius is unbounded and the checks can't isolate it (that's what
    `/companion:redesign` does, in bounded passes). No target → ask for one.

R2. **Load the contract.** Read `docs/UX.md` (the user-facing behavior the target must reproduce),
    `docs/NFR.md` (the quality attributes it must meet — *and* what's explicitly **incidental**, so
    fair to change), and `docs/INVARIANTS.md` (the must-holds).

R3. **The gate — checks first, or stop (R54, non-negotiable).** Identify every invariant check that
    touches the target and run `./check.sh`. **Refuse to regen** if any relevant invariant check is
    **missing or red** — an unpinned invariant is exactly what a regen silently deletes; the fix is
    to *add the check first* (`/companion:document` or by hand), not to proceed. Then list the
    **manual-preserve** items and require the owner to acknowledge them: some invariants have **no
    check** (G4 — R45's never-commit-default guard) or only a *textual* one (G3 — `tq` atomicity),
    so `check.sh` will **not** catch their loss. Say this plainly — do not let "the checks catch it"
    imply full coverage; for these, the owner's acknowledgement is the only guard.

R4. **Regenerate against the contract.** Redesign the target from scratch with the objective:
    *minimize implementation surface, subject to (reproduce the UX rows ∧ meet the NFRs ∧ preserve
    every invariant + manual-preserve item).* The incidental implementation (tech, structure — e.g.
    the bash/jq/≤300 choice `NFR.md` marks disposable) is fair to change. Use an independent panel as
    in critique. Present recommendation-first: the regenerated target + a diff + which contract item
    each part satisfies + your brutal-honest read — including *"the current version is already the
    best achievable — don't regen,"* an allowed and encouraged verdict.

R5. **Confirm, then apply on a branch — check-gated (R54).** Only on the owner's explicit pick:
    create a branch (never edit the default in place), apply the regen, then **re-run `./check.sh`.
    If ANY check reddens, STOP, **auto-revert the change on the branch**, and report the failure —
    never present red work as done, never leave red work sitting for the owner to clean up.** Then
    drive the target's real behavior to confirm the UX is *reproduced* (not just that tests pass).
    Never silent, never whole-repo, never without the owner's go.
