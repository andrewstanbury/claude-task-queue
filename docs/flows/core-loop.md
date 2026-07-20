# The core loop

**When:** the everyday cycle — you make a request, it becomes work, it gets done, it ships.

## Happy path
1. Every prompt is captured to a local write-only store (raw material for the living contract; nothing injected, no token cost).
2. A change to what the user sees/does — or a quality attribute — **moves the flow page first** (recommendation-first), with the code queued against it. *(uses [recommendation-first](./_patterns.md), [living-contract](./_patterns.md))*
3. The request becomes `tq` tasks — smallest-blast-first, each with a done-when. *(uses [queue-one-at-a-time](./_patterns.md))*
4. Worked one at a time, with a breadcrumb on the active task.
5. Decisions surface as pick-from-CLI menus, and every reply closes with a one-line brutal-honest verdict.
6. Context nudges *offer* next moves (debt · big blast · repetition · finished chunk) — offers, not actions. *(uses [offer-not-act nudges](./_patterns.md))*
7. Visual changes get a wireframe before code; work stays clean-as-you-go. *(uses [wireframe-first](./_patterns.md), [clean-as-you-go](./_patterns.md))*
8. A write that would commit a real credential is **blocked** with a message. *(uses [guardrails default-on](./_patterns.md))*
9. Verified by exercising, not asserting; recapped in one line.
10. A finished chunk ships with `/companion:ship-it`: verify → sync the flow pages → commit → push → merge.

## Quality bar
- Prompt capture is **write-only** — injects nothing, zero runtime token cost ([`_quality-bar.md`](./_quality-bar.md) N1).
- The credential block is **prevention, not detection** (N7) and **on by default** (opt-out only).

## Tests
- [E] `capture: banks the prompt, injects nothing` ✅
- [E] `contract-drift: warns when behaviour changed without a contract doc` ✅
- [E] `tq: done-when — --done on add + the done-when subcommand STORE it` ✅
- [E] `parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value` ✅
- [E] `secret gate: blocks a real AWS key (exit 2)` ✅
- [S] Decisions surface recommendation-first + brutal-honest verdict — judgment, eyeball only. 👁
- [S] Wireframe-before-code; clean-as-you-go; one-line recap — judgment, eyeball only. 👁

## Changes
- 2026-07-20 — migrated from UX.md Path 2 into a flow page (R62). "Sync the contract docs" step now reads "sync the flow pages."
