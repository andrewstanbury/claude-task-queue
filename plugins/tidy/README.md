# tidy

**Tidy-as-you-touch** for [Claude Code](https://code.claude.com). When you edit a file, this plugin **formats it** (auto-applying only behavior-preserving fixes) and **surfaces linter findings** for the model to address — so a project you actively work on **converges toward clean code over time**, with the work scoped to the files you actually touch. No big-bang refactor, no per-prompt cost.

## The idea

Two event-driven hooks, nothing else:

**1. A standard, once per session (`SessionStart`).** Injects a concise *clean-as-you-go* policy — apply clean-code basics, respect clean-architecture boundaries, honor the project's own tools, and **only within the scope of your change**. Stated once; governs the session at no per-prompt cost.

**2. Format + lint on touch (`PostToolUse` on `Edit`/`Write`).** For each file you edit, it detects the language and:
- **auto-applies the formatter** (Go: `goimports`, else `gofumpt`/`gofmt`) — these are behavior-preserving, so they're safe to apply silently;
- **runs the linter** (Go: `golangci-lint`) and feeds back any findings **for that file**, so the model fixes them before moving on.

Unsupported file types and missing tools are a **silent no-op** — it never gets in your way.

## A deliberately bounded responsibility

This plugin **writes to your working tree** (unlike a read-only plugin), so it's deliberately conservative:

- **Only behavior-preserving fixes auto-apply** (formatting). Linter findings are *surfaced*, never silently rewritten.
- **Strictly scoped to the file you just edited** — never a repo-wide reformat.
- **Respects the project's own config** (e.g. `.golangci.yml`); it doesn't impose a house style.
- **Generated files are skipped** (`// Code generated … DO NOT EDIT.`).
- **It never breaks the edit** — every step is best-effort; on any error it stays silent.

When a file is auto-formatted, the hook tells the model to **re-read it before further edits** (formatting may have shifted line content).

## Languages

MVP targets **Go** (`goimports`/`gofumpt`/`gofmt` + `golangci-lint`). Every other language is a graceful no-op today; more dispatch can be added in `lib/tidy.sh` without touching the hooks.

## Install

```bash
claude plugin marketplace add andrewstanbury/claude-task-queue
claude plugin install tidy@andrewstanbury
```

Enabled by default. It only acts on files whose tooling is installed, so it's safe to have on everywhere.

## Configuration

| Var | Effect |
|---|---|
| `CLAUDE_TIDY_LOG_DISABLED` | Set to `1` to turn off the activity log. |
| `CLAUDE_TIDY_LOG_DIR` | Move the activity log (default `~/.claude/state/tidy/`). |

## Requirements

- Bash 4+ and `jq`
- For Go: `goimports` (or `gofumpt`/`gofmt`) on `PATH`; `golangci-lint` optional (for findings)

## Diagnostics

When tidy seems to do nothing on a Go file, run the read-only health check:

```bash
bash bin/tidy-doctor.sh
```

It validates the [CONTRACT](./CONTRACT.md) against your environment — `jq`, a Go
formatter, `golangci-lint` — and prints the activity-log tail.

## Tests

```bash
bats tests/
```

Go tooling is faked via stub executables on `PATH`, so the dispatch is exercised deterministically without installing it. What the plugin depends on from Claude Code and the environment is in [CONTRACT.md](./CONTRACT.md).

## License

MIT.
