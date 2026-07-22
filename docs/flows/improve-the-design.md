# flow:improve-the-design
when: critique, document, rebuild, or add coverage to what's built
why: improvements run against a written contract, not memory — else they silently reverse undocumented choices [R29 R41 R54]

steps:
- `/companion:advise` — brutal-honest critique as options picked one at a time, then queued; critiques ONLY, never edits [pattern:recommendation-first]
- `/companion:docs` — record load-bearing decisions tiered check › 🔒 › 🔓, routed by contract pillar; produces flow specs (this contract) + ledger entries
- `/companion:redesign` — whole-app contract-preserving rebuild, bounded check-gated passes; runs `docs` first; single target = one pass (absorbed `regen`) [pattern:contract-preserving-rebuild; experimental]
- `/companion:cover` — rank flows by criticality × coverage gap → recommend then SCAFFOLD picked tests (black-box golden/happy-path, project's own runner, named to resolve the R61 gate) [pattern:recommendation-first, living-contract]

quality:
- judgment + workflow, not enforcement — propose · owner picks · record
- owner-present (they ask) — autopilot OFF; reuse advise loop, no second machine
- cover writes only what the owner picked — buy-in first

tests:
- [S] advise critiques one-at-a-time, never edits — judgment 👁
- [S] docs records at highest reliable tier, provenance-tagged — judgment 👁
- [S] redesign rebuilds against logged contract, check-gated — judgment 👁
- [S] cover recommends-then-scaffolds, gap-honest — judgment 👁

changes:
- 2026-07-22 machine shape [R66; reverses R62] · why-line provenance
- 2026-07-20 from UX.md P5 [R62]; cover now scaffolds (amends R58·d)
