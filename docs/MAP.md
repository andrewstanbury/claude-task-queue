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
| `flow.sh` | Generate `FLOW.md` — derived live from the repo (`./flow.sh` / `make flow`). |
| `FLOW.md` | Human-reviewable workflow snapshot (the one sanctioned human-facing artifact; refresh via `flow.sh`). |
| `.claude-plugin/marketplace.json` | Marketplace manifest (the 4 plugins + versions). |
| `.github/workflows/ci.yml` | CI — provisions tools, runs `check.sh`. |
| `tests/drift-guard.bats` | Cross-plugin guard: asserts hud/task-queue doc-detection mirrors agree with charter (the source of truth). |

Per plugin: `.claude-plugin/plugin.json` (manifest+version), `hooks/hooks.json`
(event wiring), `CONTRACT.md` (dependencies), `bin/` (hook entrypoints + controls),
`lib/` (logic), `tests/`. (charter's `/charter:align` and hud's `/hud:setup` are
the only `commands/` left; task-queue and tidy are hook-only now.)

## task-queue — *orchestrate the work* (hooks: SessionStart, UserPromptSubmit)

| File | Responsibility |
|---|---|
| `bin/tq-resume.sh` | SessionStart: standing policy + cross-session resume + roadmap hydration + quiet-mode + pause/agent/drift signals. |
| `bin/tq-capture.sh` | UserPromptSubmit: on any substantive prompt, inject the interpret→present→approve review loop (interpret → decompose → judge risk/fan-out → AskUserQuestion → create only approved); silent on trivial prompts; suppressed when the repo is paused. |
| `bin/tq-pause.sh` | Control: pause/resume the review loop (per repo) — paused runs prompts straight through in auto. |
| `bin/tq-agent.sh` | Control: opt-in agent-mode (parallel subagent fan-out). |
| `lib/tasks.sh` | Native task-store reads, resume logic, pause/agent flags, drift canary. |
| `lib/project.sh` | Detect the committed roadmap/backlog file + the `claude-companion` marker. |
| `lib/capture.sh` | Multi-step/consequential heuristics; shared alignment clause. |

## tidy — *change safely & cleanly* (hooks: SessionStart, PostToolUse[Edit\|Write], Stop)

| File | Responsibility |
|---|---|
| `bin/tidy-standard.sh` | SessionStart: the clean-as-you-go standard (trimmed to anchors) + the state prune. No longer surfaces whole-project debt — the deliberate prune now fires from `tidy-verify.sh` (Stop). |
| `bin/tidy-touch.sh` | PostToolUse: format + lint (Go/web/Python/shell) + blast-radius + coverage nudge + size for the edited file. |
| `bin/tidy-verify.sh` | Stop: the verification floor — run the project's tests, block until green (bounded, timeout, change-throttled); opt-in coverage gate. Plus, after a clean verify on a dirty tree, the throttled deliberate-prune nudge — over `CLAUDE_TIDY_PRUNE_THRESHOLD` over-budget files injects `tidy-distill.sh`'s weight report as a non-blocking systemMessage, once per debt episode. |
| `bin/tidy-distill.sh` | Read-only whole-project weight report (the prune-report generator, run by `tidy-verify.sh` over threshold). |
| `lib/tidy.sh` | Language dispatch, Go/web handlers, size nudge, state dir (`tidy_log_dir`); shared `tidy_root_for_cwd` + `tidy_run_linter`. |
| `lib/lint.sh` | Multi-stack edit-time linters (Python ruff, shell shellcheck) — findings-only, project's own tool. |
| `lib/coverage.sh` | Coverage ratchet: per-language test detection, characterize-before-change nudge, untested-changed lister for the opt-in gate. |
| `lib/checks.sh` | Test-command discovery + bounded run + working-tree fingerprint (verify throttle). |
| `lib/blast.sh` | Blast-radius (Go: exact `go list` importers, cached, → git grep fallback; basename heuristic elsewhere). |

## charter — *know the project + own the owner relationship* (hooks: SessionStart)

| File | Responsibility |
|---|---|
| `bin/charter-standard.sh` | SessionStart: the proportional project brief (baseline gaps + consult line + owner-loop consent posture (intent → demo → consent) + quiet-mode). Action-time consent is native (settings.json), not a charter hook. |
| `bin/charter-align.sh` | Deterministic alignment anchors (decisions + roadmap + recent commits) for `/charter:align`. |
| `commands/align.md` | `/charter:align` — reconcile open/proposed work against the recorded direction (clean ≠ correct). |
| `lib/charter.sh` | Detect QA / roadmap / decisions / map / stack / web; recent commits; the `claude-companion` marker. |
| `lib/conventions.sh` | Detect the project's established conventions (UI/component lib, styling, state, components dir, tests) + their recorded-status, for the reuse-before-create brief. |

## hud — *show what's happening* (a statusLine, not a hook)

| File | Responsibility |
|---|---|
| `bin/hud-status.sh` | The status-line renderer: health beacon · paused · agent · ✓/✗ tests · ctx % · branch+dirty · model. |
| `bin/hud-install.sh` | Wire the status line into `settings.json`, version-resilient, no refreshInterval (`/hud:setup`). |
| `commands/setup.md` | `/hud:setup`. |
| `lib/hud.sh` | Read-only accessors over the other plugins' state (paused, agent, verify result, branch, dirty). |
