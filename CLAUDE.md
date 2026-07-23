# CLAUDE.md

This repo is the source of **`companion`** — a Claude Code plugin: a *steering document*
plus a *tiny enforced core*, organized as one loop: **propose → queue → drain** (R52).

## The working agreement lives in one file

**[plugins/companion/STEERING.md](./plugins/companion/STEERING.md)** is how Claude works on
any project the companion is installed in — queue discipline, the brutal-honest
recommendation posture, clean-as-you-go, autopilot. The companion's SessionStart hook puts it
in context once per session. **When working *on this repo*, read it — it governs how you
work here too.**

## Architecture (R24) — two kinds of thing, kept separate

- **Steering** (prose the model reads, ignorable-by-nature) → `STEERING.md`. One file, not
  scattered across hooks.
- **Enforced core** (must block, inject, or guarantee control-flow) → `plugins/companion/bin/`:
  `secret-guard.sh` (blocks credential writes) · `session-start.sh` (injects STEERING +
  cross-session resume + LESSONS; re-anchors after compaction) · `tq` (**THE task queue** —
  the companion owns its store; never native task tools, R8/R10) · `statusline.sh` ·
  autopilot (`stop-autopilot.sh` auto-continues the drain, `ask-guard.sh` blocks asking;
  ship-mode auto-commits to `autopilot/*`, never main) · `capture.sh` (write-only prompt
  sink, zero-token) · `lib/companion.sh` (shared helpers).
- **Commands** — `setup` · `autopilot` · `ship-it` · `resume` · `review` · `advise` ·
  `redesign` · `docs` · `cover`. Per-file responsibilities live in
  **[docs/MAP.md](./docs/MAP.md)** — read it before touching the core.
- **The hook/steering line (R28/R51)** — code only where it must *block* (secret gate),
  *inject context* (session-start), or *guarantee control-flow* (autopilot). Everything
  advisory is **STEERING**, not hooks. Don't add advisory prose as a hook, and don't add a
  hook for anything a document can say.

## Hard constraints

- **Requirements ledger is the source of truth.** Durable requirements/decisions live in
  **[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)** with status (🔒 locked / 🔓 open / ⚰️
  retired). Reverse one *there*, as a visible trade-off — never silently.
- **Generic (R9).** No hardcoded language/framework/ecosystem allowlists — delegate
  *recognition* to the model, detect *structure* generically. Wide-audience product (R1).
- **Files ≤ 300 lines; best-effort hooks** (never break the action that triggered them — R68).
- Verify everything with **`./check.sh`** — CI runs the same script.

Project docs: **[docs/MAP.md](./docs/MAP.md)** · **[docs/ROADMAP.md](./docs/ROADMAP.md)** ·
**[AGENTS.md](./AGENTS.md)** · **[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)** ·
**[docs/GLOSSARY.md](./docs/GLOSSARY.md)** (coined vocabulary, R37 — on-demand, not injected).
