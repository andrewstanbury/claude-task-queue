# CLAUDE.md

This repo is the source of **`companion`** — a portable task-queue + steering system, shipped as
a Claude Code plugin: one steering doc, a small MCP server, four hooks (**R100/Pass 6**, landing
in bounded passes tracked in `tq` — see [docs/adr/README.md](./docs/adr/README.md) R100/R105).

## The working agreement lives in one file

**[plugins/companion/STEERING.md](./plugins/companion/STEERING.md)** is how Claude works on
any project the companion is installed in — queue discipline, the brutal-honest
recommendation posture, clean-as-you-go, autopilot. **Injected automatically at session start
again** (R105) — or `/companion:resume` any time mid-session. **On this repo, it governs how you
work here too.**

## Architecture (R100/R105/R111) — steering, a portable core, four re-enforced hooks

- **Steering** (prose the model reads, ignorable-by-nature, advisory) → `STEERING.md`.
- **The portable core** — `plugins/companion/bin/` + `mcp-server/`: `tq` (**THE task queue**,
  R8/R10; also an MCP server, `companion-tq`, for any MCP-capable client) · advisory
  `check-secrets.sh` (was an enforced block) · `resume.sh` (on-demand triage pull) ·
  `ship-checkpoint.sh` (ship-mode's commit logic, manual) · `statusline.sh` · `autopilot.sh`.
- **Four hooks** — `prompt-continue.sh` (UserPromptSubmit) · `session-start.sh` (STEERING+tasks
  reach every session) · `ask-guard.sh` (PreToolUse[AskUserQuestion]: denies+parks under autopilot) ·
  `stop-autopilot.sh` (Stop, **restored**: refuses the stop while autopilot is armed and a
  *startable* task remains, and on a DRY queue with burn-down armed fires the R82 hand-off — bounded;
  details in MAP).
  `secret-guard.sh`/`contract-guard.sh` stay retired.
  See [docs/adr/README.md](./docs/adr/README.md) R100/R105/R107/R111.
- **Commands** — `setup` · `autopilot` · `ship-it` · `handoff` · `resume` · `review` ·
  `advise` · `redesign` · `docs` · `cover` · `burn-down` · `board`. Per-file responsibilities live
  in **[docs/MAP.md](./docs/MAP.md)** — read it before touching the core.

## Hard constraints

- **[docs/requirements.yaml](./docs/requirements.yaml) is the contract** — one entry per observable
  behaviour, each satisfying a need in [docs/needs.yaml](./docs/needs.yaml) and naming the tests
  that verify it; `dev/trace.sh` gates both directions. Add or reverse one *there*, visibly — never
  silently. Decisions and rejected options go to **[docs/adr/](./docs/adr/README.md)**; the evidence
  behind the older requirements is frozen in
  [adr/PROVENANCE.md](./docs/adr/PROVENANCE.md), which is history and is never edited.
- **Generic (R9).** No hardcoded language/framework/ecosystem allowlists — delegate *recognition*
  to the model, detect *structure* generically. Wide-audience product (R1).
- **Files ≤ 300 lines; best-effort hooks** (never break the action that triggered them — R68).
- **Hook work is bounded (R81).** A hook may read the project; it may not do work that grows
  with repo size, file count, history, or store age. Ceilings are **measured by `./check.sh`**,
  not asserted — an unmeasured budget is not a budget.
- **The hooks that fire are NOT the ones you edit.** Served from
  `~/.claude/plugins/cache/*/companion/<version>/`; this tree is only the source. If that version
  lags `plugins/companion/.claude-plugin/plugin.json`, every change here is **inert this
  session** — check before claiming a hook or command works, name the version that actually ran.
  Not hypothetical: a still-cached `contract-guard.sh` blocked real edits mid-R100-rewrite.
- Verify with **`./check.sh`** — CI runs the same script, but not the mutation gate
  (`./check.sh --mutate`, CI shards it). Green `check.sh` is evidence about tests, never mutation
  coverage.

Project docs: **[docs/MAP.md](./docs/MAP.md)** · **[docs/ROADMAP.md](./docs/ROADMAP.md)** ·
**[AGENTS.md](./AGENTS.md)** · **[docs/adr/PROVENANCE.md](./docs/adr/PROVENANCE.md)** ·
**[docs/GLOSSARY.md](./docs/GLOSSARY.md)** (coined vocabulary, R37 — on-demand, not injected).
