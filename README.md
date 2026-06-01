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

## Principles (in priority order)

1. **Contain blast radius** — minimize and understand the ripple of every change,
   both *code* (cover the dependents of what you touch) and *architectural* (one
   owner per concern, contracts not copies). The first-class principle the rest
   serve: a contained change is cheaper to load, test, and reason about.
2. **Optimize for Claude to read & maintain** the project — assume Claude does all
   the coding going forward.
3. **Token efficiency** — *earn* the token (highest-leverage context), don't just
   minimize words; zero per-prompt cost in the plugins themselves.
4. **File sizes match the complexity** of the requirement — split only when it
   earns it (the 300-line guard is the trigger).
5. **Honor the project's quality attributes** — document them first if missing
   (web projects get Lighthouse-aligned defaults).
6. **Follow the stack's recommended patterns** — and flag outdated/deprecated tech
   within the touched scope.
7. **Streamlined, proactive plugins** — seamless, pausable, show the work, process
   the backlog optimally.

Always-on, cutting across all of the above: **tests are the floor** (the
verification hook blocks until green), **subtract as you add**, **document
proportionally**, **alignment** (clean ≠ correct — don't contradict a recorded
decision), and **bootstrap-then-quiet** hooks (record the standing policy in your
`CLAUDE.md`, mark it `claude-companion`, and the SessionStart hooks re-anchor in
one line). Hard invariants (self-contained plugins, no shared lib/build,
read-only or conservative mutation) live in [AGENTS.md](./AGENTS.md).

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
