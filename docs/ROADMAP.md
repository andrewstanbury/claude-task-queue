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

The ordering is tuned for the system's real target: **existing, often legacy,
under-tested, under-documented projects that must stay clean *as they grow*.** The
forces that contain debt lead; the intent loop and the payoff follow. (This list
supersedes the older flat six-criteria ranking — those criteria survive, re-seated
under the layers below.)

**0. Keep the project self-describing — and its growth visible.** *(precondition)*
Maintain the project's *"Claude operating manual"* — project map, quality
attributes, recorded decisions/ADRs, stack notes — and keep growth **observable**
with a size guard. You can't contain ripple in a project you can't load, or prune
cruft you can't see. Bootstrap it if missing; **gate substantive work on it
existing.** The manual is for Claude, but keep a thin **plain-language owner layer**
too — *what this is, how it works, how to run it* — so a non-technical owner isn't
locked to one Claude session (the bus-factor safety net). (charter authors/keeps the
manual; tidy's size guard keeps growth visible.)

**1. Contain blast radius — per change *and* as a system trend.** Minimize and
understand the blast radius of every change: *code* ripple (what a touched file
flows into) and *architectural* ripple (how far a structural change reaches). This
is the primary safety net when tests/specs don't exist *and* the bound on where you
clean up. At scale it has a second level — watch that **total coupling isn't
climbing** as features land (one owner per concern, contracts not copies, low
fan-in), because **compounding debt is a blast-radius-*at-scale* problem**. tidy
surfaces dependents (Go `go list` / guarded `git grep`), charter marks high-fan-in
modules in the map, task-queue sequences low-reach-first and keeps high-blast work
off parallel agents.

**2. Verify + stay aligned — the Steward intent loop.** The safety net the
**non-technical owner can't produce**, so Claude must. Establish and **confirm
intent in the owner's plain language** (ask only about product/outcome, never
implementation); build the simplest thing that meets it; **characterize before you
change** (no tests → pin the affected surface's current behavior first — blast
radius says what to pin, so coverage accrues on the worked surface); **verify
against that intent** (suite green before done — the verification floor enforces
it); and **weigh the work against recorded decisions** so it's the *right* change,
not merely a clean one.

**3. Subtract as you add.** The anti-entropy rule: a new requirement leaves net
surface **flat or smaller** — reuse before create, delete what the change makes
redundant. Without it, a project of individually-clean changes still grows
*monotonically* into debt. Applied at touch-time (tidy's subtractive posture) and
on-demand (`/tidy:distill`).

**4. Periodic deliberate prune — for what touch-time bounding skips.** "Clean as
you touch, bounded by blast radius" converges only the *active* surface (untouched
stable code is left alone — refactoring ripple you can't see is itself a top rework
risk). Cross-module and rarely-touched debt therefore accrues invisibly; a
scheduled, **characterized** audit/prune pass (`/tidy:audit` + `/tidy:distill`)
catches it. Large pre-existing architectural debt needs this deliberate pass, not
incremental nibbling.

**Cross-cutting (applied throughout, not a step):**

- **Proportionality** — every practice scaled to complexity/risk, never exhaustive.
- **Follow the stack's recommended patterns** — and **flag outdated/deprecated tech
  within the touched scope**, so cruft is modernized as you go, not left to rot.
- **Streamlined orchestration** — seamless, pausable, shows the work, processes the
  backlog optimally (fan out to agents *or* auto-order the work).
