# MAP — where things live (Claude-facing project map)

A compact `file → responsibility` index so a session orients from here instead of
re-scanning the tree. Read [AGENTS.md](../AGENTS.md) for conventions/invariants and
[docs/ROADMAP.md](./ROADMAP.md) for direction. Each plugin's `CONTRACT.md` documents
what it depends on; each plugin's `tests/*.bats` exercises it.

## Repo root

| Path | Responsibility |
|---|---|
| `AGENTS.md` | Canonical maintainer guide — read first. |
| `CLAUDE.md` | Project instructions + the hard invariants. |
| `docs/ROADMAP.md` | Direction, status, and the recorded design decisions (lean). |
| `docs/MAP.md` | This file — the `file → responsibility` index. |
| `check.sh` | One-command gate: JSON valid · ShellCheck · secret scan · 300-line size guard · bats. CI runs this. |
| `flow.sh` | Render the colored workflow diagram in the terminal, derived live from the repo (`./flow.sh` / `make flow`) — the one sanctioned human-facing artifact. |
| `.claude-plugin/marketplace.json` | Marketplace manifest (the 4 plugins + versions). |
| `.github/workflows/ci.yml` | CI — provisions tools, runs `check.sh`. |
| `tests/drift-guard.bats` | Cross-plugin guard: asserts task-queue doc-detection + tidy's scar-tissue (`tidy_hotspots`) mirrors agree with charter (the source of truth). |

Per plugin: `.claude-plugin/plugin.json` (manifest+version), `hooks/hooks.json`
(event wiring), `CONTRACT.md` (dependencies), `bin/` (hook entrypoints + controls),
`lib/` (logic), `tests/`. (charter's `/charter:align` and hud's `/hud:setup` are
the only `commands/` left; task-queue and tidy are hook-only now.)

## task-queue — *orchestrate the work* (hooks: SessionStart, UserPromptSubmit, Stop)

| File | Responsibility |
|---|---|
| `bin/tq-resume.sh` | SessionStart: standing policy + cross-session resume + roadmap hydration + quiet-mode + pause/agent/drift signals. |
| `bin/tq-capture.sh` | UserPromptSubmit: on any substantive prompt, inject the interpret→present→approve review loop (interpret → decompose → judge risk/fan-out → AskUserQuestion → create only approved) AND stash the prompt as the intent of record; on a **visual/design** prompt, inject the design-preview loop instead (recommended + alternatives as faithful ASCII mockups in the AskUserQuestion preview, arrow-keys + Enter to pick, build only the chosen one — demonstrate before build); silent on trivial prompts; suppressed when the repo is paused. |
| `bin/tq-verify.sh` | Stop: the **intent→outcome gate** (loop close) — replay the stashed intent against the actual diff, block once (consumed per ask) so the model verifies the outcome matches the ask and recaps in plain language before "done". `CLAUDE_TQ_INTENT_GATE=0` to disable. |
| `bin/tq-pause.sh` | Control: pause/resume the review loop (per repo) — paused runs prompts straight through in auto. |
| `bin/tq-agent.sh` | Control: opt-in agent-mode (parallel subagent fan-out). |
| `lib/tasks.sh` | Native task-store reads, resume logic, pause/agent flags, the intent-of-record file, drift canary. |
| `lib/project.sh` | Detect the committed roadmap/backlog file + the `claude-companion` marker. |
| `lib/capture.sh` | Multi-step / consequential / **visual-design** heuristics; shared alignment clause. |

## tidy — *change safely & cleanly* (hooks: SessionStart, PostToolUse[Edit\|Write], Stop)

