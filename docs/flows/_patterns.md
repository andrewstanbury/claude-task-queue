# patterns — shared conventions, defined once, referenced as [pattern:name]

## recommendation-first [S]
Decision-shaped → pick-from-CLI menu, recommended option marked, carrying the honest read ON the pick — its cost, what you would regret, what argues against it. Never a verdict tacked onto every reply. 👁

## queue-one-at-a-time [S/E]
Requests → `tq` tasks, smallest-blast-first, each with done-when; one at a time + breadcrumb. Companion owns the store (never native tasks). CLI: add·doing·note·done·cancel·list·report; mutations echo a one-line delta, full report at done/report/session start [R69].
- [E] `tq: done-when — --done on add + the done-when subcommand STORE it` ✅
- [E] `tq: add/doing/done write the companion store + stamp the repo root` ✅

## wireframe-first [S]
Visual change → wireframe/ASCII agreed before code. 👁

## sketch-first [E/S]
Structural change (new seam or dependency, data-model or interface change) → interface delta + call-stack stated BEFORE code, then sliced into tasks carrying the sketch as `--context` [R106]. Steering, not a command, and delivered by the SessionStart injection so it fires unasked — an opt-in design step is what the failure mode eats (adr R106).
- [E] `sketch-first is DELIVERED to a session, not merely stated in a file — no command to remember (R106)` ✅

## clean-as-you-go [S]
Weigh blast radius · subtract · YAGNI · verify by exercising · one-line recap. 👁

## offer-not-act [S]
Nudges are offers: debt→task · repetitive-drain→autopilot · **drained-run→advise on what it touched** [R107] · finished-chunk→ship-it. 👁
- [E] `a drained autopilot run offers a quality read — the lights-off gap has a nudge (R107)` ✅

## contract-preserving-rebuild [S]
`redesign` reproduces logged flows + quality bar, gated on safety checks, on a branch; implementation may change, experience may not. 👁

## guardrails-default-on [E]
Safety on by default, opt-out only; disabled gate is loud. (R100/Pass 3: the secret scan itself
is advisory now, not enforced — the status-line loudness on disable is the part still real.)
- [E] `check-secrets: BLOCKs a real AWS key (exit 2) — advisory only, R100/Pass 3` ✅
- [E] `status line: 🛡✗ when the secret gate is disabled` ✅

## living-contract [E/S]
Contract stays accurate continuously [R58]: UX/QA change moves the flow spec FIRST (steering reflex) · drift backstop runs at the SHIP boundary only (`ship-it`; not per-gate-run — tune-out, R58 amended 2026-07-22) · `/companion:cover` = test-scaffolding arm.
- [E] `contract-drift: warns when behaviour changed without a contract doc` ✅
