# Changelog

All notable changes to the **hud** plugin are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-05-31

### Added
- Initial release. A consolidated `statusLine` renderer (`bin/hud-status.sh`)
  showing, left → right: an **animated beacon** (yellow when paused), **open
  tasks + the in-progress one**, **⏸ paused**, **quality-attributes** status,
  **last tidy** action, **tokens up/down**, **git branch**, and **model**.
- Read-only: renders from the statusLine payload + existing sibling-plugin state
  (native task store, pause flags, charter's QA doc, tidy's log). No hooks, no
  project scanning, **zero model-token cost**. Each slot collapses when its
  source is absent; honours `NO_COLOR` / `TERM=dumb` and a narrow terminal.
- `lib/hud.sh` accessors; `bats` suite; README (wiring + the token nuance);
  CONTRACT (the read-only soft path coupling to sibling plugins).

[0.1.0]: https://github.com/andrewstanbury/claude-task-queue/releases/tag/hud-v0.1.0
