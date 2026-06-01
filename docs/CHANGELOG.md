# CHANGELOG — what landed, when

The shipped history of the companion plugins. **Direction and design decisions
live in [ROADMAP.md](./ROADMAP.md)**; this is the version-by-version record that
used to accrete there (kept out so the roadmap stays lean — the project's own
subtractive principle, applied to its own docs).

Versions are per-plugin (each ships independently). Newest first.

## charter — *know the project*

- **0.14.0** — blast-radius wire-in: the project-map gap nudge asks the model to
  mark **high-fan-in / "core" modules** so a change's blast radius is known before
  it's touched.
- **0.13.0** — `/charter:align`: on-demand reconcile of open/proposed work against
  recorded decisions + roadmap (charter's first slash command); the on-demand arm
  of the alignment discipline.
- **0.12.0** — recorded decisions named as the **alignment anchor** (*clean ≠
  correct*); restored the explicit "consult before reversing a choice" the 0.10.0
  brief had genericized away.
- **0.10.0** — one **compact, proportional brief** (baseline map + what's-next
  always; quality attributes for web; decisions/stack by the model's judgment).
- **0.9.0** — non-technical posture (apply sensible defaults instead of
  flag-for-review).
- **0.8.0** — **stack notes** dimension (`STACK.md` / a "## Stack" section).
- **0.7.0** — **roadmap reconcile**: surfaces recent non-merge commit subjects
  next to the roadmap so reconciliation is concrete.
- **0.6.0** — **decisions/ADR** dimension + **quiet-mode** (`claude-companion`
  marker drops the recurring honor/consult reminders).
- **0.5.0** — **web best-practices** defaults (Lighthouse-aligned QA, shift-left).
- **0.4.0** — **project map** (`file → responsibility`); orientation points at it.
- **0.3.0** — committed, Claude-facing **roadmap/backlog file**.
- **0.1.0** — MVP: **quality-attributes gate** at SessionStart.

## tidy — *change safely & cleanly*

- **0.27.0** — blast-radius wire-in: surfaced **higher in the touch output** (right
  after lint findings) and its message ties dependents to **test coverage**; the
  standard's anchors now lead with *blast radius first — cover the dependents of
  what you touch*.
- **0.26.0** — tightened the **non-Go blast-radius** heuristic: require the
  basename to sit after a quote/slash/dot (module-specifier shape, not a bare
  prose word), exclude doc/data files, raise the min basename length to 5, and
  expand the generic-name skip — cutting the false positives the looser grep
  produced.
- **0.25.0** — **multi-stack edit-time linting** (Python `ruff`, shell
  `shellcheck` — findings-only, project's own tool); **language-aware Go
  blast-radius** via `go list` (exact importer packages, cached per module per
  session, bounded, falls back to grep).
- **0.24.0** — make-free test-command discovery (`check.sh`/`test.sh`).
- **0.23.0 / 0.15.0** — test-file exemptions (light-distill / size nudge).
- **0.22.0** — `/tidy:audit` (read-only proportional whole-project audit).
- **0.16.0** — Go-aware blast-radius keyed on the **package import path**.
- **0.14.0** — non-technical posture.
- **0.13.0** — **verification floor**: a Stop hook runs the project's own tests
  and blocks until green (bounded).
- **0.12.0** — design model (tests as safety net; SOLID essence; ubiquitous
  language; proportional simplicity).
- **0.11.0** — **blast-radius** (importers via `git grep`).
- **0.10.0** — **currency/modernization** (surface manifest pins; never
  auto-upgrade).
- **0.9.0** — **web edit-time linters** (eslint incl. jsx-a11y, stylelint).
- **0.8.0** — **size-vs-complexity** automatic (per-touch + light distill at
  session start).
- **0.7.0** — `/tidy:distill` (whole-project weight report).
- **0.6.0** — bootstrap-then-quiet hook (policy in CLAUDE.md → one-line re-anchor).
- **0.5.0** — subtractive **prune force**, touch-time half (*subtract as you add*).

## task-queue — *orchestrate the work*

- **0.18.0** — blast-radius wire-in: the capture nudge **sequences low-reach steps
  first** and flags steps touching high-fan-in modules; agent-mode keeps
  **high-blast-radius changes off parallel subagents**.
- **0.17.0** — **open-decisions ledger** so a question the model asks isn't lost to
  queued/typed-ahead prompts: `tq-ask.sh` (open/resolve/list), a UserPromptSubmit
  hook that re-surfaces unanswered decisions every prompt, and a Notification hook
  that alerts when the model is idle with one open — with a proceed-on-recommended
  -default policy so work never stalls.
- **0.16.0** — **alignment-aware capture**: weigh captured work against the
  recorded direction (decisions/roadmap) before capturing.
- **0.14.0** — opt-in **agent-mode** toggle (fan independent tasks to subagents).
- **0.13.0** — bootstrap-then-quiet hook.
- **0.12.0** — **roadmap/backlog hydration** into the live task list.
- **earlier** — SessionStart policy, cross-session **resume bridge**,
  auto-advance, per-repo **pause**, schema-drift canary.

## hud — *show what's happening*

- **0.3.0** — status line reworked for **signal-per-cost**: a **static health
  beacon** (no `refreshInterval` → no idle jq+git wakeups), the verification
  floor's **✓/✗ tests** result, **agent-mode**, **context-window fill %** (from
  the payload's `used_percentage`), a **docs-health** glyph (map+roadmap+QA,
  detection realigned with charter), and an **uncommitted-file count**.
- **0.2.0** — consolidated status-line MVP.

## Phases (all complete)

- **Phase 1** — charter MVP (criteria 1 + 4).
- **Phase 2** — task-queue smart backlog + agent-mode (criterion 6).
- **Phase 3** — tidy blast-radius + size-vs-complexity + multi-stack (criteria
  3, 5, the through-line).
