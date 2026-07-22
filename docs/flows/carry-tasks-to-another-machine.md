# flow:carry-tasks-to-another-machine
when: switching computers mid-project, same task queue
why: the backlog is project state — travels with the repo over git, doesn't die with a laptop or break on a different clone path [R60 R63]

steps:
- leaving machine: `tq export` → committable `.companion/queue.json`; commit (`/companion:ship-it` does both)
- new machine: `git pull` → `/companion:resume` — imports + re-stamps to local identity; ❓/⏳/📋 classes + breadcrumbs intact

quality:
- import idempotent; dedup by (subject, done_when) across ALL statuses — finished tasks never resurrect
- one corrupt task file skipped-with-count, never zeroes the backlog
- scope: linear handoff A→B; concurrent two-way = last-export-wins (status changes don't merge back) [R60 🔓]

tests:
- [E] `tq export/import (R60): carries the open queue to a NEW clone path, re-stamped + idempotent` ✅
- [E] `tq export (R60): one corrupt task file is skipped, the backlog is NOT zeroed` ✅
- [E] `tq import (R60): dedups across ALL statuses — a task completed here is not resurrected` ✅
- [E] `tq import (R60): refuses when the session is bound to a DIFFERENT repo` ✅
- [E] `tq import (R60): a merge-conflicted queue.json is a LOUD no-op, not a silent one` ✅

changes:
- 2026-07-22 machine shape [R66; reverses R62] · why-line provenance
- 2026-07-20 created [R60]; split from P4 [R62]
