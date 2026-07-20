# First run

**When:** you install `companion` and start working — every session begins here.

## Happy path
1. Wire the status line once with `/companion:setup`.
2. On every session start, the working agreement (how Claude queues, decides, keeps clean) loads once into context.
3. Tasks left open in *this repo* from an earlier session re-surface — scoped to this repo, no cross-repo bleed.
4. Repo gotchas (`LESSONS.md`) surface if the repo has them.
5. After a context compaction, the queue + next-pointer re-anchor so work continues instead of drifting.
6. A persistent status line shows: beacon · version · active-feature icons (`🛡✗` only when the gate is off, ✈️/✈️⚡ autopilot, 📦 ship-mode) · 📋/❓/⏳ queue · model · tokens · project · branch.

## Quality bar
- The steering doc loads **once per session**, not per turn (token efficiency — see [`_quality-bar.md`](./_quality-bar.md) N1).
- Guardrail icons are shown only when relevant; a disabled gate is loud (`🛡✗`).

## Tests
- [E] `session start: injects STEERING and resumes THIS repo's tasks only (scoped by .root)` ✅
- [E] `session start: re-anchors on a compaction with queue+pointer, NOT the full STEERING` ✅
- [E] `status line: renders version · model · tokens · task count · project · branch (no shield when gate on)` ✅
- [E] `steering off (per-repo flag): SessionStart drops the working agreement` ✅

## Changes
- 2026-07-20 — migrated from UX.md Path 1 into a flow page (R62).
