# Claude Code companion plugins

A small marketplace of **native-first, low-friction** plugins for [Claude Code](https://code.claude.com) — each one leans on Claude Code's own mechanisms (the native task list, hooks, your project's tooling) rather than inventing a parallel system, and each costs little to nothing per prompt.

## Plugins

| Plugin | What it does |
|---|---|
| **[task-queue](./plugins/task-queue)** | Makes Claude Code's native task list a live work queue: a SessionStart policy + cross-session resume bridge + auto-advance to the next unblocked task on completion, with a per-repo pause. Read-only over `~/.claude/tasks`. |
| **[tidy](./plugins/tidy)** | Tidy-as-you-touch: when you edit a file, format and lint it (and fix what's safe) so an active project converges toward clean code over time — scoped to the file you touched. |
| **[charter](./plugins/charter)** | Know the project: gates substantive work on documented quality attributes (nudges to capture them if missing) and keeps the project's Claude manual in view, so a vibe-coded project stays oriented and quality-driven. |
| **[hud](./plugins/hud)** | A consolidated status line: animated beacon, open tasks + in-progress, paused, quality-attributes, last tidy, tokens up/down, git branch, model — read-only, zero model-token cost. |

## Install

```bash
claude plugin marketplace add andrewstanbury/claude-task-queue
claude plugin install task-queue@andrewstanbury
claude plugin install tidy@andrewstanbury
claude plugin install charter@andrewstanbury
claude plugin install hud@andrewstanbury
```

Each plugin is independent — install only the ones you want. See each plugin's own README for details, configuration, and its CONTRACT.

## Layout

```
.claude-plugin/marketplace.json   # lists the plugins below
plugins/<name>/                   # one self-contained plugin each
  .claude-plugin/plugin.json
  hooks/  bin/  lib/  tests/
  README.md  CONTRACT.md
```

## Development

Each plugin is Bash + `jq` (zero build step) with its own `bats` suite. CI lints (`shellcheck`), scans for secrets (`gitleaks`), guards file size, and runs every plugin's tests on each push and PR.

## License

MIT. See [LICENSE](./LICENSE).
