# patterns — shared conventions, defined once, referenced as [pattern:name]

## recommendation-first [S]
Decision-shaped → pick-from-CLI menu, recommended option marked; every reply ends with a one-line brutal-honest verdict. 👁

## queue-one-at-a-time [S/E]
Requests → `tq` tasks, smallest-blast-first, each with done-when; one at a time + breadcrumb. Companion owns the store (never native tasks). CLI: add·doing·note·done·cancel·list·report; mutations echo a one-line delta, full report at done/report/session start [R69].
- [E] `tq: done-when — --done on add + the done-when subcommand STORE it` ✅
- [E] `tq: add/doing/done write the companion store + stamp the repo root` ✅

## wireframe-first [S]
Visual change → wireframe/ASCII agreed before code. 👁

## clean-as-you-go [S]
Weigh blast radius · subtract · YAGNI · verify by exercising · one-line recap. 👁

## offer-not-act [S]
Nudges are offers: debt→task · big-blast→split · repetitive-drain→autopilot · finished-chunk→ship-it. 👁

## contract-preserving-rebuild [S]
`redesign` reproduces logged flows + quality bar, gated on safety checks, on a branch; implementation may change, experience may not. 👁

## guardrails-default-on [E]
Safety on by default, opt-out only; disabled gate is loud.
- [E] `secret gate: blocks a real AWS key (exit 2)` ✅
- [E] `status line: 🛡✗ when the secret gate is disabled` ✅

## living-contract [E/S]
Contract stays accurate continuously [R58]: prompts captured (write-only hook, zero injection; redacted at rest + rotated, R68) · UX/QA change moves the flow spec FIRST (steering reflex) · drift backstop runs at the SHIP boundary only (`ship-it`; not per-gate-run — tune-out, R58 amended 2026-07-22) · `/companion:cover` = test-scaffolding arm.
- [E] `capture: banks the prompt, injects nothing` ✅
- [E] `contract-drift: warns when behaviour changed without a contract doc` ✅
