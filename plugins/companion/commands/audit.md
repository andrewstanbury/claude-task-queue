---
description: Audit the whole project for cleanliness (size, debt, blast-radius hotspots) and queue the fixes
---

Do an on-demand, whole-project cleanliness audit — the deliberate complement to the
per-edit clean-as-you-touch hook. This is read-only analysis; queue the work, don't do it
inline.

Run these passes over the repo (skip vendored/generated dirs — `node_modules`, `dist`,
`build`, `.git`, lockfiles):

1. **Oversized files** — source files over the size budget
   (`CLAUDE_COMPANION_SIZE_BUDGET`, default 300 lines). List the worst offenders.
2. **Scar tissue (debt magnets)** — files the project has *repeatedly had to fix*, via the
   git rework ratio: for each file, `fix`/`revert`-flavored commits ÷ total commits touching
   it; flag those ≥ ~0.34 with ≥ 2 reworks. These are where debt concentrates.
3. **Blast-radius hotspots** — files with many dependents (widely referenced), where a change
   ripples far. High fan-in + oversized + scar-tissue is the top-priority cleanup.
4. **Performance hot paths** *(judgment, no engine allowlist)* — recognise realtime/per-frame
   or hot-loop code generically and flag likely regressions; route anything you can't measure
   statically to a before/after profile rather than guessing.

Then **queue every finding as a `tq` task**, smallest blast-radius first
(`tq add "<fix>"`), parking anything genuinely risky or ambiguous as `❓ [parked] <decision>`.
Give the owner a one-line plain-language summary of what you queued. Don't start the fixes
unless they say go (this is an audit, not a sweep — ratchet, never sweep).
