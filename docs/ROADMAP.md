# ROADMAP — the vibe-coding companion system

A living design record. The goal of this marketplace is a set of Claude Code
plugins that let you **vibe-code an entire project** while Claude keeps it clean,
well-documented, token-efficient, and low-debt — **proactively, with minimal
input** (pausing the backlog is the one control you need).

Read [AGENTS.md](../AGENTS.md) first for the conventions and hard invariants that
constrain everything below.

## Prioritized criteria (in order)

1. **Optimize for Claude to read & maintain the project** — assume Claude does
   all the coding going forward.
2. **Token efficiency** — the plugins *and* the project being worked on.
3. **File sizes that match the complexity** of the product requirements.
4. **Follow the project's Quality Attributes**; if none are documented, document
   them *before* working on the project.
5. **Follow the recommended patterns** of the tech stack / frameworks in use —
   and **flag outdated/deprecated tech within the touched scope** (versions
   behind latest stable, deprecated APIs/architecture, stale tests) so cruft is
   modernized as you go, not left to rot.
6. **Streamlined plugins** — seamless, pausable, show the tasks being worked on,
   and process the backlog optimally (fan out to agents *or* auto-order the work).

**Through-line:** reduce tech debt as you go; bake **TDD + blast-radius
awareness** into every change.

## Unifying insight

Criteria **1, 3, 4, 5 collapse to one root**: the project being vibe-coded needs
its own *"Claude operating manual"* — a maintained project map + quality
attributes + stack patterns + file-size norms — and substantive work should be
**gated on it existing**. This is the same discipline this repo gives itself
(AGENTS.md + CONTRACT + checks + size guard), created and kept current
**automatically** for whatever project Claude is pointed at.

Criterion **2 (project token efficiency) is the *payoff*, not a separate
mechanism**: a well-mapped, small-filed, clean, pattern-following project is
cheap for Claude to load and reason about. It accrues from 1/3/4/5 plus the
already-lean plugins.

## Architecture — three self-contained plugins, by responsibility

| Plugin | Responsibility | Serves |
|---|---|---|
| **task-queue** (shipped) | **Orchestrate the work** — capture, order, advance, pause, show tasks | 6 |
| **tidy** (shipped) | **Make each change safely & cleanly** — format/lint/TDD on touch, ratchet | 3, 5, TDD, blast-radius, tech-debt |
| **charter** (shipped, MVP) | **Maintain the project's Claude manual** — quality-attributes gate now; map/architecture/stack notes planned | 1, 4 (feeds 2, 3, 5) |
| **hud** (shipped, MVP) | **Show what's happening** — a consolidated, read-only status line over the other plugins' state | 6 (the "show the tasks" half) |

Single responsibility: **orchestrate / change-safely / know-the-project.** Each
plugin stays independently installable (the install boundary forbids shared code
— see AGENTS.md), Bash + `jq`, zero build, locality over decomposition.

## Plugins

### task-queue — *orchestrate* (shipped)
- **Now:** SessionStart policy + cross-session resume + auto-advance + per-repo
  pause + conditional capture nudge + schema-drift canary + orientation nudge.
- **Planned (Phase 2):** smarter backlog — detect independent vs chained tasks;
  an **opt-in agent-mode toggle** (like pause) that fans parallel tasks out to
  subagents when beneficial, defaulting to inline for token efficiency.

### tidy — *change safely & cleanly* (shipped)
- **Now:** format + lint + TDD nudge on touch, ratchet posture, tidy-doctor,
  payload-drift canary.
- **Planned (Phase 3):** **blast-radius awareness** (surface a symbol's
  dependents before you change it, so TDD covers the affected surface);
  file-size-vs-complexity nudge; multi-stack pattern linting; and
  **currency/modernization** — flag deprecated/outdated tech in the touched
  scope. Identity going forward: *no change lands without a test and an
  understanding of what it can break.*

#### Currency / modernization (how it works)

Detecting "this is outdated" is **the model's job, not the hook's** — it's world
knowledge (e.g. "RN's old architecture is deprecated," "this version is behind")
that a hook can't reliably know offline. So:
- **Judgment (engine):** a *currency* clause in tidy's standard — when you touch
  code, notice deprecated patterns / behind-latest versions / stale tests in
  scope and flag modernization.
- **Facts (assist):** on touch, surface the **declared versions from the nearest
  manifest** (`package.json`, `go.mod`, …) so the model judges against what's
  actually pinned. **Scoped to the touched area — never a whole-project scan.**
- **Guardrails:** **nudge, never auto-upgrade** (a framework/dep bump is the
  highest-blast-radius change there is — hence its pairing with blast-radius);
  scoped; deduped once per concern per session.
- **Limit:** "latest stable" leans on the model's training-cutoff knowledge
  (approximate); an optional network check (`npm view …`) is deferred.
- **charter** holds the persistent stack + modernization notes so this judgment
  has durable context.

Other "industry best practice" axes — **security, accessibility, performance** —
are *not* separate mechanisms: they're **quality attributes**, documented and
honored via `charter` (criterion 4). Currency is the one that's distinct because
it's *temporal* and model-knowledge-driven, so it gets named explicitly.

### charter — *know the project* (MVP shipped, Phase 1)
- **Shipped (MVP):** at SessionStart, if the project has no documented **quality
  attributes** (e.g. `QUALITY.md` / NFRs / ADRs), **nudge to document them before
  substantive changes** (source-aware, lean on compact); honor-reminder when
  documented; `charter-doctor`.
- **Done:** consolidated the orientation nudge here from task-queue (charter
  owns project-knowledge) — a local integration shakeout found it duplicated
  charter's documentation nudge at SessionStart.
- **Planned:** bootstrap/maintain the project map + architecture/stack notes.

## Honest limits (what hooks can and can't do)

- Hooks **nudge; they don't enforce.** The QA "gate" is a strong instruction,
  not a hard block.
- **Agent fan-out** = nudging the model to use the Task tool (a hook can't spawn
  agents). It costs more tokens, so it's opt-in, never the default.
- **Blast radius** = lightweight dependent-surfacing (grep / language tooling
  like `go list`), language-specific — not full static analysis.
- Plugins act **only within a Claude session** — no out-of-session daemon.
- These are consistent with the token-efficiency, avoid-complexity, and
  read-only/conservative-mutation principles in AGENTS.md.

## Phased plan (in priority order)

1. **Phase 1 — `charter` MVP** (criteria 1 + 4). The root that unlocks 1–5. ✅ **done** (charter 0.1.0)
2. **Phase 2 — task-queue smart backlog + agent-mode toggle** (criterion 6).
3. **Phase 3 — tidy blast-radius + size-vs-complexity + multi-stack patterns**
   (criteria 3, 5, and the through-line).
4. **Criterion 2 accrues continuously** from the above + the already-lean plugins.

Each phase is its own PR cycle, MVP-first, so complexity stays bounded. Do not
build it all at once.

## Status — 2026-05-31

- **task-queue 0.11.0**, **tidy 0.4.0**, **charter 0.2.0**, **hud 0.1.0** — shipped.
- **Phase 1 (charter MVP)** done; **hud** (status line, criterion 6 "show the
  tasks") added. Next: **Phase 2** (task-queue smart backlog + agent-mode), then
  **Phase 3** (tidy blast-radius + size-vs-complexity + currency/modernization).
