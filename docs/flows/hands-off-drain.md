# flow:hands-off-drain
when: keep working the queue without stopping to ask (autopilot; optional ship-mode)
why: idle hours → finished reviewable work; unsupervised decisions only where the owner opted in — decisive for new reversible ones (R59), sweep for parks the parker marked `rev:` (R77); the irreversible always reaches the owner [R26 R59 R65 R77]. R100/Pass 4: ask-guard.sh and stop-autopilot.sh are retired — everything below is now ADVISORY (STEERING states it), not enforced by any hook. The biggest fidelity loss of the whole redesign.

steps:
- `/companion:autopilot on` → drain continues; asking is now ADVISORY — STEERING says don't stop to ask, park instead (`tq add` it yourself; nothing auto-parks anymore)
- ship on → run `bin/ship-checkpoint.sh` yourself at a stopping point (was automatic) to commit to `autopilot/*` (never default branch, never pushed) → review + `/companion:ship-it` [pattern:guardrails-default-on]
- sweep on → the drain ALSO works parks the parker MARKED `rev:` (reversible, owner's-call), applying each recorded `rec:`; no marker ⇒ irreversible ⇒ never swept, same for ⏳ and `decompose:` [R77]
- `decisive on` → auto-picks recommended option for reversible decisions (taste included), records each, parks only irreversible-critical; shown ✈️⚡ [R59]

quality:
- ~~no-progress cap~~ — RETIRED with stop-autopilot.sh; nothing left bounds a stall or a runaway run. Watch your own progress.
- ship-mode NEVER touches default branch, never pushes (still true — same code, now manually invoked)
- decisive safety = auditability (every auto-pick is a recorded breadcrumb; irreversible still parks)
- drain touches only minimal-blast tasks; a `decompose:`-flagged task is never auto-drained [R65]

tests:
- [E] `autopilot: toggle persists per repo, independent of other modes (R26)` ✅
- [E] `ship-checkpoint (R34): toggle, and commits work to an autopilot/* branch — NEVER main` ✅
- [E] `ship-mode never commits to the default branch, even from detached HEAD (R45)` ✅
- [E] `autopilot decisive (R59): toggle persists, independent of plain autopilot` ✅
- [E] `the decisive/plain park-vs-decide guidance is stated in STEERING (R33/R59/R84) — advisory only, no guard left` ✅
- [E] `autopilot sweep: OFF stops on a parked-only queue, ON works a rev: park (R77)` ✅
- [E] `autopilot sweep: an IRREVERSIBLE park (no rev: marker) is never eligible (R77/R59)` ✅
- [E] `autopilot sweep: ⏳, decompose:, unrecorded and prose-only markers stay excluded (R77/R65)` ✅

changes:
- 2026-08-08 ask-guard.sh + stop-autopilot.sh retired — the whole flow becomes advisory (STEERING-stated), not hook-enforced; ship-mode's commit logic survives as standalone `bin/ship-checkpoint.sh`; no-progress/run-bound caps and the sweep terminator have no replacement [R100/Pass 4, reverses R26/R33/R59/R77/R81/R84/R88]
- 2026-07-26 sweep mode: work parks marked `rev:`, positive-marker eligibility, own terminator [R77; amends R33/R38/R59]
- 2026-07-22 machine shape [R66; reverses R62] · decompose-park [R65] · why-line provenance
- 2026-07-20 from UX.md P3 [R62]
