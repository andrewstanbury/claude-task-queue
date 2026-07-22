# flow:pick-up-where-you-left-off
when: return to a repo after an earlier session → resume, then clear decisions waiting on owner
why: parked decisions are only trustworthy if they reliably reach the owner later — resume+review make the human half as dependable as the drain [R38 R39]

steps:
- `/companion:resume` — autopilot OFF first (resumed decisions go to the owner, not the next drain), then re-surface earlier tasks preserving ❓/⏳/📋 class [pattern:recommendation-first]
- `/companion:review` — walk ❓+⏳ pile one at a time, recommendation-first; each pick written back BEFORE new work; `decompose:` parks run as context interviews → minimal-blast children [R65]; this is also the autopilot-off trigger

quality:
- resume never promotes a parked ❓ into plain open (would let the next drain decide it)
- autopilot-off arms the review — one gesture
- carried queue survives repo move (per-worktree identity, not abspath); worktrees/clones stay isolated [R63]

tests:
- [E] `manual resume: turns autopilot OFF first, announced when on and quiet when off` ✅
- [E] `manual resume: lists THIS repo's open tasks on demand (and says so when none)` ✅
- [E] `resume: carried tasks render the done-when + LATEST note sub-lines` ✅
- [E] `resume survives a repo MOVE — scoping keys on a per-worktree identity` ✅
- [E] `resume ISOLATES git worktrees — same history, separate trees, separate queues` ✅
- [S] review walks pile recommendation-first, one at a time — judgment 👁

changes:
- 2026-07-22 machine shape [R66; reverses R62] · why-line provenance
- 2026-07-20 from UX.md P4 [R62]; carry-queue split to own flow; per-worktree scoping [R63, corrected from root-SHA design that would merge worktree queues]