| File | Responsibility |
|---|---|
| `bin/tidy-standard.sh` | SessionStart: the clean-as-you-go standard (trimmed to anchors) + the state prune. No longer surfaces whole-project debt — the deliberate prune now fires from `tidy-verify.sh` (Stop). |
| `bin/tidy-touch.sh` | PostToolUse: format + lint (Go/web/Python/shell) + blast-radius + coverage nudge + size for the edited file. |
| `bin/tidy-verify.sh` | Stop: the verification floor — run the project's tests, block until green (bounded, timeout, change-throttled); opt-in coverage gate; the **regression gate** (block when a changed file is both a scar-tissue hotspot and untested — bounded, default-on, `CLAUDE_TIDY_REGRESSION_GATE=0` to disable). Plus, after a clean verify on a dirty tree, one non-blocking post-work surface: **import cycles** touching the change (`lib/arch.sh`, content-deduped) + the throttled deliberate-prune nudge (over `CLAUDE_TIDY_PRUNE_THRESHOLD` over-budget files → `tidy-distill.sh`'s weight report, once per debt episode). |
| `bin/tidy-distill.sh` | Read-only whole-project weight report (the prune-report generator, run by `tidy-verify.sh` over threshold). |
| `lib/tidy.sh` | Language dispatch, Go/web handlers, size nudge, state dir (`tidy_log_dir`); shared `tidy_root_for_cwd` + `tidy_run_linter`. |
| `lib/lint.sh` | Multi-stack edit-time linters (Python ruff, shell shellcheck) — findings-only, project's own tool. |
| `lib/coverage.sh` | Coverage ratchet: per-language test detection, characterize-before-change nudge, untested-changed lister for the opt-in gate; `tidy_hotspots` (scar-tissue mirror of charter, drift-guarded) + `tidy_untested_hotspots` (the regression gate's target — untested ∩ hotspot). |
| `lib/checks.sh` | Test-command discovery + bounded run + working-tree fingerprint (verify throttle). |
| `lib/blast.sh` | Blast-radius (Go: exact `go list` importers, cached, → git grep fallback; basename heuristic elsewhere). |
| `lib/arch.sh` | Clean-architecture checks: import-cycle detection touching the change (detect-and-run the project's `madge`; silent without it — no bespoke resolver). |

## charter — *know the project + own the owner relationship* (hooks: SessionStart, Stop)

| File | Responsibility |
|---|---|
| `bin/charter-standard.sh` | SessionStart: the proportional project brief (baseline gaps + consult line + owner-loop consent posture (intent → demo → consent) + scar-tissue/outcome-memory surfacing + quiet-mode). Action-time consent is native (settings.json), not a charter hook. |
| `bin/charter-align-gate.sh` | Stop: the **alignment floor** — when a finished change plausibly bears on a recorded decision, block once and put the recorded decisions in front of the model (honor, or surface+confirm a reversal). Bounded (per-tree throttle + attempt cap) so it can't loop; the outcome-time complement to the review loop's intent-time alignment. |
| `bin/charter-align.sh` | Deterministic alignment anchors (decisions + roadmap + recent commits) for `/charter:align`. |
| `commands/align.md` | `/charter:align` — reconcile open/proposed work against the recorded direction (clean ≠ correct). |
| `lib/charter.sh` | Detect QA / roadmap / decisions / map / stack / web; recent commits; the `claude-companion` marker; `charter_hotspots` (outcome memory — the git rework-ratio scar-tissue metric). |
| `lib/conventions.sh` | Detect the project's established conventions (UI/component lib, styling, state, components dir, tests) + their recorded-status, for the reuse-before-create brief. |
| `lib/align.sh` | Alignment-floor helpers: cache-only state dir, working-tree fingerprint (throttle), bounded decisions excerpt, and the cheap deterministic pre-filter (decision-bearing surfaces + fenced-token overlap) that keeps the gate silent on routine edits. |

## hud — *show what's happening* (a statusLine, not a hook)

| File | Responsibility |
|---|---|
| `bin/hud-status.sh` | The status-line renderer: health beacon · paused · agent · ✓/✗ tests · ctx % · branch+dirty · model. |
| `bin/hud-install.sh` | Wire the status line into `settings.json`, version-resilient, no refreshInterval (`/hud:setup`). |
| `commands/setup.md` | `/hud:setup`. |
| `lib/hud.sh` | Read-only accessors over the other plugins' state (paused, agent, verify result, branch, dirty). |
