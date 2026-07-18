# UX — the user-experience contract (R54 contract, pillar a)

What the user **sees and does** with `companion` installed. This is what a ground-up `advise`
regen (R54) must **reproduce** — the *experience*, not the implementation. Descriptive (what is),
not prescriptive (the "why/priority" is the NFR contract, `docs/NFR.md`). **[E]** = enforced (code
runs/blocks, reliable) · **[S]** = steering (behavior Claude follows; real, not guaranteed).
Tied to a check where one exists (see `docs/INVARIANTS.md`).

**Status: confirmed 2026-07-17 (owner accepted [E]+[S] as-is).**

## Automatic (zero user action)

| Experience | Kind | Check |
|---|---|---|
| Working agreement loads once per session (Claude queues/decides/cleans by the same rules) | [E] | `session start: injects STEERING …` |
| Earlier-session tasks in *this repo* re-surface at start (no cross-repo bleed) | [E] | `… resumes THIS repo's tasks only (scoped by .root)` |
| Repo gotchas (`LESSONS.md`) surface if present | [E] | — |
| After a compaction, the queue + next-pointer re-anchor (work continues, not drifts) | [E] | `re-anchors on a compaction with queue+pointer …` |
| A write that would commit a real credential is **blocked** with a message | [E] | `secret gate: blocks a real AWS key (exit 2)` |
| A persistent status line: beacon · 🛡/✈️/📦 health · 📋/❓/⏳ queue · model · tokens · project · branch | [E] | `status line: renders …` |

## How Claude behaves (the steering layer)

| Experience | Kind |
|---|---|
| Requests become `tq` tasks (smallest-blast-first, each with a done-when), worked one at a time | [S] |
| Decisions arrive as **recommendation-first pick-from-CLI menus** (recommended option marked) + a one-line brutal-honest verdict every reply | [S] |
| Context nudges (offers, not actions): debt → task · big blast → split · repetitive drain → autopilot · finished chunk → ship-it | [S] |
| Visual changes → wireframe first; clean-as-you-go (blast radius, subtract, YAGNI); verify by exercising | [S] |

## The task queue (`tq`) — the spine the user watches

Reprints on every change. `add · doing · note · done · cancel · list · report`. The companion owns
its store; deliberately not Claude's native tasks.

## Slash commands (8)

`/companion:setup` (wire status line) · `/companion:autopilot` (keep-draining, enforced when on) ·
`/companion:ship-it` (verify→commit→push→merge) · `/companion:resume` (re-surface + triage earlier
tasks) · `/companion:review` (walk the parked pile) · `/companion:advise` (brutal-honest critique
as options) · `/companion:document` (record load-bearing decisions) · `/companion:features`
(toggle enforced-core capabilities per repo).

## Configuration the user controls

- Per-repo toggles via `/companion:features`: **secret · steering · autopilot · ship** (disabling
  the secret gate warns loudly). | [E] |
- Ship-mode: autopilot auto-commits each turn to an `autopilot/*` branch (never main, never pushed). | [E] |
- Global override: `CLAUDE_COMPANION_SECSCAN=0` (CI escape hatch). | [E] |

---

*Reproduction bar for a regen: every **[E]** row must hold (its check green); every **[S]** row is
the intended behavior the steering layer must still produce. The "why each of these matters / at
what priority" lives in the NFR contract, not here.*
