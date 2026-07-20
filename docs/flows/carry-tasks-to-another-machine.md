# Carry tasks to another machine

**When:** you're switching computers mid-project and want the same task queue.

## Happy path
1. On the machine you're leaving: `tq export` writes this repo's open queue to a committable `.companion/queue.json`; commit it. *(or `/companion:ship-it` does it for you as part of shipping)*
2. On the new machine: `git pull`, then `/companion:resume` — the queue imports, **re-stamped to this machine's path** so it surfaces regardless of where the repo was cloned, with ❓/⏳/📋 classes and breadcrumbs intact.

## Quality bar
- Re-running import never duplicates or resurrects a finished task (dedup by `(subject, done_when)` across all statuses).
- A half-written task file can't zero the exported backlog (each file filtered individually).
- **Scope:** linear handoff (A → B). Concurrent two-way editing is last-export-wins — status changes don't merge back.

## Tests
- [E] `tq export/import (R60): carries the open queue to a NEW clone path, re-stamped + idempotent` ✅
- [E] `tq export (R60): one corrupt task file is skipped, the backlog is NOT zeroed` ✅
- [E] `tq import (R60): dedups across ALL statuses — a task completed here is not resurrected` ✅
- [E] `tq import (R60): refuses when the session is bound to a DIFFERENT repo` ✅
- [E] `tq import (R60): a merge-conflicted queue.json is a LOUD no-op, not a silent one` ✅

## Changes
- 2026-07-20 — created (R60); split from Path 4 into its own flow (R62).
