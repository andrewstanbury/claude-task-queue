# Improve the design

**When:** you want to critique, document, rebuild, or add test coverage to what you've built.

## Happy path
1. `/companion:advise` — brutal-honest critique of a target as options you pick one at a time, then queued. Critiques only, never edits. *(uses [recommendation-first](./_patterns.md))*
2. `/companion:document` — record load-bearing decisions, tagged by contract pillar (check › 🔒 › 🔓), so `advise` stops guessing and can't reverse an undocumented choice. Produces **flow pages** (this contract) + ledger entries.
3. `/companion:redesign` — whole-app contract-preserving rebuild in bounded, check-gated passes; runs `document` first; a single bounded target is one pass (absorbs the former `regen`). *(uses [contract-preserving rebuild](./_patterns.md); experimental)*
4. `/companion:cover` — recommend then **scaffold** the ideal test for each critical flow (ranked by criticality × coverage gap), as a black-box golden/happy-path test in the project's own runner, tagged to the flow so the R61 gate resolves it. *(uses [recommendation-first](./_patterns.md), [living-contract](./_patterns.md))*

## Quality bar
- These are **judgment + workflow, not enforcement** — they propose, you choose, they record.
- Owner-present by nature (they ask questions) — meant for autopilot **off**; they reuse the `advise` recommendation-first loop, not a second machine.
- `cover` writes only what you pick — buy-in first; a test written without it is noise.

## Tests
- [S] `advise` critiques recommendation-first, one at a time, never edits — judgment, eyeball only. 👁
- [S] `document` records at the highest reliable tier, provenance-tagged — judgment, eyeball only. 👁
- [S] `redesign` rebuilds against the logged contract in check-gated passes — judgment, eyeball only. 👁
- [S] `cover` recommends then scaffolds, gap-honest — judgment, eyeball only. 👁

## Changes
- 2026-07-20 — migrated from UX.md Path 5 into a flow page (R62). `cover` now **scaffolds** the picked tests (was recommend-only — amends R58·d).
