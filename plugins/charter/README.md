# charter

**Know the project.** When you vibe-code a project with Claude, the thing that
keeps it maintainable, token-efficient, and quality-driven is a *documented
sense of what the project is and what "good" means for it.* `charter` makes that
non-optional: it **gates substantive work on documented quality attributes**, and
keeps the project's "Claude manual" in view — proactively, at no per-prompt cost.

## The idea

One event-driven hook (for now):

**A `SessionStart` hook.** It resolves the repo and checks whether the project
documents its **quality attributes** (performance, security, accessibility,
reliability, maintainability targets — the *-ilities*).

- **Not documented →** it nudges the model to **capture them first**, before
  substantive changes, in `QUALITY.md` (or a "Quality Attributes" section of
  `CLAUDE.md`). You can't honor what isn't written down.
- **Documented →** a brief reminder to honor them, then it stays out of the way.

Source-aware (lean re-anchor on `compact`/`resume`, silent once documented), so
it costs almost nothing per session.

> The "gate" is a strong **nudge**, not a hard block — a hook can't stop the
> model, but it makes the omission impossible to miss.

## What counts as "documented"

Any of: a `QUALITY.md` / `docs/QUALITY.md` / `docs/quality-attributes.md`, an ADR
under `docs/adr/`, or a *Quality Attributes* / *Non-functional* section in
`CLAUDE.md` / `AGENTS.md` / `README.md`. Override the accepted file with
`CLAUDE_CHARTER_QA_FILE` (a path relative to the repo root).

## Diagnostics

```bash
bash bin/charter-doctor.sh
```

Reports whether the current project documents its quality attributes, whether a
Claude manual (`CLAUDE.md`/`AGENTS.md`) exists, and the activity-log tail.

## Where it fits

`charter` is the *know-the-project* plugin in a three-part system — alongside
**task-queue** (orchestrate the work) and **tidy** (change safely & cleanly). See
[../../docs/ROADMAP.md](../../docs/ROADMAP.md). It's **read-only over your
project** — it inspects and nudges; it never writes your files.

## Install

```bash
claude plugin marketplace add andrewstanbury/claude-task-queue
claude plugin install charter@andrewstanbury
```

## Configuration

| Var | Effect |
|---|---|
| `CLAUDE_CHARTER_QA_FILE` | A path (relative to repo root) that counts as the quality-attributes doc. |
| `CLAUDE_CHARTER_LOG_DISABLED` | Set to `1` to turn off the activity log. |
| `CLAUDE_CHARTER_LOG_DIR` | Move the activity log (default `~/.claude/state/charter/`). |

## Requirements

- Bash 4+ and `jq`

## Tests

```bash
bats tests/
```

What it depends on from Claude Code is in [CONTRACT.md](./CONTRACT.md).

## License

MIT.
