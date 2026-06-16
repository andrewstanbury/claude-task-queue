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
| **charter** | Know the project + own the owner relationship | Gates work on documented quality attributes (web projects get Lighthouse-aligned defaults); maintains a roadmap/backlog, a project map, and decisions/ADRs — generating them from the code/git when missing; surfaces consent before consequential actions. |
| **hud** | Show what's happening | A consolidated, read-only status line over the other plugins' state. |

## Principles (in priority order)

The full, canonical statement lives in **[docs/ROADMAP.md](./docs/ROADMAP.md)**
("Prioritized criteria"). Tuned for ongoing work on **real, often legacy,
under-tested** projects, in short:

- **0 · Self-describing first** — keep the project's map / quality-attributes /
  decisions current (and growth visible) so a change's blast radius is knowable;
  keep a thin plain-language owner layer.
- **1 · Contain blast radius** — know what depends on what you touch and contain
  the ripple; watch that total coupling doesn't climb (**YAGNI** — burden of proof
  is on *adding* a dep/abstraction/layer).
- **2 · Verify + stay aligned** — characterize before you change, keep the suite
  green, weigh work against recorded decisions, honor the owner's *outcome* not
  their proposed implementation.
- **3 · Subtract as you add** — net surface flat or smaller; reuse before create.
- **4 · Deliberate prune** — a scheduled audit/distill for the cross-module debt
  touch-time bounding skips.

Always-on: **tests stay green** (the verification floor blocks until they pass),
**document proportionally**, and **bootstrap-then-quiet** hooks. Hard invariants
(self-contained plugins, no shared lib/build, read-only or conservative mutation)
live in [AGENTS.md](./AGENTS.md).

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
