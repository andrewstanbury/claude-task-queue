# UX — the user-experience contract (R54 contract, pillar a)

What the user **sees and does** with `companion` installed. This is what a ground-up `advise`
regen (R54) must **reproduce** — the *experience*, not the implementation. Descriptive (what is),
not prescriptive (the "why/priority" is the NFR contract, `docs/NFR.md`). **[E]** = enforced (code
runs/blocks, reliable) · **[S]** = steering (behavior Claude follows; real, not guaranteed).
Tied to a check where one exists (see `docs/INVARIANTS.md`).

**Status: confirmed 2026-07-17 (owner accepted [E]+[S] as-is).**

The catalog has two axes. **Happy paths** are the *journeys* — what the user walks through, in
order. **Design patterns** are the *recurring conventions* those journeys are built from — defined
**once**, and referenced **by name** from each step that uses one (a pattern is exercised at many
points; restating it would drift). Every row keeps its **[E]/[S]** kind and its check either way.

---

# Happy paths — the journeys

## Path 1 · First run (install → every session start)

| Step | Kind | Pattern | Check |
|---|---|---|---|
| Wire the status line once (`/companion:setup`) | [E] | — | — |
| Working agreement loads once per session (Claude queues/decides/cleans by the same rules) | [E] | *steering loads once* | `session start: injects STEERING …` |
| Earlier-session tasks in *this repo* re-surface (no cross-repo bleed) | [E] | — | `… resumes THIS repo's tasks only (scoped by .root)` |
| Repo gotchas (`LESSONS.md`) surface if present | [E] | — | — |
| After a compaction, the queue + next-pointer re-anchor (work continues, not drifts) | [E] | — | `re-anchors on a compaction with queue+pointer …` |
| A persistent status line appears: beacon · 🛡/✈️/📦 health · 📋/❓/⏳ queue · model · tokens · project · branch | [E] | *guardrails default-on* | `status line: renders …` |

## Path 2 · The core loop (request → queue → drain → ship)

| Step | Kind | Pattern | Check |
|---|---|---|---|
| A request becomes `tq` tasks (smallest-blast-first, each with a done-when) | [S]/[E] | *queue-one-at-a-time* | `tq: done-when …` |
| Worked one at a time, a breadcrumb on the active task | [S]/[E] | *queue-one-at-a-time* | `parked/blocked … prefix-view over pending` |
| Decisions surface as pick-from-CLI menus (+ a one-line brutal-honest verdict each reply) | [S] | *recommendation-first* | — |
| Context nudges offer next moves (debt · big blast · repetition · finished chunk) | [S] | *offer-not-act nudges* | — |
| Visual changes get a wireframe before code; work stays clean-as-you-go | [S] | *wireframe-first* · *clean-as-you-go* | — |
| A write that would commit a real credential is **blocked** with a message | [E] | *guardrails default-on* | `secret gate: blocks a real AWS key (exit 2)` |
| Verified by exercising, not asserting; recapped in one line | [S] | *clean-as-you-go* | — |
| A finished chunk ships: verify→commit→push→merge (`/companion:ship-it`) | [S] | — | — |

## Path 3 · Hands-off drain (autopilot → ship-mode)

| Step | Kind | Pattern | Check |
|---|---|---|---|
| `/companion:autopilot on` — Claude keeps draining the queue without stopping to ask | [E] | *offer-not-act nudges* | — |
| While on, asking is blocked and the drain auto-continues each turn | [E] | — | — |
| Ship-mode auto-commits each turn to an `autopilot/*` branch (never main, never pushed) | [E] | *guardrails default-on* | — |

## Path 4 · Pick up where you left off (`/companion:resume`)

| Step | Kind | Pattern | Check |
|---|---|---|---|
| `/companion:resume` step 1 — turns autopilot off, re-surfaces earlier-session tasks preserving their ❓/⏳/📋 class (absorbs the former `/companion:resume`, R39) | [E]/[S] | *recommendation-first* | `manual resume: turns autopilot OFF first …` |
| Then walk the parked/blocked pile one at a time, picks written back before new work | [S] | *recommendation-first* | — |

