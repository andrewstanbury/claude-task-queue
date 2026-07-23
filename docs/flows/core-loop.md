# flow:core-loop
when: request → work → done → shipped (the everyday cycle)
why: work survives crashes/compactions only as small verified steps with own acceptance; owner attention goes to decisions, not keeping work alive [R52 R65]

steps:
- every prompt captured to local write-only store (zero injection); obvious credentials/PII redacted at rest, store rotates at ~1MB [R58·a R68]
- UX/quality-attribute change → move the flow page FIRST, code queued against it [pattern:living-contract]
- request → `tq` tasks, smallest-blast-first, each `--done "<acceptance>"` [pattern:queue-one-at-a-time]
- high-blast-for-missing-context task → decompose-park (`❓ decompose:` risk+questions, not options); answers re-enter loop as minimal-blast children — open queue always safe to drain [R65]
- worked one at a time, breadcrumb on active task
- decisions → pick-from-CLI menus; every reply ends with one-line brutal-honest verdict [pattern:recommendation-first]
- context nudges are offers, not actions [pattern:offer-not-act]
- visual change → wireframe first [pattern:wireframe-first]; clean-as-you-go [pattern:clean-as-you-go]
- credential write → BLOCKED [pattern:guardrails-default-on]
- verify by exercising; recap one line
- ship via `/companion:ship-it`: verify → sync flows → commit → push → merge

quality:
- capture is write-only — zero runtime tokens [N1]
- queue mutations echo a one-line delta; full report only at done/report/session start [N1 R69]
- credential block is prevention, on by default [N7]

tests:
- [E] `capture: banks the prompt, injects nothing` ✅
- [E] `capture: redacts anchored credentials/PII at rest + rotates at the size cap (R68)` ✅
- [E] `contract-drift: warns when behaviour changed without a contract doc` ✅
- [E] `tq: done-when — --done on add + the done-when subcommand STORE it` ✅
- [E] `tq delta (R69): add/doing print a one-line counts delta, NOT the full queue; done prints the full report` ✅
- [E] `parked/blocked (❓/⏳) is a prefix-view over pending, NOT a status value` ✅
- [E] `secret gate: blocks a real AWS key (exit 2)` ✅
- [S] recommendation-first + brutal verdict — judgment 👁
- [S] decompose-park routing (high-blast never sits open; answers → minimal-blast children) — judgment 👁
- [S] wireframe-first · clean-as-you-go · one-line recap — judgment 👁

changes:
- 2026-07-23 delta reports: mutations one-line, full report at boundaries [R69; amends R47 cadence]
- 2026-07-22 capture hardened: at-rest redaction + rotation [R68; closes the R58 follow-up]
- 2026-07-22 machine shape [R66; reverses R62] · decompose-park [R65] · why-line provenance
- 2026-07-20 from UX.md P2 [R62]; "sync contract docs" → "sync flow pages"