- **Token efficiency (the payoff — named so it isn't forgotten).** Not *fewest*
  tokens but *highest-leverage* ones: a well-mapped, small-filed, clean,
  pattern-following project is automatically cheap for Claude to load and reason
  about. It **accrues from 0–4** plus the already-lean plugins — *don't chase it
  directly* (that's what causes under-testing and under-documenting).

**Through-line:** reduce tech debt as you go; bake **blast-radius awareness +
verify-against-intent + subtract-as-you-add** into every change — and run a
deliberate prune for what incremental work can't reach.

## Unifying insight

The list has **one root and one payoff.** The root is **#0**: most of what "good"
means — loadable, right-sized, quality-attribute-driven, pattern-following — is just
*the project describing itself well*. That's the same discipline this repo gives
itself (AGENTS.md + CONTRACT + checks + size guard), created and kept current
**automatically** for whatever project Claude is pointed at. The payoff is **token
efficiency**: not a separate mechanism but the consequence of 0–4 plus the
already-lean plugins — a well-mapped, small-filed, clean project is cheap for Claude
to load and reason about.

## Architecture — four self-contained plugins, by responsibility

| Plugin | Responsibility | Serves |
|---|---|---|
| **task-queue** | **Orchestrate the work** — capture, order, advance, pause, show tasks | 1 (sequence low-reach-first), orchestration |
| **tidy** | **Make each change safely & cleanly** — format/lint/TDD on touch, blast-radius, verification floor | 1, 2, 3, 4 (+ size guard for 0) — the change-time engine |
| **charter** | **Maintain the project's Claude manual** — QA gate, roadmap/backlog, project map, decisions anchor, stack notes, `/charter:align` | 0, 2 (alignment arm) |
| **hud** | **Show what's happening** — a consolidated, read-only status line over the others' state | visibility (0 growth), orchestration |

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

- **Tests are a safety net, not a ritual — and verification must be *observable*.**
  Cover changed behavior; nothing's done until the suite is green (the
  **verification floor** — Stop hook runs the project's own tests, blocks until
  green, bounded — is the net a non-technical owner can't produce). But green is
  proof for *Claude*, not the owner: on user-visible changes, **demonstrate it
  working and recap in plain language** (`/run`, `/verify`) — a non-technical owner
  verifies by *seeing* it work, not by reading test names, and trust comes from a
  working demo, not a checkmark they can't interpret.
- **SOLID's essence, not the label**; **DDD's ubiquitous language only** (name
  code/docs in the owner's domain words); **complexity-proportional simplicity**
  (the simplest maintainable solution the requirement demands — no speculative
  layers); and **boring & reversible by default** — prefer mainstream, replaceable
  tech and decisions that can be backed out, because architecture here gets *no
  human review* (blast radius + the prune pass are its only checks) and the owner
  can't recover from an irreversible or exotic choice.
- **Non-technical posture — autonomy on the reversible, consent on the
  consequential.** Resolve safe/reversible findings autonomously (formatting, safe
  upgrades behind passing tests, delete provably-dead code, sensible defaults). But
  the dividing line that matters here is **reversibility + cost + data-safety, not
  technical-vs-product**: before anything consequential or hard to undo — a **paid**
  dependency, an **irreversible data migration/deletion**, **vendor lock-in** — get
  a plain-language heads-up-and-yes first, even though it's "technical." The owner
  can't consent to what they can't see, or recover from what they didn't choose.

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
- **A charter doc-inventory state file as a runtime single-source-of-truth**
  (2026-06-01) — proposed to stop the charter↔hud↔task-queue detection mirrors
  drifting. Rejected: the install boundary forces each consumer to keep a fallback
  detector anyway, so the inventory is *net-additive* (doesn't remove the
  duplication) and adds a mid-session staleness lag. Chose the cheaper, subtractive
  alternative — a **CI drift-guard test** (`tests/drift-guard.bats`).

## Status — 2026-06-01

- **task-queue 0.20.0** · **tidy 0.29.1** · **charter 0.14.0** · **hud 0.3.1**.
- **The planned roadmap (Phases 1–3) and the direction-&-signal layer are
  complete.** The system changes cleanly, sheds cruft, checks alignment, and lints
  across Go/web/Python/shell with a toolchain-accurate Go blast-radius.
- **What's next:** nothing planned — further work is **demand-driven** (a new
  stack to lint, an Expo/React-Native-Web QA profile, a pain point that surfaces),
  not new layers.
