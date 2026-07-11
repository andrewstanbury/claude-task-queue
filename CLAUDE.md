# CLAUDE.md

This repo is the source of **`companion`** — one Claude Code plugin: a *steering document*
plus a *tiny enforced core*. (It replaced a four-plugin system on 2026-07-11; see **R24** in
the ledger.)

## The working agreement lives in one file

**[plugins/companion/STEERING.md](./plugins/companion/STEERING.md)** is how Claude works on
any project the companion is installed in — queue discipline, the brutal-honest
recommendation posture, clean-as-you-go standards, autopilot. When installed, the companion's
SessionStart hook puts it in context once per session. **When working *on this repo*, read it —
it governs how you work here too.**

## Architecture (R24) — two kinds of thing, kept separate

- **Steering** (prose the model reads, ignorable-by-nature) → `STEERING.md`. One file, not
  scattered across hooks.
- **Enforced core** (must execute or block) → `plugins/companion/bin/`:
  - `secret-guard.sh` — PreToolUse: blocks a write that would commit a credential (`exit 2`).
    The one real content-gate; a leaked key is irreversible.
  - `session-start.sh` — SessionStart: injects STEERING + re-surfaces this repo's open tasks
    from an earlier session (cross-session resume). Repo-scoped (no cross-project bleed).
  - `tq` — the task-queue fallback CLI for models whose native task tools are gated off
    (`tengu_vellum_ash`: Opus 4.8 / Sonnet 5 / Fable 5). Writes the native store; `tq report`
    prints the queue on each `done`.

Keep the split honest: don't add advisory prose as a hook, and don't add a hook for anything
a document can say.

## Hard constraints

- **Requirements ledger is the source of truth.** Durable requirements/decisions live in
  **[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)** with status (🔒 locked / 🔓 open / ⚰️
  retired). Reverse one *there*, as a visible trade-off — never silently.
- **Generic (R9).** No hardcoded language/framework/ecosystem allowlists — delegate
  *recognition* to the model, detect *structure* generically. This is a wide-audience product (R1).
- **Files ≤ 300 lines; best-effort hooks** (never break the action that triggered them).
- Verify everything with **`./check.sh`** — CI runs the same script.

Project docs: **[docs/MAP.md](./docs/MAP.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[AGENTS.md](./AGENTS.md)**, **[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)**.
