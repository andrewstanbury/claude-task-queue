# MAP — where things live

A compact `file → responsibility` index. Read [AGENTS.md](../AGENTS.md) for conventions and
[docs/ROADMAP.md](./ROADMAP.md) for direction. The 2026-07-11 rebuild (R24) collapsed the old
four plugins into one; this reflects the current tree.

## Repo root

| Path | Responsibility |
|---|---|
| `CLAUDE.md` | What this repo is + hard constraints + pointer to the steering doc. |
| `docs/REQUIREMENTS.md` | The **requirements ledger** — durable requirements/decisions with 🔒/🔓/⚰️ status. Source of truth. |
| `docs/ROADMAP.md` | Direction and backlog. |
| `docs/MAP.md` | This file. |
| `check.sh` | One-command gate: JSON valid · `claude plugin validate` · ShellCheck · secret scan · 300-line size guard · bats. CI runs this. |
| `.claude-plugin/marketplace.json` | Marketplace manifest (the one `companion` plugin). |

## plugins/companion — the whole system

| File | Responsibility |
|---|---|
| `STEERING.md` | **The steering layer** — the working agreement (queue discipline · challenge-the-ask + recommendation posture against the ledger · clean-as-you-go · autopilot). Prose the model reads once per session; not code, not a hook. |
| `bin/session-start.sh` | SessionStart hook: inject STEERING once + re-surface this repo's open tasks from an earlier session (scoped by each session store's `.root` stamp — no native transcript, no cross-repo bleed). |
| `bin/secret-guard.sh` | PreToolUse[Write\|Edit] hook: the one **enforced** content-gate — block a write that would commit a credential (`exit 2`). `CLAUDE_COMPANION_SECSCAN=0` disables. |
| `bin/touch.sh` | PostToolUse[Write\|Edit] hook: **clean-as-you-touch** — format the edited file (project's own formatter), surface its blast radius (dependents), flag over-budget size. Non-blocking. `CLAUDE_COMPANION_TOUCH=0` disables; `CLAUDE_COMPANION_SIZE_BUDGET` tunes size. |
| `commands/audit.md` | `/companion:audit` — on-demand whole-project sweep (size / debt / blast-radius hotspots), queues fixes via `tq`. |
| `bin/tq` | **THE task queue** — the companion owns its store (`~/.claude/companion/tasks`, NOT native tasks). `add`/`doing`/`note`/`done`/`list`/`report`; the report reprints on every `add`/`doing`/`done`. |
| `bin/resume.sh` | Manual resume (`/companion:resume`) — list this repo's open tasks from earlier sessions on demand (the SessionStart twin). |
| `commands/ship-it.md` | `/companion:ship-it` — verify → commit → push → PR/merge to the default branch. |
| `commands/resume.md` | `/companion:resume` — re-surface + reinstate earlier open tasks. |
| `bin/statusline.sh` | The status line (a `statusLine` command, not a hook): ⠋ animated beacon · 🛡 secret gate · 🎨/🔒 R27 edit-gates when armed · model · ✈️ autopilot · ⇡in ⇣out tokens · 📋 open tasks · project · branch. Read-only, no model cost; the beacon animates at `refreshInterval:1` (waking jq+git once/sec on idle). Wire with `/companion:setup`. |
| `bin/autopilot.sh` | Toggle the persisted per-repo autopilot flag (`on`/`off`/`status`). |
| `bin/stop-autopilot.sh` | Stop hook: while autopilot is on and non-deferred work remains, auto-continue the drain (no-progress capped); yields when only ❓/⏳ remain. `CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0` disables. |
| `bin/ask-guard.sh` | PreToolUse[AskUserQuestion] hook: deny asking while autopilot is on (decide-if-reversible or park as ❓); while off, presenting an AskUserQuestion disarms the R27 design + return-review gates. |
| `bin/prompt.sh` | UserPromptSubmit hook (R27): record the prompt as the intent of record + arm the design-preview marker on a visual prompt (`companion_looks_visual`). Side-effects only, no injection; silent under autopilot; `CLAUDE_COMPANION_GATES=0` disables. |
| `bin/work-guard.sh` | PreToolUse[Write\|Edit] hook (R27): **block** an edit until a visual change's wireframe is shown (design-preview) and until parked ❓ decisions are presented on return (return-review). Silent under autopilot; `CLAUDE_COMPANION_GATES=0` disables. |
| `bin/intent-note.sh` | PostToolUse[Write\|Edit] hook (R27): **advisory** — on the first edit of a request, surface the recorded intent as `additionalContext` (no block) so the outcome check isn't skipped. Once per request (a `reminded` marker prompt.sh clears); silent under autopilot; `CLAUDE_COMPANION_GATES=0` disables. |
| `lib/companion.sh` | Shared helpers (flag encoding/paths, open-task scan, gate state, visual/decisions detection) — sourced by every hook that reads state, so the encoding can't drift. |
| `commands/setup.md` · `commands/autopilot.md` | `/companion:setup` (status line) · `/companion:autopilot` (toggle). |
| `hooks/hooks.json` | Wires SessionStart · UserPromptSubmit · PreToolUse[Write\|Edit (secret-guard + work-guard) + AskUserQuestion] · PostToolUse[Write\|Edit (touch + intent-note)] · Stop (stop-autopilot). |
| `.claude-plugin/plugin.json` | Manifest + version. |
| `tests/companion.bats` | Tests the **enforced core only** — the secret gate, `tq`, session-start/resume, and the status line. (The steering layer is prose; it isn't unit-testable, and pretending it was is what the old system got wrong.) |
