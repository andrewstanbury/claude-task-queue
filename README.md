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

Tuned for ongoing work on **real, often legacy projects** — features already
built, frequently *without* solid tests or documented requirements. The order
reflects what prevents rework and lets the project **converge toward clean as you
build**, rather than accrue cruft.

1. **Contain blast radius** — before changing code, know what depends on it and
   contain the ripple. When tests and specs don't exist, this is the primary
   safety net, and it **bounds where you clean up**. The one principle not to
   compromise. (Both *code* ripple and *architectural* ripple — one owner per
   concern, contracts not copies.)
2. **Characterize before you change** — tests often don't exist, so pin the
   *current* behavior of the affected surface with tests **first** (blast radius
   says what to pin). This is how the project accrues a real spec over time.
3. **Preserve intent** — requirements are often undocumented, so don't alter
   behavior you didn't mean to; surface assumptions to the owner in plain language
   (clean ≠ correct — a well-made change can still be the wrong one).
4. **Clean as you touch, bounded by blast radius** — leave the touched area better
   than you found it; subtract as you add; **ratchet, never sweep** (don't
   refactor code whose ripple you can't see — that's how cleanup *causes* rework).
5. **Optimize for Claude to read & maintain** — rebuild the missing map/docs as
   you learn the code, keep files sized to their complexity, prefer the smaller
   surface. Keeps 1–4 cheap; this is where **token efficiency** accrues. Document
   quality attributes when the project's risk earns it (web → Lighthouse-aligned).
6. **Follow current, correct patterns** — flag outdated/deprecated tech within the
   touched scope.
7. **Streamlined, proactive plugins** — seamless, pausable, show the work, process
   the backlog optimally.

Always-on: **tests stay green** (the verification floor blocks until they pass),
**document proportionally**, and **bootstrap-then-quiet** hooks (record the
standing policy in your `CLAUDE.md`, mark it `claude-companion`, and the
SessionStart hooks re-anchor in one line). Hard invariants (self-contained
plugins, no shared lib/build, read-only or conservative mutation) live in
[AGENTS.md](./AGENTS.md).

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
