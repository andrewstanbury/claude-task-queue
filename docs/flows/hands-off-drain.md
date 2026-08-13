# flow:hands-off-drain
when: keep working the queue without stopping to ask (autopilot; optional ship-mode)
why: idle hours → finished reviewable work; unsupervised decisions only where the owner opted in — decisive for new reversible ones (R59), sweep for parks the parker marked `rev:` (R77); the irreversible always reaches the owner [R26 R59 R65 R77]. R100/Pass 6 (docs/adr/README.md R105): ask-guard.sh is REINSTATED — "don't stop to ask" is hook-enforced again. stop-autopilot.sh is RESTORED (R111, 2026-08-12, reversing the declines of R105 and R107) — "keep going instead of stopping" is hook-enforced again while a STARTABLE task remains, with the no-progress cap, both R81 run bounds and the R77 sweep terminator back with it. Ship-mode's auto-commit and the drained-queue-to-burn-down handoff stay RETIRED on purpose: `ship-checkpoint.sh` and the model own those now, and restoring them would put two owners on one concern.

steps:
- `/companion:autopilot on` → drain continues; asking is ENFORCED again — ask-guard.sh denies AskUserQuestion and auto-parks it for you, but parking it yourself first (`tq add`) is still the intended path, not the denial round-trip
- ship on → call the `ship_checkpoint` MCP tool yourself at a stopping point (was automatic pre-R100) to commit to `autopilot/*` (never default branch, never pushed) → review + `/companion:ship-it` [pattern:guardrails-default-on]
- sweep on → the drain ALSO works parks the parker MARKED `rev:` (reversible, owner's-call), applying each recorded `rec:`; no marker ⇒ irreversible ⇒ never swept, same for ⏳ and `decompose:` [R77]
- `decisive on` → auto-picks recommended option for reversible decisions (taste included), records each, parks only irreversible-critical; shown ✈️⚡ [R59]

quality:
- ~~no-progress cap~~ — still RETIRED with stop-autopilot.sh (not reinstated); nothing bounds a stall or a runaway run. Watch your own progress.
- asking IS enforced again — ask-guard.sh denies + auto-parks while autopilot is armed [R33/R84]
- ship-mode NEVER touches default branch, never pushes (still true — same code, still manually invoked, not reinstated as automatic)
- decisive safety = auditability (every auto-pick is a recorded breadcrumb; irreversible still parks)
- drain touches only minimal-blast tasks; a `decompose:`-flagged task is never auto-drained [R65]

tests:
- [E] `autopilot: toggle persists per repo, independent of other modes (R26)` ✅
- [E] `ship-checkpoint (R34): toggle, and commits work to an autopilot/* branch — NEVER main` ✅
- [E] `ship-mode never commits to the default branch, even from detached HEAD (R45)` ✅
- [E] `autopilot decisive (R59): toggle persists, independent of plain autopilot` ✅
- [E] `ask-guard: autopilot ON denies AND auto-parks the question with its real options + a recommendation (R84)` ✅
- [E] `ask-guard: DECISIVE mode swaps the guidance from park-every-decision to decide-if-reversible (R59)` ✅
- [E] `the decisive/plain park-vs-decide guidance is stated in STEERING and ask-guard.sh enforces it again (R33/R59/R84, R100/Pass 6)` ✅
- [E] `autopilot sweep: OFF stops on a parked-only queue, ON works a rev: park (R77)` ✅
- [E] `autopilot sweep: an IRREVERSIBLE park (no rev: marker) is never eligible (R77/R59)` ✅
- [E] `autopilot sweep: ⏳, decompose:, unrecorded and prose-only markers stay excluded (R77/R65)` ✅

changes:
- 2026-08-08 ask-guard.sh REINSTATED (owner-decided, "avoid rework" + "don't let the model barrel past an unanswered decision" outweighed portability for this one guarantee); stop-autopilot.sh stays retired — only the ask-blocking half of R100/Pass 4's loss is undone [R100/Pass 6, docs/adr/README.md R105, re-reverses R33/R59/R84, partially re-reverses R26]
- 2026-08-08 ask-guard.sh + stop-autopilot.sh retired — the whole flow becomes advisory (STEERING-stated), not hook-enforced; ship-mode's commit logic survives as standalone `bin/ship-checkpoint.sh`; no-progress/run-bound caps and the sweep terminator have no replacement [R100/Pass 4, reverses R26/R33/R59/R77/R81/R84/R88]
- 2026-07-26 sweep mode: work parks marked `rev:`, positive-marker eligibility, own terminator [R77; amends R33/R38/R59]
- 2026-07-22 machine shape [R66; reverses R62] · decompose-park [R65] · why-line provenance
- 2026-07-20 from UX.md P3 [R62]
