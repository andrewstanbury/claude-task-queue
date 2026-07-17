# GLOSSARY — the companion's coined vocabulary

Claude-facing (R37). A *coined domain term → its meaning*: when a concept recurs and its plain
description is long, one word carries twenty and naming stays consistent. Consult before naming
something new; reuse a term rather than mint a synonym. **Vocabulary only** — gotchas are in
[LESSONS.md](./LESSONS.md), decisions in [REQUIREMENTS.md](./REQUIREMENTS.md), work in the `tq` queue.
Loaded on demand (not injected each session).

| Term | Means |
|---|---|
| **the companion** | The one plugin this repo builds (`plugins/companion`) — a steering document + a tiny enforced core. |
| **steering** | Prose the model reads once per session (`STEERING.md`) and applies by judgment. Ignorable-by-nature; the honest home for anything not enforced. |
| **enforced core** | The `bin/` code that must *execute or block* — the only thing that isn't steering. |
| **the hook/steering line** (R28) | The deciding rule for where a behavior lives: *execute or block → hook; judgment or nudge → steering.* |
| **the queue / `tq`** | The companion's self-owned task store + CLI — deliberately **not** Claude Code's native task tools (R8/R10). |
| **done-when** | A task's own acceptance test (`tq add --done`) — re-read after a compaction, it re-derives the next action instead of guessing (R30·d1). |
| **the ledger** | `REQUIREMENTS.md` — the single source of truth for durable requirements/decisions (R2). |
| **R-ID** | A ledger entry (e.g. R28), with status **🔒 locked / 🔓 open / ⚰️ retired**. Recommendations cite the R-IDs they touch (R5). |
| **blast radius** | What a change ripples into (callers, dependents) — grep the symbol, cover them before changing (criterion 1). |
| **the secret gate** | The PreToolUse floor that blocks a write committing a credential (`secret-guard.sh`) — the one sanctioned edit-breaker (R19). |
| **the beacon** | The status-line spinner (`⠋`) that animates *on activity only*, static when idle (R30·d9). |
| **autopilot / keep-going mode** | The persisted, enforced "keep draining the queue without stopping" flag — *momentum, not owner-absence* (R26/R36). |
| **park / `❓ [parked]`** | Under autopilot, defer a decision that's the owner's (direction, design, taste, irreversible) instead of stopping or auto-deciding (R33). |
| **blocked / `⏳ [blocked]`** | A task needing a manual owner-only action (e.g. a human playtest) — captured silently, resurfaced on check-in (R31). |
| **ship-mode** | While autopilot is on, auto-commit each turn's work to an `autopilot/*` branch — never the default, never a push (R34). |
| **the parked pile** | The `❓`/`⏳` set the owner reviews on check-in, presented recommendation-first when autopilot goes off. |
| **self-describing project** | The precondition that a repo carries a map · ledger · stack-notes · glossary before substantive work (ROADMAP criterion 0). |
