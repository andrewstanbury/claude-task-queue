# flow:hands-off-drain
when: keep working the queue without stopping to ask (autopilot; optional ship-mode)
why: idle hours → finished reviewable work with zero unsupervised decisions [R26 R59 R65]

steps:
- `/companion:autopilot on` → drain continues; asking is BLOCKED (enforced: ask-guard deny + Stop auto-continue)
- ship on → each turn auto-commits to `autopilot/*` (never default branch, never pushed) → review + `/companion:ship-it` [pattern:guardrails-default-on]
- `decisive on` → auto-picks recommended option for reversible decisions (taste included), records each, parks only irreversible-critical; shown ✈️⚡ [R59]

quality:
- no-progress cap — cannot spin forever (productive drain keeps going)
- ship-mode NEVER touches default branch, never pushes
- decisive safety = auditability (every auto-pick is a recorded breadcrumb; irreversible still parks)
- drain touches only minimal-blast tasks; a `decompose:`-flagged task is never auto-drained [R65]

tests:
- [E] `autopilot: toggle persists, and is enforced (ask-guard deny + Stop auto-continue)` ✅
- [E] `autopilot: Stop yields after the no-progress cap (can't spin forever)` ✅
- [E] `ship-mode (R34): toggle, and Stop auto-commits work to an autopilot/* branch — NEVER main` ✅
- [E] `ship-mode never commits to the default branch, even from detached HEAD` ✅
- [E] `autopilot decisive (R59): toggle persists, and flips the ask-guard guidance park→decide` ✅

changes:
- 2026-07-22 machine shape [R66; reverses R62] · decompose-park [R65] · why-line provenance
- 2026-07-20 from UX.md P3 [R62]
