# Changelog

All notable changes to **claude-task-queue** are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

The `0.2.0`–`0.4.0` line is where the project inverted from a heavyweight
orchestration layer (its own store, Haiku triage, autopilot, a destructive-action
gate, a CLI, a status bar) into a featherweight **native-first** plugin: two
event-driven hooks, **read-only** over Claude Code's own task store, with **zero
per-prompt cost**. The breaking releases in that range reflect that rebuild.

## [0.9.0] — 2026-05-30

### Added
- **Proactive capture — a conditional `UserPromptSubmit` hook** (`bin/tq-capture.sh`
  + `lib/capture.sh`). It is **silent on almost every prompt**, speaking up only
  when the prompt looks multi-step **and** the session queue is empty — exactly
  when work should be captured but hasn't been. The checks are local bash/jq, so
  it's **token-free unless it fires** — which is what makes it safe per-prompt,
  unlike the unconditional `UserPromptSubmit` removed in 0.2.0. Disable with
  `CLAUDE_TQ_CAPTURE_DISABLED=1`.
- **Orientation nudge (token efficiency over time).** SessionStart now reminds
  the model to record durable project structure/conventions in `CLAUDE.md`, so
  future sessions orient cheaply instead of re-exploring the codebase each time.

## [0.8.0] — 2026-05-30

### Added
- **SessionStart schema-drift canary.** `tq_schema_status()` samples real task
  files; when one exists but lacks the `id`/`status` fields we read, the
  SessionStart hook injects a one-line warning (and logs `SCHEMA DRIFT`). This
  is how a never-reviewed install notices Claude Code changing the store format
  instead of failing silently. Fires only on a real mismatch — otherwise silent.
- **Real-captured test fixture** (`tests/fixtures/real-task.json`) plus a test
  that resume + advance parse the true on-disk shape, not just hand-made fakes.

### Fixed
- **CONTRACT.md lifecycle note corrected.** The v0.7.1 note claimed Claude Code
  removes a completed task's file individually; a real capture showed completed
  entries actually **persist** while the list has open tasks (the folder clears
  only when fully drained). The advance logic was already robust to both (it
  judges "blocked" against the open set), so no code change — just an honest doc
  fix.

## [0.7.1] — 2026-05-30

### Fixed
- **Advance hook stranding tasks behind completed blockers.** Claude Code
  removes a task's file when it's completed, so a finished blocker is *absent*
  from the store — but the advance hook had compared `blockedBy` against a
  "completed" set, so a task blocked by an earlier-completed (now-removed) task
  was never surfaced as next. It now judges "blocked" against the set of
  still-**open** tasks: an absent blocker can't block. Added a regression test.

### Changed
- CONTRACT.md documents the store's completion-removal lifecycle and the
  absent-blocker-is-satisfied rule it implies.

## [0.7.0] — 2026-05-30

### Added
- **Pause the backlog between tasks.** A per-repo pause suppresses the
  `TaskCompleted` auto-advance so you can finish a task and stop, instead of
  rolling into the next one.
  - `bin/tq-pause.sh on|off|status` toggles a flag scoped to the repo root; the
    pause **persists across sessions** until you resume.
  - Natural-language control: the `SessionStart` hook injects the exact
    `tq-pause.sh` command (with its resolved path) once per session, so "pause
    the queue" / "resume the queue" works without a slash command.
  - While paused, `TaskCompleted` stays silent (logged as `paused`), and
    `SessionStart` surfaces a "PAUSED for this repo" banner so it's discoverable.
  - `tq_pause_dir()` / `tq_pause_file()` / `tq_is_paused()` in `lib/tasks.sh`;
    relocatable via `CLAUDE_TQ_PAUSE_DIR`.
- `tests/pause.bats` — 8 cases (toggle, repo-root scoping, hook honoring the
  pause, resume re-enabling, and the SessionStart hint + banner).

### Changed
- `TaskCompleted` now also reads `cwd` from its payload to resolve the repo root
  for the pause check (falls back to the session transcript).

## [0.6.0] — 2026-05-30

### Added
- **Observability log** (`tq_log` in `lib/tasks.sh`): each hook appends a
  best-effort, tab-separated line to `~/.claude/state/task-queue/activity.log`
  (`session-start` / `advance` events). Disk-only (no model-context cost), never
  blocks a hook, disabled via `CLAUDE_TQ_LOG_DISABLED`, relocatable via
  `CLAUDE_TQ_LOG_DIR`.
