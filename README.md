# claude-task-queue — companion plugins (personal, Claude-run)

A small marketplace of **self-contained Claude Code plugins** that make
vibe-coding a project seamless: Claude keeps it clean, documented,
token-efficient, and low-debt **proactively** — driven by event hooks, with
essentially nothing to trigger by hand.

Maintained by Claude, for Claude. **Start at [AGENTS.md](./AGENTS.md)**
(conventions, invariants, workflow) and [docs/ROADMAP.md](./docs/ROADMAP.md)
(direction + status). Each plugin's `CONTRACT.md` documents what it depends on.

## The plugins

| Plugin | Job | Highlights |
|---|---|---|
| **task-queue** | Orchestrate the work | Native task list as a live queue: capture, dependency-order, auto-advance, per-repo pause, cross-session resume, hydrate from a committed roadmap/backlog. |
| **tidy** | Change safely & cleanly | Format + lint + TDD nudge on touch; subtractive prune posture; **automatic size-vs-complexity** flag (per-touch + a light distill at session start); `/tidy:distill` for an on-demand deep prune pass. |
| **charter** | Know the project | Gates work on documented quality attributes (web projects get Lighthouse-aligned defaults); maintains a roadmap/backlog, a project map, and decisions/ADRs — generating them from the code/git when missing. |
| **hud** | Show what's happening | A consolidated, read-only status line over the other plugins' state. |

Design principles (see AGENTS.md for the hard invariants): **zero per-prompt
cost**, **self-contained** plugins (no shared lib / build), **read-only or
conservative mutation**, and **bootstrap-then-quiet** — record the standing
policy in your `CLAUDE.md` and mark it `claude-companion`, and the SessionStart
hooks re-anchor in one line instead of re-injecting in full.

The only non-automatic entry points are, by design: `/tidy:distill` (deep prune),
`tq-pause on|off` (the one control), and the per-plugin `*-doctor.sh` diagnostics.

## Install

This marketplace is a **directory source**. From Claude Code:

```
/plugin marketplace add /path/to/claude-task-queue
/plugin install task-queue@andrewstanbury
/plugin install tidy@andrewstanbury
/plugin install charter@andrewstanbury
/plugin install hud@andrewstanbury
```

After pulling new versions, `/plugin marketplace update andrewstanbury` then
update each plugin.

## Verify

Run **`./check.sh`** — JSON validity, ShellCheck, secret scan, a 300-line
size guard, and the `bats` test suites. CI runs the same script.
