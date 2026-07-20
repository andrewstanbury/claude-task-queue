# Flows — the user-experience contract (R54 pillar a · R62 shape)

What the user **sees and does** with `companion` installed — **one readable page per user flow**,
not a table. This is the human-collaboration-first shape (R62): you change the experience by
*talking to Claude about a flow*, and Claude edits that flow's page (happy path + tests + Changes)
in step. A ground-up `redesign` (R54) must reproduce these flows; the *why/priority* lives in each
flow's **Quality bar** + the global [`_quality-bar.md`](./_quality-bar.md) (the old `NFR.md`, slimmed).

**How to read a flow page**
- **Happy path** — the journey, in order, in plain language (what the user sees/does).
- **Quality bar** — the quality attributes that constrain *this* flow (the demoted NFR).
- **Tests** — each line is `[E]` (enforced — carries a backtick test name the **R61 gate** resolves
  to a real `@test`) or `[S]` (steering/judgment — eyeball only, 👁, never a test).
- **Changes** — the running log of decisions about this flow, *attached to the flow* (the durable
  home for "we changed X because Y" — no longer scattered in chat).

**How to change a flow:** tell Claude the experience change; it edits the one flow page's Happy path,
updates/scaffolds the Tests (`/companion:cover`), appends a Changes line, and the gate keeps the
Tests ↔ real-tests link honest. Recurring conventions live once in [`_patterns.md`](./_patterns.md),
referenced by name.

## The flows
- [First run](./first-run.md) — install → every session start
- [The core loop](./core-loop.md) — request → queue → drain → ship
- [Hands-off drain](./hands-off-drain.md) — autopilot → ship-mode
- [Pick up where you left off](./pick-up-where-you-left-off.md) — resume → review
- [Carry tasks to another machine](./carry-tasks-to-another-machine.md) — export → pull → resume
- [Improve the design](./improve-the-design.md) — advise → document → redesign → cover
- [Conventions (patterns)](./_patterns.md) · [Quality bar (global)](./_quality-bar.md)

## Slash commands (9)
`/companion:setup` (wire status line) · `/companion:autopilot` (keep-draining, enforced when on) ·
`/companion:ship-it` (verify→sync flows→commit→push→merge) · `/companion:resume` (re-surface
earlier-session tasks — session pickup) · `/companion:review` (walk the parked ❓ + blocked ⏳
backlog, recommendation-first; the autopilot-off trigger) · `/companion:advise` (brutal-honest
critique as options — critique only, never edits) · `/companion:redesign` (whole-app
contract-preserving rebuild in bounded, check-gated passes; runs `document` first — absorbs the
former `regen`; experimental) · `/companion:document` (record load-bearing decisions, tagged by
contract pillar) · `/companion:cover` (recommend then scaffold the ideal test per critical flow).

## Configuration the user controls
- **Autopilot / ship / decisive** via `/companion:autopilot` (`on|off`, `ship on|off`,
  `decisive on|off` — R59: auto-decide reversible, park only irreversible). `[E]`
- **Secret gate / steering** on by default; disable per-repo via a hand-written `<feature>=off` flag
  (the `/companion:features` CLI was removed 2026-07-18, R50). `[E]`
- **Global override:** `CLAUDE_COMPANION_SECSCAN=0` (CI escape hatch, wins everywhere). `[E]`
