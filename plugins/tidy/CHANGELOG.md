# Changelog

All notable changes to the **tidy** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.1.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/tidy-v0.1.0