## Path 5 · Improve the design (advise → document → redesign)

| Step | Kind | Pattern | Check |
|---|---|---|---|
| `/companion:advise` — brutal-honest critique as options you pick one at a time, then queued (critique only, never edits) | [S] | *recommendation-first* | — |
| `/companion:document` — record load-bearing decisions, tagged by contract pillar (check › 🔒 › 🔓) | [S] | — | — |
| `/companion:redesign` — whole-app contract-preserving rebuild in bounded, check-gated passes; **runs `document` first**, and a single bounded target is just one pass (absorbs the former `regen`) (experimental) | [S] | *contract-preserving rebuild* | — |

---

# Design patterns — the recurring conventions

Each is defined **once here**; the happy-path steps above reference it by name.

| Pattern | Kind | What it is | Check |
|---|---|---|---|
| *recommendation-first* | [S] | Anything decision-shaped arrives as a recommendation-first pick-from-CLI menu (recommended option marked), and every reply closes with a one-line brutal-honest verdict. | — |
| *queue-one-at-a-time* | [S]/[E] | Requests become `tq` tasks, smallest-blast-first, each with a done-when, worked one at a time with a breadcrumb. The companion owns its store; deliberately not Claude's native tasks. | `tq: done-when …` |
| *wireframe-first* | [S] | A visual change gets a wireframe/ASCII sketch agreed before code. | — |
| *clean-as-you-go* | [S] | Weigh blast radius, subtract, YAGNI; verify by exercising, not asserting; recap in one line. | — |
| *offer-not-act nudges* | [S] | Context nudges are **offers, not actions**: debt → task · big blast → split · repetitive drain → autopilot · finished chunk → ship-it. | — |
| *contract-preserving rebuild* | [S] | `redesign` reproduces the logged UX + NFR contract, gated on the safety checks, applied on a branch — the experience is preserved, the implementation may change (a single bounded target is one pass). | — |
| *guardrails default-on* | [E] | Safety features (secret gate, status-line health, ship-mode's never-main) are on by default and opt-out only; disabling the secret gate warns loudly. | `secret gate: blocks a real AWS key (exit 2)` |

---

# Reference (the enumerable anchors)

## The task queue (`tq`)

Reprints on every change. `add · doing · note · done · cancel · list · report`. The spine the
user watches. See *queue-one-at-a-time* above.

## Slash commands (7)

`/companion:setup` (wire status line) · `/companion:autopilot` (keep-draining, enforced when on) ·
`/companion:ship-it` (verify→commit→push→merge) · `/companion:resume` (re-surface earlier-session
tasks + walk the parked pile — absorbs the former `review`) · `/companion:advise` (brutal-honest critique
as options — critique only, never edits) · `/companion:redesign` (whole-app contract-preserving rebuild in
bounded, check-gated passes; runs `document` first, a single target is one pass — absorbs the former
`regen`; experimental) · `/companion:document` (record load-bearing decisions, tagged by contract pillar).

## Configuration the user controls

- **Autopilot / ship** toggle via `/companion:autopilot` (`on|off`, and `ship on|off`). | [E] |
- **Secret gate / steering** are on by default; disable per-repo via a hand-written `<feature>=off`
  flag file (the `/companion:features` CLI was removed 2026-07-18, R50) — the flag mechanism + the
  gate's read of it are unchanged. | [E] |
- Ship-mode: autopilot auto-commits each turn to an `autopilot/*` branch (never main, never pushed). | [E] |
- Global override: `CLAUDE_COMPANION_SECSCAN=0` (CI escape hatch, wins everywhere). | [E] |

---

*Reproduction bar for a regen: every **[E]** row must hold (its check green); every **[S]** row is
the intended behavior the steering layer must still produce. Reshaping the catalog (paths vs
patterns) never drops a row or its check. The "why each of these matters / at what priority" lives
in the NFR contract, not here.*
