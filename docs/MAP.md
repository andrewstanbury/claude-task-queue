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
| `tests/drift-guard.bats` | Cross-plugin guard: asserts task-queue doc-detection + tidy's scar-tissue (`tidy_hotspots`) + hud's open-questions mirrors agree with charter/task-queue (the source of truth). |
| `tests/token-budget.bats` | The **token-budget NFR**: runs each hook in its representative path and fails CI if its injected text exceeds a per-hook character budget — token efficiency (the defining quality attribute) made enforceable. Growing a budget is a deliberate ratchet. |

Per plugin: `.claude-plugin/plugin.json` (manifest+version), `hooks/hooks.json`
(event wiring), `CONTRACT.md` (dependencies), `bin/` (hook entrypoints + controls),
`lib/` (logic), `tests/`. (Slash commands are a thin optional
surface over the hooks: task-queue's `/task-queue:*` family, charter's `/charter:align`,
hud's `/hud:setup` + `/hud:legend`, and tidy's `/tidy:audit`.)

## task-queue — *orchestrate the work* (hooks: SessionStart, UserPromptSubmit, Stop)

| File | Responsibility |
|---|---|
| `bin/tq-resume.sh` | SessionStart: standing policy + cross-session resume + roadmap hydration + quiet-mode + solo/agent/drift signals. |
| `bin/tq-capture.sh` | UserPromptSubmit: on any substantive prompt, inject the review loop — first **EVALUATE before executing** (steelman then challenge the ask; flag contradictions with recorded constraints or the owner's own earlier requests, or a forced poor/over-engineered design; recommend against when warranted — selective, real-signal only, so it doesn't train rubber-stamping), then the interpret→present→approve loop (interpret → decompose → judge risk/fan-out → AskUserQuestion → create only approved) AND stash the prompt as the intent of record; on a **visual/design** prompt, inject the design-preview loop instead (recommended + alternatives as faithful wireframe mockups in the AskUserQuestion preview, arrow-keys + Enter to pick, build only the chosen one — demonstrate before build); **always** re-surfaces any open-question (`❓`) the user hasn't answered (even on a trivial/solo-mode prompt) so it isn't buried; silent on trivial prompts otherwise; loop suppressed when the repo is in solo mode. |
| `bin/tq-verify.sh` | Stop: the **intent→outcome gate** (loop close) — replay the stashed intent against the actual diff, block once (consumed per ask) so the model verifies the outcome matches the ask and recaps in plain language before "done". `CLAUDE_TQ_INTENT_GATE=0` to disable. |
| `bin/tq-ask-guard.sh` | PreToolUse[AskUserQuestion]: while solo mode is on, hard-block the question (deny) and tell the model to decide-if-reversible or PARK as `❓` — makes solo's "never ask" mechanical, not advisory. |
| `bin/tq-review-guard.sh` | PreToolUse[Edit\|Write\|NotebookEdit]: after autopilot turns off with a parked `❓` pile, deny edits until the owner has reviewed every parked item and cleared it (self-clears when empty) — makes "review the parked decisions before new code" mechanical. `CLAUDE_TQ_REVIEW_GATE=0` disables. |
| `bin/tq-design-guard.sh` | PreToolUse[Edit\|Write\|NotebookEdit]: on a visual/design prompt, deny edits until a wireframe preview (AskUserQuestion) has been shown — the ask-guard clears the per-session marker capture armed. Stands down during an autopilot drain. Enforces show-before-build. `CLAUDE_TQ_DESIGN_GATE=0` disables. |
| `bin/tq` | Fallback queue writer: when the native task tools are gated off for a model, the model runs `tq add/doing/done/list` and it writes native-format JSON to the native per-session store — same format/location every reader keys off. The one place task-queue writes `~/.claude/tasks` (self-routed; idle when native is present). |
| `bin/tq-status.sh` | Control: the `/task-queue:status` readout — feature states (autopilot/agents) + open-work count. The other modes are per-feature slash commands (`/task-queue:autopilot\|agents` `toggle` via `tq-away.sh`/`tq-agent.sh`; `resume` re-surfaces an earlier session's open tasks). The single `/tq` hub was retired for these. |
| `bin/tq-agent.sh` | Control: opt-in agent-mode toggle. When on, the capture hook names the independent unblocked tasks (`tq_ready_tasks`) and tells the model to fan them to parallel subagents — the hook selects, the model spawns. |
| `bin/tq-away.sh` | Control: the `/task-queue:autopilot` toggle — flip autopilot on (run fully autonomous, never block, PARK what needs the owner) / off (normal review loop resumes). |
| `bin/tq-restore.sh` | Control: the manual `/task-queue:resume` twin — re-surface an earlier session's open tasks on demand (after a crash-relaunch or a compacted-away startup note), complementing the automatic SessionStart resume. |
| `bin/tq-ship.sh` | Control: `/task-queue:ship-it` — deterministic git plumbing that takes verified work from the tree to merged-on-main (the caller supplies the green gate). |
| `lib/tasks.sh` | Native task-store reads, agent flag + the away/solo auto-continue counter, the intent-of-record file, `tq_open_questions` + `tq_open_worklist`, drift canary. |
| `lib/away.sh` | Autopilot/away state (`tq_is_away`) + the owner-present marker (`tq_mark_present`/`tq_owner_present`), the park-rule, the return-review flag (`tq_review_pending`/`set`/`clear`), and the away digest (`tq_away_digest`). |
| `lib/signals.sh` | `tq_state_signals` — the compact autopilot/agent/drift state line for the SessionStart resume bridge. |
| `lib/resume.sh` | `tq_resume_context` — the cross-session resume bridge (reinstate an earlier session's open tasks). |
| `lib/project.sh` | Detect the committed roadmap/backlog file + the `claude-companion` marker. |
| `lib/capture.sh` | Multi-step / consequential / **visual-design** heuristics; shared alignment clause. |

## tidy — *change safely & cleanly* (hooks: SessionStart, PreToolUse[Edit\|Write\|MultiEdit], PostToolUse[Edit\|Write], Stop)

| File | Responsibility |
|---|---|
| `bin/tidy-presecret.sh` | PreToolUse: the **secret floor** — scan the content a write would land for hardcoded credentials and block (exit 2) before it reaches disk. tidy's one deliberate hard-stop; fail-open on anything else. `CLAUDE_TIDY_SECSCAN=0` to disable. |
| `bin/tidy-standard.sh` | SessionStart: the clean-as-you-go standard (trimmed to anchors) + the state prune. No longer surfaces whole-project debt — the deliberate prune now fires from `tidy-verify.sh` (Stop). |
| `bin/tidy-touch.sh` | PostToolUse: format + lint (Go/web/Python/shell/GDScript) + blast-radius + coverage nudge + size for the edited file. |
| `bin/tidy-verify.sh` | Stop: the verification floor — run the project's tests, block until green (bounded, timeout, change-throttled); opt-in coverage gate; the **regression gate** (block when a changed file is both a scar-tissue hotspot and untested — bounded, OPT-IN/off by default since tests are the owner's call, `CLAUDE_TIDY_REGRESSION_GATE=1` to enable); the **quality floor** (run the project's own declared typecheck/a11y/dep-rule gates before the tests, block until green, bounded — `CLAUDE_TIDY_QUALITY_FLOOR=0` to disable). Plus, after a clean verify on a dirty tree, one non-blocking post-work surface: **import cycles** touching the change (`lib/arch.sh`, content-deduped) + the throttled deliberate-prune nudge (over `CLAUDE_TIDY_PRUNE_THRESHOLD` over-budget files → `tidy-distill.sh`'s weight report, once per debt episode). |
| `bin/tidy-distill.sh` | Read-only whole-project weight report (the prune-report generator, run by `tidy-verify.sh` over threshold, and on demand by `/tidy:audit`). |
| `commands/audit.md` | `/tidy:audit` — on-demand whole-project audit: runs `tidy-distill.sh` (static weight report) PLUS a model-driven **performance pass** (recognises hot/realtime paths generically — no engine allowlist — and flags likely per-frame/hot-loop regressions, routing fps/thermal to a before/after profile since it can't measure runtime), then **auto-queues** every finding as a `TaskCreate` cleanup task (smallest blast-radius first), parking only obviously-risky ones as `❓`. The manual, clean-tree/below-threshold complement to the automatic prune. |
| `lib/tidy.sh` | Language dispatch, Go/web/GDScript handlers, size nudge, state dir (`tidy_log_dir`); shared `tidy_root_for_cwd` + `tidy_run_linter`. |
| `lib/lint.sh` | Multi-stack edit-time linters (Python `ruff` + format via `ruff format`/`black`, shell `shellcheck`) — Python also auto-formats; project's own tool. |
| `lib/secscan.sh` | The secret-floor regex: prefix-anchored credential shapes (AWS/GitHub/Slack/Stripe/Google/PEM) + a placeholder-filtered generic pattern, and the exempt-path test. Pure regex, no external tool (works without gitleaks). |
| `lib/coverage.sh` | Coverage ratchet: per-language test detection, opt-in characterize-before-change nudge (`CLAUDE_TIDY_COVERAGE=1`), untested-changed lister for the opt-in gate; `tidy_hotspots` (scar-tissue mirror of charter, drift-guarded) + `tidy_untested_hotspots` (the regression gate's target — untested ∩ hotspot). |
| `lib/checks.sh` | Test-command discovery + bounded run + working-tree fingerprint (verify throttle); `tidy_quality_commands` (discover the project's own typecheck/a11y/dep-rule scripts for the quality floor). |
| `lib/blast.sh` | Blast-radius (Go: exact `go list` importers, cached, → git grep fallback; basename heuristic elsewhere). |
| `lib/arch.sh` | Clean-architecture checks: import-cycle detection (detect-and-run `madge`, `tidy_cycles_changed`). |

## charter — *know the project + own the owner relationship* (hooks: SessionStart, Stop)

| File | Responsibility |
|---|---|
| `bin/charter-standard.sh` | SessionStart: the proportional project brief (baseline gaps + consult line + owner-loop consent posture (intent → demo → consent) + scar-tissue/outcome-memory surfacing + quiet-mode). Action-time consent is native (settings.json), not a charter hook. |
| `bin/charter-mcp-probe.sh` | SessionStart (fresh start only): the **MCP reachability probe** — warn in plain language when an MCP server declared for the repo silently won't work this session (the tools just don't appear and a non-technical owner never notices). Best-effort, bounded, non-blocking; self-disables when no servers are declared; `CLAUDE_CHARTER_MCP_PROBE=0` to disable. |
| `bin/charter-align-gate.sh` | Stop: the **alignment floor** — when a finished change plausibly bears on a recorded decision, block once and put the recorded decisions in front of the model (honor, or surface+confirm a reversal). Bounded (per-tree throttle + attempt cap) so it can't loop; the outcome-time complement to the review loop's intent-time alignment. |
| `bin/charter-align.sh` | Deterministic alignment anchors (decisions + roadmap + recent commits) for `/charter:align`. |
| `commands/align.md` | `/charter:align` — reconcile open/proposed work against the recorded direction (clean ≠ correct). |
| `lib/charter.sh` | Detect QA / roadmap / decisions / map / stack / web (React Native excluded from web — `charter_is_react_native`); recent commits; the `claude-companion` marker; `charter_hotspots` (outcome memory — the git rework-ratio scar-tissue metric). |
| `lib/mcp-probe.sh` | MCP-probe logic: read the MCP servers declared for the repo and check each is reachable (parallel, hard per-server timeout; stdio = command/package starts, http/sse = endpoint responds — a 401/403 auth challenge counts as reachable). Any internal error degrades to silence. |
| `lib/conventions.sh` | Detect the project's established conventions (UI/component lib, styling, state, components dir, tests; React Native: Expo-vs-bare platform, navigation lib, NativeWind) + their recorded-status, for the reuse-before-create brief. |
| `lib/align.sh` | Alignment-floor helpers: cache-only state dir, working-tree fingerprint (throttle), bounded decisions excerpt, and the cheap deterministic pre-filter (decision-bearing surfaces + fenced-token overlap) that keeps the gate silent on routine edits. |

## hud — *show what's happening* (a statusLine, not a hook)

| File | Responsibility |
|---|---|
| `bin/hud-status.sh` | The status-line renderer, three zones: **health & alerts** (beacon · 🛡 safety shield / 🛡✗N disabled-floor count · ✅/❌/⚠️ tests (self-colored emoji) · 🎨 design / 🔒 review edit-gates, tagged with a word only while armed · **❓N** parked decisions · **⏳N** owner-blocked) · **feature state** (bare ✈️ autopilot / 🤖 agents, shown only when on) · **context** (model · ⇡/⇣ token throughput · **project name** · branch+dirty · **↑ahead ↓behind** vs upstream). |
| `bin/hud-install.sh` | Wire the status line into `settings.json`, version-resilient, `refreshInterval: 1` for the animated beacon (`/hud:setup`). |
| `commands/setup.md` | `/hud:setup`. |
| `lib/hud.sh` | Read-only accessors over the other plugins' state (autopilot/away, agent, verify result, `hud_floors_disabled` shield count, `hud_design_pending`/`hud_review_pending` edit-gates, `hud_open_questions` ❓-count, `hud_blocked` ⏳-count, `hud_human_tokens`, branch, dirty, `hud_ahead_behind` unpushed/unpulled vs upstream, `hud_legend` — read-only mirrors/markers). |
