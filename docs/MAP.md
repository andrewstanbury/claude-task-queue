# MAP — where things live

A compact `file → responsibility` index. Read [AGENTS.md](../AGENTS.md) for conventions and
[docs/ROADMAP.md](./ROADMAP.md) for direction. The 2026-07-11 rebuild (R24) collapsed the old
four plugins into one; this reflects the current tree. The plugin runs one loop —
**propose → queue → drain** (R52): `session-start` seeds it · `tq` holds it · autopilot drains it ·
the secret gate guards every write (see ROADMAP "The loop").

## Repo root

| Path | Responsibility |
|---|---|
| `CLAUDE.md` | What this repo is + hard constraints + pointer to the steering doc. |
| `docs/REQUIREMENTS.md` | The **requirements ledger** — durable requirements/decisions with 🔒/🔓/⚰️ status. Source of truth. |
| `docs/ROADMAP.md` | Direction and backlog. |
| `docs/MAP.md` | This file. |
| `docs/GLOSSARY.md` | The companion's **coined vocabulary** — a *term → meaning* index (R37). Claude-facing, terse, **loaded on demand** (not injected each session); vocabulary only (gotchas → LESSONS, decisions → ledger). |
| `check.sh` | One-command gate: JSON valid · `claude plugin validate` · **version match (each `plugin.json` == its marketplace entry)** · ShellCheck · secret scan · 300-line size guard · bats. CI runs this. |
| `.claude-plugin/marketplace.json` | Marketplace manifest (the one `companion` plugin). |

## plugins/companion — the whole system

| File | Responsibility |
|---|---|
| `STEERING.md` | **The steering layer** — the working agreement (queue discipline · challenge-the-ask + recommendation posture against the ledger · clean-as-you-go · autopilot). Prose the model reads once per session; not code, not a hook. |
| `bin/session-start.sh` | SessionStart hook: inject STEERING once + re-surface this repo's open tasks from an earlier session (scoped by each session store's `.root` stamp — no native transcript, no cross-repo bleed) + surface the repo's `docs/LESSONS.md` gotchas if present (R30·d7). Fires on `source=compact` too → **re-anchors after a context compaction** (R30·d2), with a compaction-aware lead. |
| `bin/secret-guard.sh` | PreToolUse[Write\|Edit] hook: the one **enforced** content-gate — block a write that would commit a credential (`exit 2`). `CLAUDE_COMPANION_SECSCAN=0` disables. |
| `docs/LESSONS.md` | This repo's accumulated **gotchas** (portability/test/CI traps) — model-maintained, injected each session by `session-start.sh` (R30·d7). Gotchas only; decisions live in the ledger, work in the queue. |
| `commands/advise.md` | `/companion:advise` (R29/R32) — independent brutal-honest **critique** of a target (default: whole project) via a critic panel; recommendation-first, one at a time, then queued. **Critique only — never edits.** Also the whole-project cleanliness sweep (absorbed `/companion:audit`, R32). |
| `commands/regen.md` | `/companion:regen <target>` (R54) — contract-preserving ground-up rebuild of **one bounded** target against the logged contract (`UX.md`+`NFR.md`), gated on the invariant checks (`INVARIANTS.md`+`check.sh`), applied on a branch, re-checked, auto-revert on red. **Edits.** |
| `commands/redesign.md` | `/companion:redesign` (R55) — **whole-app** contract-preserving rebuild as a sequence of bounded, check-gated `regen` passes, with an up-front invariant-coverage gate (D0). **Edits.** |
| `bin/tq` | **THE task queue** — the companion owns its store (`~/.claude/companion/tasks`, NOT native tasks). `add [--done "<acceptance>"]`/`doing`/`note`/`done-when`/`done`/`list`/`report`; a task's `done_when` (R30·d1) is its acceptance test, rendered in the report + resume so it survives a compaction. Report reprints on every state change. |
| `bin/resume.sh` | Manual resume (`/companion:resume`) — list this repo's open tasks from earlier sessions on demand (the SessionStart twin). |
| `commands/ship-it.md` | `/companion:ship-it` — verify → **state the case** (risks / what-changes / R-IDs; devil's-advocate for consequential changes, R30·d6) → commit → push → merge to the default branch → **prune merged branches** (R35: delete the shipped branch local+remote, sweep `--merged` branches with `-d`; shared-repo confirm). |
| `commands/resume.md` | `/companion:resume` — re-surface + reinstate earlier open tasks. |
| `commands/review.md` | `/companion:review` (R38) — walk the `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first (reusing the advise loop, R29), and write picks back to `tq` before new work. **Runs automatically when autopilot is turned off.** Parked+blocked only; defer/bail allowed; no-op when empty. |
| `bin/statusline.sh` | The status line (a `statusLine` command, not a hook), grouped by plugin-relevance (R34): ⠋ beacon · `│` 🛡 gate · ✈️ autopilot · 📦 ship-mode `│` (active features) · `│` 📋 open · ❓ parked · ⏳ blocked `│` (the queue, own section) · model · ⇡in ⇣out · project · branch (+ ↑ahead ↓behind). Read-only; beacon animates at `refreshInterval:3`. Wire with `/companion:setup`. |
| `bin/autopilot.sh` | Toggle the persisted per-repo autopilot flag (`on`/`off`/`status`), and **ship-mode** (`ship on`/`off`/`status`, R34). |
| `bin/stop-autopilot.sh` | Stop hook: while autopilot is on and non-deferred work remains, auto-continue the drain (no-progress capped); yields when only ❓/⏳ remain. **Ship-mode (R34):** also auto-commits each turn's work to an `autopilot/*` branch (never the default, never a push), best-effort. `CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0` disables the continue. |
| `bin/ask-guard.sh` | PreToolUse[AskUserQuestion] hook: deny asking while autopilot is on (decide-if-reversible or park as ❓). Silent when autopilot is off. |
| `lib/companion.sh` | Shared helpers (flag encoding/paths, repo root, open-task scan) — sourced by autopilot, the Stop hook, ask-guard, session-start/resume, and the status line, so the encoding can't drift. |
| `commands/setup.md` · `commands/autopilot.md` | `/companion:setup` (status line) · `/companion:autopilot` (toggle). |
| `hooks/hooks.json` | Wires SessionStart · PreToolUse[Write\|Edit (secret-guard) + AskUserQuestion (ask-guard)] · Stop (stop-autopilot). |
| `.claude-plugin/plugin.json` | Manifest + version. |
| `tests/companion-{core,hud,fuzz}.bats` | Test the **enforced core only** — `core` (secret gate · `tq` · session-start/resume · autopilot), `hud` (status line), `fuzz` (every hook survives empty/garbage/huge/emoji stdin — R30·d8). The steering layer is prose; it isn't unit-testable, and pretending it was is what the old system got wrong. |
