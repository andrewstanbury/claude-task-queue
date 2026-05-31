# Changelog

All notable changes to the **charter** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — 2026-05-31

### Added
- **Orientation nudge** on a fresh context — record durable project structure /
  conventions in `CLAUDE.md` so future sessions orient cheaply. Consolidated
  here from task-queue (charter owns project-knowledge); omitted in lean
  (compact/resume) mode to stay token-light.

## [0.1.0] — 2026-05-31

### Added
- Initial release (ROADMAP Phase 1). A `SessionStart` hook that **gates
  substantive work on documented quality attributes**: if the project documents
  none (no `QUALITY.md` / ADR / "Quality Attributes" section), it nudges the
  model to capture them — perf, security, a11y, reliability, maintainability —
  before substantive changes; if they're documented, a brief honor-reminder.
- Source-aware + lean: full nudge on `startup`/`clear`, a one-line re-anchor on
  `compact`/`resume`, silent once QA is documented and the source is compact.
- `bin/charter-doctor.sh` — read-only health check (QA status, manual presence,
  log tail). Best-effort activity log at `~/.claude/state/charter/`.
- Override the accepted QA doc via `CLAUDE_CHARTER_QA_FILE`.
- Self-contained (its own repo-root resolution); read-only over your project.
- `bats` suite, README, CONTRACT.

[0.2.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/charter-v0.2.0
[0.1.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/charter-v0.1.0
