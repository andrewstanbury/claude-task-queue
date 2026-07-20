# Hands-off drain

**When:** you want Claude to keep working the queue without stopping to ask — autopilot, optionally shipping as it goes.

## Happy path
1. `/companion:autopilot on` — Claude keeps draining the queue without stopping to ask.
2. While on, asking is **blocked** and the drain auto-continues each turn.
3. With ship-mode on, each turn's work auto-commits to an `autopilot/*` branch (never main, never pushed) for later review + `/companion:ship-it`. *(uses [guardrails default-on](./_patterns.md))*
4. `/companion:autopilot decisive on` — auto-picks the recommended option for **reversible** decisions (design/wording included), records each, and parks only the irreversible-critical (R59); shown as `✈️⚡`.

## Quality bar
- Autopilot can't spin forever — it yields after a no-progress cap (a productive drain keeps going).
- Ship-mode **never** commits to the default branch and **never** pushes — reversible checkpoints only.
- Decisive mode's safety is **auditability**: every auto-pick is a recorded breadcrumb, and the irreversible still parks.

## Tests
- [E] `autopilot: toggle persists, and is enforced (ask-guard deny + Stop auto-continue)` ✅
- [E] `autopilot: Stop yields after the no-progress cap (can't spin forever)` ✅
- [E] `ship-mode (R34): toggle, and Stop auto-commits work to an autopilot/* branch — NEVER main` ✅
- [E] `ship-mode never commits to the default branch, even from detached HEAD` ✅
- [E] `autopilot decisive (R59): toggle persists, and flips the ask-guard guidance park→decide` ✅

## Changes
- 2026-07-20 — migrated from UX.md Path 3 into a flow page (R62).
