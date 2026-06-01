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
| `docs/CHANGELOG.md` | Per-plugin version-by-version shipped history. |
| `README.md` | Human-facing overview of the marketplace. |
| `check.sh` | One-command gate: JSON valid · ShellCheck · secret scan · 300-line size guard · bats. CI runs this. |
| `.claude-plugin/marketplace.json` | Marketplace manifest (the 4 plugins + versions). |
| `.github/workflows/ci.yml` | CI — provisions tools, runs `check.sh`. |

Per plugin: `.claude-plugin/plugin.json` (manifest+version), `hooks/hooks.json`
(event wiring), `CONTRACT.md` (dependencies), `bin/` (hook entrypoints + controls),
`lib/` (logic), `commands/` (slash commands), `tests/`.

## task-queue — *orchestrate the work* (hooks: SessionStart, TaskCompleted, UserPromptSubmit, Notification)

| File | Responsibility |
|---|---|
| `bin/tq-resume.sh` | SessionStart: standing policy + cross-session resume + roadmap hydration + quiet-mode + pause/agent/drift signals + log prune. |
| `bin/tq-next.sh` | TaskCompleted: advance to the next unblocked task. |
| `bin/tq-capture.sh` | UserPromptSubmit: conditional capture nudge. |
| `bin/tq-decisions.sh` | UserPromptSubmit: re-surface open decisions every prompt so a question isn't lost to queued input. |
| `bin/tq-notify.sh` | Notification: desktop/terminal alert when idle with an open decision. |
| `bin/tq-ask.sh` | Control: the model's CLI for the open-decisions ledger (open/resolve/list). |
| `bin/tq-pause.sh` | Control: pause/resume auto-advance (per repo). |
| `bin/tq-agent.sh` | Control: opt-in agent-mode (parallel subagent fan-out). |
| `bin/tq-doctor.sh` | Manual diagnostics. |
| `lib/tasks.sh` | Native task-store reads, resume logic, pause/agent flags, logging + log prune. |
| `lib/project.sh` | Detect the committed roadmap/backlog file + the `claude-companion` marker. |
| `lib/capture.sh` | Capture heuristics. |
| `lib/decisions.sh` | Open-decisions ledger (per-repo): add/resolve/list/count. |

## tidy — *change safely & cleanly* (hooks: SessionStart, PostToolUse[Edit\|Write], Stop)

| File | Responsibility |
|---|---|
| `bin/tidy-standard.sh` | SessionStart: the clean-as-you-go standard (trimmed to anchors) + state prune. |
| `bin/tidy-touch.sh` | PostToolUse: format + lint (Go/web/Python/shell) + blast-radius + coverage nudge + size + currency for the edited file. |
| `bin/tidy-verify.sh` | Stop: the verification floor — run the project's tests, block until green (bounded, timeout, change-throttled); opt-in coverage gate. |
| `bin/tidy-distill.sh` | Read-only whole-project weight report (backs `/tidy:distill` and `/tidy:audit`). |
| `bin/tidy-doctor.sh` | Manual diagnostics. |
| `commands/distill.md` | `/tidy:distill` — on-demand prune pass. |
| `commands/audit.md` | `/tidy:audit` — read-only proportional whole-project audit. |
| `lib/tidy.sh` | Language dispatch, Go/web handlers, size/currency nudges, state prune. |
| `lib/lint.sh` | Multi-stack edit-time linters (Python ruff, shell shellcheck) — findings-only, project's own tool. |
| `lib/coverage.sh` | Coverage ratchet: per-language test detection, characterize-before-change nudge, untested-changed lister for the opt-in gate. |
| `lib/checks.sh` | Test-command discovery + bounded run + working-tree fingerprint (verify throttle). |
| `lib/blast.sh` | Blast-radius (Go: exact `go list` importers, cached, → git grep fallback; basename heuristic elsewhere). |

## charter — *know the project* (hook: SessionStart)

| File | Responsibility |
|---|---|
| `bin/charter-standard.sh` | SessionStart: the proportional project brief (baseline gaps + consult line + quiet-mode) + log prune. |
| `bin/charter-doctor.sh` | Manual diagnostics. |
| `bin/charter-align.sh` | Deterministic alignment anchors (decisions + roadmap + recent commits) for `/charter:align`. |
| `commands/align.md` | `/charter:align` — reconcile open/proposed work against the recorded direction (clean ≠ correct). |
| `lib/charter.sh` | Detect QA / roadmap / decisions / map / stack / web; recent commits; the `claude-companion` marker; logging. |

## hud — *show what's happening* (a statusLine, not a hook)

| File | Responsibility |
|---|---|
| `bin/hud-status.sh` | The status-line renderer: health beacon · tasks · paused · agent · ✓/✗ tests · docs-health · last tidy · ctx % · branch+dirty · model. |
| `bin/hud-install.sh` | Wire the status line into `settings.json`, version-resilient, no refreshInterval (`/hud:setup`). |
| `commands/setup.md` | `/hud:setup`. |
| `lib/hud.sh` | Read-only accessors over the other plugins' state (tasks, paused, agent, verify result, QA/map/roadmap, last tidy, branch, dirty). |
