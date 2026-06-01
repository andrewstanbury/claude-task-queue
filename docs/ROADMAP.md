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
| **charter** (shipped) | **Maintain the project's Claude manual** — quality-attributes gate, roadmap/backlog file, project map; stack notes + prune force planned | 1, 4 (feeds 2, 3, 5) |
| **hud** (shipped, MVP) | **Show what's happening** — a consolidated, read-only status line over the other plugins' state | 6 (the "show the tasks" half) |

Single responsibility: **orchestrate / change-safely / know-the-project.** Each
plugin stays independently installable (the install boundary forbids shared code
— see AGENTS.md), Bash + `jq`, zero build, locality over decomposition.

## Plugins

### task-queue — *orchestrate* (shipped)
- **Now:** SessionStart policy + cross-session resume + auto-advance + per-repo
  pause + conditional capture nudge + schema-drift canary + **roadmap/backlog
  hydration** (when the repo has a committed `docs/ROADMAP.md`/`BACKLOG.md`, the
  resume bridge nudges the model to adopt its open Now/Next items into the live
  task list — the orchestration half of charter's roadmap file; read-only, no
  parsing, full-context only).
- **Shipped (Phase 2 — agent-mode, 0.14.0):** an **opt-in agent-mode toggle**
  (`tq-agent.sh on|off`, mirroring pause) — when ON, the SessionStart policy
  permits fanning **independent** tasks (unblocked, no shared `blockedBy`,
  non-conflicting files) out to subagents via the Task tool; OFF by default for
  token efficiency. The independent-vs-chained detection is the model's, from its
  task list's `blockedBy`. State signal + command discovery ride along.
- **Shipped (alignment-aware capture, 0.16.0):** the conditional capture nudge —
  which already fires only on multi-step work with an empty queue — now also
  **weighs the work against the project's recorded direction** when it fires: if
  the repo has decisions/ADRs or a roadmap/backlog, it names them and asks the
  model to flag drift or decision-contradictions *before* capturing. This is the
  **second arm of the alignment thread** (the orchestration counterpart to
  charter 0.12.0's decisions anchor): charter holds the direction, task-queue
  weighs captured work against it. Self-contained detection (decisions path added
  to `lib/project.sh`, duplicated from charter per the install boundary), and
  **zero added per-prompt cost** — the docs are resolved only on the rare firing
  path, never on the silent majority of prompts.

### tidy — *change safely & cleanly* (shipped)
- **Now:** format + lint + TDD nudge on touch, ratchet posture, tidy-doctor,
  payload-drift canary, and the **subtractive posture** (prune force, touch-time
  half): *subtract as you add* — delete what a change makes redundant, **reuse
  before create**, prefer the smaller surface so net complexity trends down. The
  on-demand whole-project pass (**`/tidy:distill`**: a read-only weight report —
  file/line counts, heaviest + over-budget files, cruft markers, junk artefacts —
  that drives the model's subtractive judgment on dead code, duplication, and
  doc↔code drift) is now shipped too. **Size-vs-complexity is automatic** (no
  manual trigger): a touched file over the line budget (`CLAUDE_TIDY_SIZE_BUDGET`,
  default 400) is flagged for decomposition on edit, and over-budget files also
  surface on their own at session start (a *light distill*, quiet unless there's
  drift). Disable with `CLAUDE_TIDY_SIZE_CHECK=0`.
- **Shipped (web edit-time linters, 0.9.0):** on touch, surface the project's own
  **eslint** (incl. jsx-a11y) / **stylelint** findings for web files — *findings
  only, no `--fix`* — shifting Lighthouse's a11y/best-practices audit to edit
  time. Acts only when the project has the linter; silent otherwise. This is the
  enforcement layer behind charter's web quality-attribute defaults.
- **Shipped (currency/modernization, 0.10.0):** on touch, surface the nearest
  manifest's **pinned versions** (package.json/go.mod/…) once per manifest per
  session, with a nudge to flag deprecated/behind-latest tech — facts from the
  hook, judgment from the model, **never an auto-upgrade**. `CLAUDE_TIDY_CURRENCY=0`
  to disable.
- **Shipped (blast-radius, 0.11.0):** for a touched source file, `git grep`
  surfaces approximate **importers/dependents** (`~N files reference X`) so a
  change's affected surface gets test coverage — a grep heuristic, guarded and
  deduped. `CLAUDE_TIDY_BLAST=0` to disable. Realises *no change lands without a
  test and an understanding of what it can break.*
- - **Shipped (Go-aware blast-radius, 0.16.0):** for Go files the blast-radius keys
  on the **package import path** (module from go.mod + relative dir), not the
  basename — what other packages actually import. Non-Go keeps the basename
  heuristic.
- **Planned (Phase 3):** broader multi-stack pattern linting.

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
- **Shipped (roadmap/backlog):** charter now maintains a committed,
  **Claude-facing roadmap/backlog file** (`docs/ROADMAP.md` / `ROADMAP.md` /
  `docs/BACKLOG.md`, override `CLAUDE_CHARTER_ROADMAP_FILE`) — the cross-session,
  cross-engineer record of *what's next*. **Missing →** instruct the model to
  generate it from git history + the codebase (assumptions flagged); **present →**
  read it and reconcile against recent git history before substantive changes.
  The team isn't on GitHub Issues/Projects, so this committed file (versioned by
  git = the shared audit trail) is the coordination point across machines.
  *Detect-not-author:* the hook stays read-only; the model writes the file.
