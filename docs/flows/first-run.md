# flow:first-run
when: install → automatic at every session start (again, R100/Pass 6) → also on demand via `/companion:resume`
why: steering steers only if in context — R100/Pass 2 made that the model's own judgment call
  every time, and the owner watched that fail; R100/Pass 6 (docs/adr/README.md R105) restores the
  guarantee via `session-start.sh`, while `/companion:resume` stays available mid-session [R28 N1]

steps:
- `/companion:setup` wires the status line (once)
- `session-start.sh` (SessionStart hook, reinstated) injects the working agreement automatically
  at a fresh session start (the STEERING core above the marker only — rationale never printed,
  check-gated) [R69] — `/companion:resume` prints the same content on demand, any time, and also
  disarms autopilot as part of pulling it (session-start.sh deliberately does not)
- earlier-session open tasks re-surface, scoped to THIS repo (no cross-repo bleed)
- repo `LESSONS.md` gotchas surface if present [R30·d7]
- a FRESH start gets the full core + live queue; a POST-COMPACTION re-anchor gets a short message
  instead of the full core (token cost, R30·d2) but the SAME cheap report tail (tasks, version-lag,
  LESSONS, R93 out-of-band changes, rework) — a compaction is itself the state clear R93 exists to
  survive, so that half is never abbreviated
- status line: beacon · version · feature icons (🛡✗ only when gate off, ✈️/✈️⚡, 📦) · 📋/❓/⏳ · 5h/7d account rate-limit bars, each labelled with its ↻ reset countdown (absent for API-key users and before the first response; rolling windows, NOT a billing cycle) and the 7d carrying a ▴/▾ on-pace marker [R76] · model · tokens · project · branch (unaffected by R100/R105 — the status line was never a hook)

quality:
- steering is injected automatically AND available on demand — never per-turn [N1]
- printed surface is check-gated (STEERING core ≤12KB, CLAUDE.md ≤4KB, LESSONS ≤6KB) [N1 R69]
- guardrail icons only when relevant; disabled gate is loud (🛡✗)

tests:
- [E] `session-start: fresh start injects the FULL STEERING core + carried tasks, unlike resume it does NOT clear autopilot` ✅
- [E] `session-start: post-compaction re-anchor is SHORT — queue + posture, not the full STEERING core` ✅
- [E] `session-start: compact re-anchor carries the SAME version-lag + rework as a fresh start (R93 — a compaction IS a state clear)` ✅
- [E] `resume: prints STEERING and resumes THIS repo's tasks only (scoped by .root) — R39` ✅
- [E] `resume: shows the FULL STEERING core alongside the live queue — no abbreviated path left to pick (R100/Pass 2)` ✅
- [E] `status line: renders version · model · tokens · task count · project · branch (no shield when gate on)` ✅
- [E] `steering off (per-repo flag): resume drops the working agreement (tasks/lessons unaffected, R50)` ✅
- [E] `session-start: steering=off drops the working agreement, carried tasks unaffected (R50)` ✅
- [E] `status line: 5h + 7d usage bars render both windows from .rate_limits (R76)` ✅
- [E] `status line: no .rate_limits (API-key user / pre-first-response) renders NO bar (R76)` ✅
- [E] `status line: one window absent renders ONLY the other — no field shift (R76)` ✅
- [E] `status line: the ▴/▾ pace marker says whether the 7d window will be spent (R76)` ✅
- [E] `status line: a FAILED clock suppresses the countdown, never renders a 56-year one (R76/R68)` ✅

changes:
- 2026-08-08 SessionStart hook REINSTATED (owner-decided: "guaranteed context delivery" outweighed
  portability for this one guarantee) — `session-start.sh` injects automatically again, sharing
  content with `/companion:resume` via `lib/resume-report.sh` rather than duplicating it; the
  post-compaction abbreviation is back too, now carrying the full cheap report tail instead of
  being fully abbreviated [R100/Pass 6, docs/adr/README.md R105, re-reverses R39/R69/R80/R93]
- 2026-08-08 SessionStart hook retired; `/companion:resume` absorbs its content and becomes the
  ONLY entry point, called on demand — no more automatic firing, no more separate abbreviated
  post-compaction path [R100/Pass 2, reverses R39/R69/R80/R93's injection guarantee]
- 2026-07-25 status line gains 5h/7d ACCOUNT rate-limit bars — free from the payload; rolling windows, not a billing cycle [R76]
- 2026-07-31 the ↻ reset countdown becomes always-on and TAKES the label slot from the 5h/7d names (they fall back in when no timestamp is usable); spaces added around each bar [R76]
- 2026-07-31 the 7d bar gains a ▴/▾ on-pace marker — derived-exact from the window length + resets_at, never sampled; a pre-merge devil's-advocate pass caught its bias INVERTED and it now ceilings elapsed so ▴ cannot lie [R76]
- 2026-07-23 two-tier steering: core-only injection, budget enforced in check.sh [R69; partially reverses R66's trim-declined]
- 2026-07-22 machine shape [R66; reverses R62 human-first] — content preserved, prose dropped; why-line kept as provenance
- 2026-07-20 from UX.md P1 [R62]
