# ROADMAP — the vibe-coding companion system

A living **design record**: the direction, the decisions, and what's next. The
version-by-version shipped history lives in [CHANGELOG.md](./CHANGELOG.md) so this
file stays lean (the project's own subtractive principle, applied to its own docs).

The goal of this marketplace is a set of Claude Code plugins that let you
**vibe-code an entire project** while Claude keeps it clean, well-documented,
token-efficient, and low-debt — **proactively, with minimal input** (pausing the
backlog is the one control you need).

Read [AGENTS.md](../AGENTS.md) first for the conventions and hard invariants that
constrain everything below.

## Prioritized criteria (in order)

1. **Optimize for Claude to read & maintain the project** — assume Claude does
   all the coding going forward.
2. **Token efficiency** — the plugins *and* the project being worked on.
3. **File sizes that match the complexity** of the product requirements.
4. **Follow the project's Quality Attributes**; if none are documented, document
   them *before* working on the project.
5. **Follow the recommended patterns** of the tech stack in use — and **flag
   outdated/deprecated tech within the touched scope** so cruft is modernized as
   you go, not left to rot.
6. **Streamlined plugins** — seamless, pausable, show the tasks being worked on,
   and process the backlog optimally (fan out to agents *or* auto-order the work).

**The first-class principle — contain blast radius.** Above the criteria sits one
organizing idea: **minimize and understand the blast radius of every change.**
Both *code* blast radius (what a touched file ripples into → surface dependents,
cover them with tests) and *architectural* blast radius (how far a change to the
plugins ripples → one owner per concern, contracts not copies). It's the
through-line the other criteria *serve*, not a rival to criterion 1 — a contained
change is cheaper to load, test, and reason about, so low blast radius is how 1–3
are achieved. Every plugin wires it in: tidy surfaces dependents and ties them to
tests, charter marks high-fan-in modules in the map, task-queue sequences
low-reach-first and keeps high-blast work off parallel agents.

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
mechanism**: a well-mapped, small-filed, clean, pattern-following project is cheap
for Claude to load and reason about. It accrues from 1/3/4/5 plus the already-lean
plugins.

## Architecture — four self-contained plugins, by responsibility

| Plugin | Responsibility | Serves |
|---|---|---|
| **task-queue** | **Orchestrate the work** — capture, order, advance, pause, show tasks | 6 |
| **tidy** | **Make each change safely & cleanly** — format/lint/TDD on touch, blast-radius, verification floor | 3, 5, TDD, tech-debt |
| **charter** | **Maintain the project's Claude manual** — QA gate, roadmap/backlog, project map, decisions anchor, stack notes, `/charter:align` | 1, 4 (feeds 2, 3, 5) |
| **hud** | **Show what's happening** — a consolidated, read-only status line over the others' state | 6 |

Single responsibility: **orchestrate / change-safely / know-the-project / show.**
Each plugin stays independently installable (the install boundary forbids shared
code — see AGENTS.md), Bash + `jq`, zero build, locality over decomposition.

## What each plugin does now

Version history → [CHANGELOG.md](./CHANGELOG.md).

- **task-queue** — SessionStart policy (native task list = live queue) +
  cross-session **resume bridge** + auto-advance + per-repo **pause** + opt-in
  **agent-mode** (fan independent tasks to subagents) + **roadmap/backlog
  hydration** + **alignment-aware capture** (weigh new work against the recorded
  direction) + schema-drift canary.
- **tidy** — on touch: format + lint (**Go, web, Python ruff, shell shellcheck** —
  fast file-scoped tools only) + TDD nudge + **size-vs-complexity** flag +
  **currency** (surface manifest pins, never auto-upgrade) + **blast-radius**
  (Go via the exact `go list` import graph, else a guarded `git grep`). On Stop:
  the **verification floor** runs the project's own tests and blocks until green.
  On demand: **`/tidy:distill`** (weight report) and **`/tidy:audit`**. Holds the
  **subtractive posture** (subtract as you add; reuse before create).
- **charter** — at SessionStart, a compact **proportional brief** that gates
  substantive work on the project's "Claude manual": **quality attributes**
  (Lighthouse-aligned defaults for web), **roadmap/backlog**, **project map**,
  **decisions/ADRs** (the alignment anchor), **stack notes** — detect-not-author
  (the model writes the docs), quiet once they're summarised in CLAUDE.md.
  On demand: **`/charter:align`** reconciles open/proposed work against the
  recorded decisions + roadmap.
- **hud** — a static **health beacon** + tasks + paused + agent-mode + the
  verification floor's **✓/✗ tests** + **docs-health** + last tidy +
  **context-window fill %** + branch & dirty-count + model. Read-only, no idle
  timer, zero model-token cost.

### Currency / modernization — why it's split model-vs-hook

Detecting "this is outdated" is **the model's job, not the hook's** — it's world
knowledge a hook can't have offline. So: the *judgment* is a currency clause in
tidy's standard (notice deprecated patterns / behind-latest versions in scope);
the *facts* are the **pinned versions from the nearest manifest**, surfaced on
touch, scoped to the touched area. Guardrail: **nudge, never auto-upgrade** (a dep
bump is the highest-blast-radius change there is). A network "latest stable" check
(`npm view …`) is **deliberately not done** — edit-time network calls would break
the offline, zero-per-prompt-cost posture. charter holds durable stack notes so
the judgment has context. Other "best practice" axes (security, a11y, performance)
aren't separate mechanisms — they're **quality attributes** documented via charter.

## Design principles (the durable decisions)

### Proportionality over maximalism

The deepest bias to resist: applying good practices *exhaustively* instead of *in
proportion to complexity/risk* — "test everything," "document everything," "nudge
on everything." charter emits one **compact, proportional brief** (baseline map +
what's-next always; QA for web; decisions/stack by judgment — *don't over-document
a small project*); tidy's standard is trimmed to anchors (inform, don't teach) and
frames tests as "verify where it earns its keep." Per-touch nudges stay terse,
failures first.

