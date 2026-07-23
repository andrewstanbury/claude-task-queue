# flow:first-run
when: install → every session start
why: steering steers only if in context — one injection/session buys the whole agreement [R28 N1]

steps:
- `/companion:setup` wires the status line (once)
- SessionStart injects the working agreement (once/session; the STEERING core above the marker only — rationale never injected, ≤12KB check-gated) [R69]
- earlier-session open tasks re-surface, scoped to THIS repo (no cross-repo bleed)
- repo `LESSONS.md` gotchas surface if present [R30·d7]
- post-compaction: re-anchor with queue + next-pointer only, NOT full STEERING [R32]
- status line: beacon · version · feature icons (🛡✗ only when gate off, ✈️/✈️⚡, 📦) · 📋/❓/⏳ · model · tokens · project · branch

quality:
- steering loads once/session, never per-turn [N1]
- injected surface is check-gated (STEERING core ≤12KB, CLAUDE.md ≤4KB, LESSONS ≤6KB) [N1 R69]
- guardrail icons only when relevant; disabled gate is loud (🛡✗)

tests:
- [E] `session start: injects STEERING and resumes THIS repo's tasks only (scoped by .root)` ✅
- [E] `session start: re-anchors on a compaction with queue+pointer, NOT the full STEERING` ✅
- [E] `status line: renders version · model · tokens · task count · project · branch (no shield when gate on)` ✅
- [E] `steering off (per-repo flag): SessionStart drops the working agreement` ✅

changes:
- 2026-07-23 two-tier steering: core-only injection, budget enforced in check.sh [R69; partially reverses R66's trim-declined]
- 2026-07-22 machine shape [R66; reverses R62 human-first] — content preserved, prose dropped; why-line kept as provenance
- 2026-07-20 from UX.md P1 [R62]