- **Shipped (web best-practices, "shift the audit left"):** when charter detects
  a **web project** (framework dep / `index.html` / web config; override
  `CLAUDE_CHARTER_WEB=1|0`) and QA is undocumented, the nudge seeds
  **Lighthouse-aligned defaults** — Core Web Vitals budgets, accessibility
  (WCAG AA, jsx-a11y/stylelint at edit time), SEO, responsive + **print CSS**,
  **progressive enhancement**, and **components-by-default** (prefer components
  over raw elements; reuse existing before creating new). Best practices become
  *designed-in*, not audited after — Lighthouse/CI is a backstop, not the rework
  loop. (This realises the "a11y/perf/security are quality attributes" stance
  below.) The library-agnostic component principle also feeds the **prune force**
  (reuse-before-create = anti-duplication).
- **Shipped (project map):** charter maintains a compact, committed
  **`file → responsibility` map** (`docs/MAP.md` / `MAP.md` /
  `ARCHITECTURE.md`, override `CLAUDE_CHARTER_MAP_FILE`) so a session **orients
  from the map instead of re-scanning the tree** — the biggest token lever for an
  AI maintainer (the map grows sublinearly, the tree doesn't). The orientation
  nudge now points at the map (it *replaced* the old generic "record learnings"
  line, so SessionStart didn't grow). Recognises an existing `ARCHITECTURE.md`
  rather than re-nagging. Same detect-not-author boundary.
- **Shipped (decisions + quiet, 0.6.0):** a **decisions/ADR dimension**
  (`DECISIONS.md` / `docs/adr/` / `docs/decisions/`) — present → consult before
  reversing a choice, missing → capture the evident ones — so Claude doesn't
  re-litigate or contradict past decisions; **ADRs untangled from the QA gate**
  (they're decisions, not quality attributes). **Quiet-mode:** the
  `claude-companion` marker drops charter's recurring honor/consult reminders
  (keeping the gap nudges), so charter goes silent once the docs are summarised
  in CLAUDE.md.
- **Shipped (decisions = the alignment anchor, 0.12.0):** the explicit "consult
  before reversing a choice" instruction — which the 0.10.0 compact-brief refactor
  had genericized into a flat "consult as relevant" list — is **restored and named
  as the alignment anchor** (*clean ≠ correct*: a well-made change can still
  contradict a recorded decision). This is the first arm of the *direction &
  signal* layer and what alignment-aware task-queue capture weighs work against
  (shipped as task-queue 0.16.0 — see above). Still full-context-only and
  quiet-able (standing policy lives in CLAUDE.md).
- **Done:** consolidated the orientation nudge here from task-queue (charter
  owns project-knowledge) — a local integration shakeout found it duplicated
  charter's documentation nudge at SessionStart.
- **Shipped (roadmap reconcile, 0.7.0):** when a roadmap is present, charter
  surfaces the last few **non-merge commit subjects** next to it so reconciliation
  is concrete ("recently merged: … — mark done what landed") rather than an
  abstract "reconcile against git history."
- **Shipped (stack notes, 0.8.0):** a **stack dimension** — detect STACK.md / a
  "## Stack" section; missing → capture languages/frameworks/versions from the
  manifests, present → consult. Durable context for currency/modernization.

## Proportionality over maximalism (2026-05-31)

The deepest bias found: applying good practices *exhaustively* instead of *in
proportion to complexity/risk* — "test everything", "document everything" (five
charter docs for any repo), "nudge on everything", "build everything". The fix is
to generalise the complexity-proportional-simplicity principle to docs, nudges,
and scope. Shipped: charter 0.10.0 emits one **compact, proportional brief** —
baseline (map + what's-next) always, quality attributes only for web, decisions/
stack left to the model's judgment ("don't over-document a small project"); the
tidy standard was trimmed to anchors (inform, don't teach) and reframed tests as
"verify where it earns its keep". Advisory per-touch nudges stay on but terser,
failures first.

## Design model (challenged + chosen 2026-05-31)

TDD / DDD / SOLID are different levels, not alternatives. For LLM-written code
owned by **non-technical** people, the leverage is **verification + simplicity**,
not methodology labels. Chosen model (tidy 0.12.0):

- **Tests are a safety net, not a ritual** — "cover changed behavior with a
  passing test; nothing's done until the suite is green" (test-first is a default,
  not a gate). The verification floor (run the project's checks) enforces green.
- **SOLID's essence, not the label** — already in tidy's clean-code/architecture
  clause; no OO-shaped formalism.
- **DDD's ubiquitous language only** — name code/docs in the owner's domain words
  so non-technical contributors can follow; skip bounded-contexts/aggregates.
- **Complexity-proportional simplicity** — the simplest maintainable solution the
  requirement demands; no speculative patterns/layers (counters methodology
  theater and nudge-sprawl).

**Shipped (verification floor, tidy 0.13.0):** a **Stop hook** runs the project's
*own* discoverable test command (package.json / go / pytest / cargo / Makefile, or
explicit `CLAUDE_TIDY_TEST_CMD`) when the tree is dirty, and **blocks until the
tests pass** — bounded to a few attempts, then allows the stop with a visible
warning. This is the safety net a non-technical owner can't produce, and it's the
project-checks runner that subsumes per-language test integration. (Per-language
*lint* handlers beyond Go/web remain superseded by this discover-and-run posture.)

**Decided against (2026-05-31):** consolidating the 4 plugins into 1 — the
duplication isn't yet painful and the migration would disrupt a working install;
revisit only if the duplication bites.

Still open: the plugin **consolidation** decision (4→1). *(Test-file exemption
shipped — tidy 0.15.0 for the size nudge, 0.23.0 for the light-distill.)*

**Shipped (non-technical posture, tidy 0.14.0 + charter 0.9.0):** resolve
technical findings autonomously (apply safe patch/minor upgrades behind passing
tests; delete provably-dead code with tests as the guardrail; charter applies
sensible defaults instead of 'flag for review'); only ask the owner about
product/outcome choices, in plain language; recap each unit of work in
non-technical terms.

## Strategic direction — the subtractive force + quiet hooks

The system optimises for *Claude to read & maintain* a project at low token cost
**over time**. The gap (surfaced 2026-05-31): every mechanism so far is
**additive and reactive-on-touch** — it makes changes cleanly but never makes the
project *smaller*. For "a project sheds cruft as requirements grow," two missing
primitives, now the priority ahead of the older Phase 2/3 sequencing:

1. **A maintained project map** (✅ shipped above) — so growth is visible and
   loading stays cheap. The other two read from it.
2. **A subtractive *prune* force** — ✅ shipped, both halves: touch-time (tidy
   0.5.0: *subtract as you add*) and on-demand (**`/tidy:distill`**, tidy 0.7.0:
   read-only whole-project weight report → model's subtractive judgment).
   Deferred: richer per-touch surfacing once blast-radius lands. This turns
   *add requirement → add code* into *add requirement → net surface flat or smaller*.
3. **Hooks: re-injection → bootstrap-once + drift-detect** — ✅ MVP shipped for
   the two pure-policy re-injectors (task-queue 0.13.0, tidy 0.6.0). Convention:
   record the standing policy in the project's `CLAUDE.md` (always loaded) and
   mark it `claude-companion`; the hook then re-anchors in **one line** instead
   of re-injecting the full policy — **state (carryover, hydration, drift) is
   never suppressed**, only the policy prose. When the marker is absent, the full
   nudge carries a one-line tip to bootstrap it. Now extended to **charter**
   (0.6.0) too — the marker drops its honor/consult reminders and it goes silent
   when everything is documented. All three SessionStart re-injectors are quiet-able.

Invariants hold throughout: zero per-prompt cost, self-contained plugins,
native-first, conservative mutation.

## The next layer — direction & signal (2026-05-31)

The strategic gap above (additive/reactive) is closed: the system now changes
cleanly *and* sheds cruft. What it still can't guarantee is that a change is the
**right** change and that the **signal** steering it is high-quality. Three
disciplines, in priority order:

### 1. Alignment — clean ≠ correct

Every force so far makes a change *clean* (tested, small, documented, current);
none checks it's *aligned with intent*. A well-made change can still be the wrong
thing, contradict a past decision, or drift from what's-next. The missing force
routes charter's project-knowledge (quality attributes, **decisions/ADRs**,
roadmap) into the orchestration loop: **as work is captured and picked up, weigh
it against the documented direction** — surface drift and decision-contradictions
*before* the work is done, not at review. This is "know the project" (charter)
feeding "orchestrate" (task-queue); the two open arms are charter's
CONTEXT/ADR/decisions awareness and alignment-aware capture in task-queue. Same
boundaries: read-only detection, model judgment, zero per-prompt cost.

### 2. Feedback-loop disciplines — tighten the loop, audit the skills

The suite is a stack of feedback loops at different latencies: **per-touch**
(format/lint/currency/blast-radius), **on-stop** (the verification floor — tests
must pass), **on-demand** (`/tidy:audit` assess, `/tidy:distill` cut), and **CI**
(the backstop). The discipline: *the fastest loop that can catch a class of
problem owns it* — push signal as close to the change as it'll go
(touch > stop > on-demand > CI), so nothing waits for review that a hook could
have said at edit time.

Skills audit (the on-demand `/` commands, 2026-05-31): **tidy** ships `audit`
(read-only assess) and `distill` (subtractive, edits) — they share the
weight-report header but differ in mandate, so not redundant; **hud** ships
`setup`; **task-queue** ships none. The gap the audit surfaced — no on-demand
**alignment check** — is now **closed: `/charter:align` (charter 0.13.0)**
reconciles open/proposed work against the recorded decisions + roadmap on demand
(`charter-align.sh` emits the deterministic anchors — decisions path, roadmap
path, recently-landed commits — and the command does the reconciliation), the
on-demand counterpart to alignment-aware capture (task-queue 0.16.0). Read-only,
model-judged, zero per-prompt cost (a `/` command, not a hook). Keep the set
small and non-overlapping: each command earns its slot the same way each nudge
earns its tokens.

### 3. Refined token philosophy — earn the token, don't just save it

"Token efficiency #1" was read too literally as *fewest tokens* (which argues for
cutting every nudge). Refit: **every token must earn its keep, in proportion to
its leverage over the project's life.** The wins were never about saying less —
they were about the *highest-leverage* tokens: the **project map** (sublinear,
replaces re-scanning the tree), **policy-stated-once** (not re-injected per turn),
**conditional/silent hooks** (cost zero unless they fire), and **quiet-mode**
(drop the prose once it's in CLAUDE.md — never the live state). This dissolves the
efficiency-vs-build-everything tension: build what raises signal-per-token over
time; cut what raises cost without raising signal. Proportionality (above) is the
same rule applied to docs, nudges, and scope.

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

- **task-queue 0.16.0**, **tidy 0.24.0**, **charter 0.13.0**, **hud 0.2.0** — shipped.
- **Phase 1 (charter MVP)** done; **hud** (status line) added; **charter 0.3.0**
  added the roadmap/backlog file, **0.4.0** the project map (orientation → map),
  and **0.5.0** web best-practices defaults (Lighthouse-aligned QA, "shift the
  audit left"). **task-queue 0.12.0** hydrates the live queue from the committed
  roadmap/backlog; **tidy 0.5.0** added the prune force's touch-time half; and
  **task-queue 0.13.0 + tidy 0.6.0** add bootstrap-then-quiet hooks (policy in
  CLAUDE.md → one-line re-anchor); **tidy 0.7.0** adds `/tidy:distill` and
  **tidy 0.8.0** makes size-vs-complexity automatic (per-touch + a light distill
  at session start — no manual trigger); **charter 0.6.0** adds the decisions/ADR
  dimension and quiet-mode. Then the rest of the roadmap landed: **tidy 0.9.0**
  web edit-time linters, **0.10.0** currency/modernization, **0.11.0**
  blast-radius (Phase 3); **task-queue 0.14.0** opt-in agent-mode (Phase 2); and
  **charter 0.7.0** roadmap reconcile. **The planned roadmap is essentially
  complete.** Remaining nice-to-haves only: broader
  multi-stack pattern linting, and a language-aware blast-radius (e.g. `go list`)
  over today's grep heuristic.
- **What's next** is the new strategic layer above (*The next layer — direction &
  signal*): **alignment** (clean ≠ correct — charter's decisions/roadmap feeding
  task-queue capture), **feedback-loop disciplines** (tighten the loop; close the
  on-demand alignment-check gap the skills audit found), and the **refined token
  philosophy** (earn the token, don't just save it). The mechanism is mostly
  built; this layer is about steering it.
