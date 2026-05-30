# Changelog

All notable changes to the **tidy** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.3.0] — 2026-05-30

### Added
- **TDD nudge.** Editing a Go *source* file surfaces a one-line reminder to add
  or extend its sibling `_test.go` (test-first). Gentle by design: skips test
  and generated files, and fires at most once per file per session (markers
  under `~/.claude/state/tidy/nudged/`).
- **Recommended ratchet-friendly `.golangci.yml`** in the README (`new-from-rev`
  so only *new* issues surface — keeps a legacy backlog from flooding you). The
  plugin honors your config; it never imposes one.

### Changed
- **Enriched the SessionStart standard**: now leads with test-first (TDD) and
  legacy-aware clean architecture (characterization tests before refactoring,
  no god-files) and states the **ratchet** lint posture — fix findings in code
  you touched; leave unrelated pre-existing issues alone.
- `PostToolUse` output is now a single combined `[tidy] <file>:` note covering
  formatting, scoped linter findings, and the TDD nudge.

## [0.2.0] — 2026-05-30

### Added
- **`bin/tidy-doctor.sh`** — a manual, read-only health check that validates the
  CONTRACT against the live environment (jq, a Go formatter, golangci-lint) and
  prints the activity-log tail. Exits non-zero only on a hard failure.
- **Payload-drift canary** in the PostToolUse hook: if a payload arrives but has
  no `tool_input.file_path`, it's logged as `drift` (the shape we read may have
  changed) and the hook stays silent.

## [0.1.0] — 2026-05-30

### Added
- Initial release. Tidy-as-you-touch via two event-driven hooks:
  - **`SessionStart`** injects a concise clean-as-you-go standard (apply
    clean-code basics, respect clean-architecture boundaries, honor the
    project's tools — scoped to the change).
  - **`PostToolUse(Edit|Write)`** formats the touched file (Go: `goimports` /
    `gofumpt` / `gofmt`, behavior-preserving, auto-applied) and surfaces
    `golangci-lint` findings **for that file** for the model to address.
- Conservative by design: only behavior-preserving fixes auto-apply, scoped to
  the touched file, generated files skipped, project config honored, and it
  never breaks the triggering edit. Auto-formatting prompts a re-read.
- Best-effort activity log at `~/.claude/state/tidy/activity.log`
  (`CLAUDE_TIDY_LOG_DIR` / `CLAUDE_TIDY_LOG_DISABLED`).
- MVP targets **Go**; other languages no-op gracefully.
- `bats` suite (Go tooling faked on `PATH`), README, CONTRACT.

[0.3.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/tidy-v0.3.0
[0.2.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/tidy-v0.2.0
[0.1.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/tidy-v0.1.0