### Design model — verification + simplicity, not methodology labels

TDD / DDD / SOLID are different levels, not alternatives. For LLM-written code
owned by **non-technical** people, the leverage is **verification + simplicity**:

- **Tests are a safety net, not a ritual** — cover changed behavior; nothing's
  done until the suite is green. The **verification floor** (Stop hook runs the
  project's own tests, blocks until green, bounded) enforces this — the safety net
  a non-technical owner can't produce.
- **SOLID's essence, not the label**; **DDD's ubiquitous language only** (name
  code/docs in the owner's domain words); **complexity-proportional simplicity**
  (the simplest maintainable solution the requirement demands — no speculative
  layers).
- **Non-technical posture** — resolve technical findings autonomously (safe
  upgrades behind passing tests; delete provably-dead code; apply sensible
  defaults); only ask the owner about product/outcome choices, in plain language.

### The subtractive force + quiet hooks

The system optimises for *Claude to read & maintain* a project at low token cost
**over time**. Every mechanism must not only change cleanly but keep the project
*small*. Three primitives realise this:

1. **A maintained project map** — growth stays visible and loading stays cheap.
2. **A subtractive prune force** — touch-time (*subtract as you add*) and
   on-demand (`/tidy:distill`): *add requirement → net surface flat or smaller*.
3. **Bootstrap-once + drift-detect hooks** — record the standing policy in the
   project's `CLAUDE.md` (always loaded) and mark it `claude-companion`; the hook
   then re-anchors in **one line** instead of re-injecting the full policy.
   **State** (carry-over, hydration, drift) is never suppressed — only the policy
   prose. All SessionStart re-injectors are quiet-able.

### Direction & signal — clean ≠ correct

Changing cleanly and shedding cruft still doesn't guarantee a change is the
**right** change. Three disciplines:

1. **Alignment** — route charter's project-knowledge (decisions/ADRs, roadmap)
   into the orchestration loop: as work is captured and picked up, **weigh it
   against the documented direction** and surface drift/decision-contradictions
   *before* the work is done. Shipped as three arms: the decisions anchor
   (charter), alignment-aware capture (task-queue), and on-demand `/charter:align`.
2. **Feedback-loop disciplines** — the suite is a stack of loops at different
   latencies: **per-touch** → **on-stop** (verification floor) → **on-demand**
   (`/tidy:audit`, `/tidy:distill`, `/charter:align`) → **CI**. *The fastest loop
   that can catch a class of problem owns it* — push signal as close to the change
   as it'll go. (Edit-time linting is therefore limited to fast, file-scoped tools;
   slow whole-project linters stay with the verification floor.)
3. **Refined token philosophy — earn the token, don't just save it.** Not *fewest
   tokens* but *highest-leverage* tokens: the project map (sublinear vs.
   re-scanning the tree), policy-stated-once, conditional/silent hooks (cost zero
   unless they fire), quiet-mode. Build what raises signal-per-token over time;
   cut what raises cost without raising signal.

## Honest limits (what hooks can and can't do)

- Hooks **nudge; they don't enforce.** The QA "gate" is a strong instruction, not
  a hard block.
- **Agent fan-out** = nudging the model to use the Task tool (a hook can't spawn
  agents); it costs tokens, so it's opt-in.
- **Blast radius** = lightweight dependent-surfacing (`go list` / `git grep`),
  language-specific — not full static analysis.
- Plugins act **only within a Claude session** — no out-of-session daemon.
- Consistent with the token-efficiency, avoid-complexity, and
  read-only/conservative-mutation principles in AGENTS.md.

## Decided against

- **Consolidating the 4 plugins into 1** (2026-05-31) — the duplication isn't
  painful and the migration would disrupt a working install; revisit only if the
  duplication bites. *Not a pending item — recorded so it isn't re-litigated.*

## Status — 2026-06-01

- **task-queue 0.18.0** · **tidy 0.27.0** · **charter 0.14.0** · **hud 0.3.0**.
- **The planned roadmap (Phases 1–3) and the direction-&-signal layer are
  complete.** The system changes cleanly, sheds cruft, checks alignment, and lints
  across Go/web/Python/shell with a toolchain-accurate Go blast-radius.
- **What's next:** nothing planned — further work is **demand-driven** (a new
  stack to lint, an Expo/React-Native-Web QA profile, a pain point that surfaces),
  not new layers.
