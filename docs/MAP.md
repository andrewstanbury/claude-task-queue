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
| `bin/statusline.sh` | The status line (a `statusLine` command, not a hook): 🛡 secret gate · model · ⇡in ⇣out tokens · 📋 open tasks · project · branch. Read-only, zero model cost. Wire with `/companion:setup`. |
| `commands/setup.md` | `/companion:setup` — wires the status line into settings.json. |
| `hooks/hooks.json` | Wires the two hooks (SessionStart, PreToolUse). |
| `.claude-plugin/plugin.json` | Manifest + version. |
| `tests/companion.bats` | Tests the **enforced core only** — the secret gate, `tq`, session-start/resume, and the status line. (The steering layer is prose; it isn't unit-testable, and pretending it was is what the old system got wrong.) |