- **`bin/tq-doctor.sh`**: a manual, read-only health check that validates the
  CONTRACT.md assumptions against the live environment (`jq`, the native task
  store + transcripts, and a **schema canary** sampling real task files for the
  `id`/`status` fields) and prints the activity-log tail. Exits non-zero only on
  a hard failure.
- `tests/diagnostics.bats` covering the log and the doctor.

### Changed
- CONTRACT.md now documents the two files the plugin writes (root cache,
  activity log) and names `tq-doctor` as the on-demand boundary check.

## [0.5.0] — 2026-05-30

### Added
- **`TaskCompleted` auto-advance hook** (`bin/tq-next.sh`). When the model marks
  a task done, it reads the current session's native task list and injects a
  one-line note naming the next **unblocked** pending task (lowest id first,
  honoring `blockedBy`) — so the queue keeps moving without being asked.
  - Treats the just-completed task as closed when checking dependencies, so the
    result is correct whether the hook fires before or after Claude Code writes
    the store.
  - Stays **silent** when another task is already `in_progress`, or when nothing
    is actionable (queue blocked, drained, or empty) — it never nudges toward
    draining the backlog.
- `tq_next_context()` in `lib/tasks.sh` backing the hook.
- 7 new `bats` cases (17 total) covering ordering, blocked-by-completed
  unblocking, and every silence path.
- `CHANGELOG.md` (this file).

### Changed
- Reframed as **two event-driven hooks** (`SessionStart` + `TaskCompleted`)
  rather than "one SessionStart hook" — still zero per-prompt cost.
- README install section: clarified the plugin is **enabled by default**
  (`defaultEnabled: true`); dropped the now-unneeded `claude plugin enable` step.

### Unchanged (by principle)
- **Read-only** over `~/.claude/tasks`: the new hook only reads the store and
  nudges the model — it never calls `TaskCreate`/`TaskUpdate` itself.

## [0.4.0] — 2026-05-30

### Changed
- **BREAKING:** Rebuilt as a **native Claude Code plugin** (`.claude-plugin/`,
  marketplace install) wired by `hooks/hooks.json`. The whole plugin became
  **one `SessionStart` hook** with **zero per-prompt cost**: it injects the
  queue policy once and appends the cross-session resume list.
- Removed the install/uninstall scripts and `settings.json` merging — Claude
  Code now wires and unwires the hooks.

## [0.3.0] — 2026-05-30

### Added
- **Resume bridge:** on `SessionStart`, surface a repo's still-open tasks from
  earlier sessions (capped, recency-bounded) so a fresh session re-adopts them
  into its otherwise-empty native list.

### Removed
- **BREAKING:** Dropped the always-on status line — a plugin can't robustly own
  the status line (the user's own config always wins).

## [0.2.0] — 2026-05-30

### Changed
- **BREAKING:** Rebuilt as a **zero-token reader over Claude Code's native task
  store**. Established the guiding principle: **never write the native store** —
  either read it or nudge the model, but the model owns the tasks. This retired
  the bespoke durable queue, the Haiku per-prompt decomposition, autopilot, the
  `PreToolUse` destructive-action gate, and the `tq` CLI in favor of leaning on
  Claude Code's own task tools and live task rendering.

> Safety gating that the old `PreToolUse` gate provided is now delegated to
> Claude Code's native permission system.

## [0.1.1] — 2026-05-29

### Fixed
- Anchored the `PreToolUse` destructive-command regex to cut false positives.
- Added an observability log and a `tq doctor` diagnostic.

## [0.1.0] — 2026-05-29

### Added
- First release: a **durable, project-scoped task queue** for Claude Code with
  Haiku-triage prompt decomposition, pause-resumable autopilot, a `PreToolUse`
  gate (silent on low-risk, always block on destructive), a `tq` CLI, and a
  status-bar reader. Queue persisted under `~/.claude/state/task-queue/`,
  surviving `/clear` and restarts.

[0.9.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.9.0
[0.8.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.8.0
[0.7.1]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.7.1
[0.7.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.7.0
[0.6.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.6.0
[0.5.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.5.0
[0.4.0]: https://github.com/andrewstanbury/claude-task-queue/commit/4b7b4f4
[0.3.0]: https://github.com/andrewstanbury/claude-task-queue/commit/59969ca
[0.2.0]: https://github.com/andrewstanbury/claude-task-queue/commit/156eba8
[0.1.1]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.1.1
[0.1.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/v0.1.0
