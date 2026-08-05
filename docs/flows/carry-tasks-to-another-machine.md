# flow:carry-tasks-to-another-machine
when: switching computers mid-project, same task queue
why: the backlog is project state — it travels with the repo over git, so it does not die with a laptop or break on a different clone path [R63 R96]

steps:
- nothing to do while leaving: the queue lives in `.companion/tasks` inside the repo, so any commit carries it [R96]
- leaving machine, work FINISHED: `/companion:ship-it` — the ship commits the tree, queue included
- leaving machine, work MID-FLIGHT: `/companion:handoff` → one call (`ship.sh handoff`): stage → refuse credential shapes → commit WIP (`wip/<stamp>` branch when on default — WIP never lands on default; in place on a feature branch) → `push -u`; NO gate required (checkpoint, not ship — the gate fires at `land`) [R72]
- new machine: clone or pull, then `/companion:resume` — it re-surfaces this repo's open tasks with ❓/⏳/📋 classes and breadcrumbs intact [R75]

quality:
- the queue is repo state, never machine state: a fresh clone or container inherits it [R96]
- a handoff never lands on the default branch and never ships without a gate [R72]

tests:
- [E] `the QUEUE is repo state: it survives into a fresh clone with no home state (R96 stage 2)`
- [E] `ship.sh handoff: on the default branch — WIP moves to a wip/* branch, default untouched, work rides the commit`
- [E] `modes are REPO state: they survive a wiped state dir and do not block burn-down (R96)`

changes:
- 2026-08-05 — the manual `tq export`/`import` carry is DELETED (R60 reversed). It duplicated what git already carried, and could carry a STALE copy: `/companion:resume` auto-imported a three-day-old export and resurrected 13 completed tasks. Git is now the only transport.
