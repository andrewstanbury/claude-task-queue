# Pick up where you left off

**When:** you return to a repo after an earlier session and want to resume, then clear the decisions waiting on you.

## Happy path
1. `/companion:resume` — turns autopilot **off** first (so resumed decisions come back to *you*, not the next drain), then re-surfaces this repo's earlier-session tasks, preserving each item's ❓/⏳/📋 class. *(uses [recommendation-first](./_patterns.md))*
2. `/companion:review` — walk the parked (❓) + blocked (⏳) backlog one at a time, recommendation-first; each pick is written back to the queue **before** any new work. This is also what the autopilot-off switch triggers.

## Quality bar
- Resume never **promotes a parked decision into a plain open task** (that would let the next drain autopilot the answer instead of asking you).
- Turning autopilot off is what *arms* the review — the two are one gesture.

## Tests
- [E] `manual resume: turns autopilot OFF first, announced when on and quiet when off` ✅
- [E] `manual resume: lists THIS repo's open tasks on demand (and says so when none)` ✅
- [E] `resume: carried tasks render the done-when + LATEST note sub-lines` ✅
- [S] `/companion:review` walks the pile recommendation-first, one at a time — judgment, eyeball only. 👁

## Changes
- 2026-07-20 — migrated from UX.md Path 4 into a flow page (R62). The "carry the queue to another machine" step moved to its own flow: [Carry tasks to another machine](./carry-tasks-to-another-machine.md).
