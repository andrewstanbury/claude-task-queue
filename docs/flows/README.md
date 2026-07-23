# flows — the UX contract (R54 pillar a · machine shape per R66)

Claude-consumed spec: what the user sees/does per flow. A ground-up `redesign` must reproduce these.
Shape (R66, reverses R62's human-first pages): one dense spec per flow — `when · why [R-IDs] · steps ·
quality · tests · changes`. `why` = anti-reversal provenance (what the feature is for + ledger trace).
Change interface: the owner states an experience change in conversation → edit that flow's spec
(steps + tests + a dated `changes:` line) in the same turn [pattern:living-contract].

tests grammar (R61 gate, enforced by check.sh):
- `- [E] ` + backtick test-name → must resolve to a real bats `@test` title, else the build FAILS
- `- [S] … 👁` → judgment, eyeball-only, skipped (honest gaps stay visible, not failed)

## flows
- [first-run](./first-run.md) — install → every session start
- [core-loop](./core-loop.md) — request → queue → drain → ship
- [hands-off-drain](./hands-off-drain.md) — autopilot → ship-mode
- [pick-up-where-you-left-off](./pick-up-where-you-left-off.md) — resume → review
- [carry-tasks-to-another-machine](./carry-tasks-to-another-machine.md) — export → pull → resume
- [improve-the-design](./improve-the-design.md) — advise → docs → redesign → cover
- [patterns](./_patterns.md) · [quality-bar](./_quality-bar.md)

## Slash commands (10)
`/companion:setup` (wire status line) · `/companion:autopilot` (keep-draining, enforced when on) ·
`/companion:ship-it` (verify→sync flows→commit→push→merge, on the `ship.sh` rail R71) ·
`/companion:handoff` (mid-flight checkpoint → pushed `wip/*` branch + queue, no gate, R72) ·
`/companion:resume` (session pickup) ·
`/companion:review` (walk ❓+⏳ backlog recommendation-first; autopilot-off trigger; `decompose:`
parks run as context interviews, R65) · `/companion:advise` (critique-only options) ·
`/companion:redesign` (contract-preserving rebuild, check-gated passes; runs `docs` first) ·
`/companion:docs` (record load-bearing decisions by pillar) · `/companion:cover` (recommend →
scaffold flow tests).

## config
- autopilot/ship/decisive via `/companion:autopilot` (`on|off`, `ship on|off`, `decisive on|off` [R59]) [E]
- secret gate/steering on by default; per-repo `<feature>=off` flag file (features CLI removed, R50) [E]
- global: `CLAUDE_COMPANION_SECSCAN=0` (CI escape, wins everywhere) [E]
