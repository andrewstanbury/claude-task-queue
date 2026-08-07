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
  ship-mode auto-commits to `autopilot/*`, never main) · `lib/companion.sh` (shared helpers).
- **Commands** — `setup` · `autopilot` · `ship-it` · `handoff` · `resume` · `review` ·
  `advise` · `redesign` · `docs` · `cover` · `burn-down` · `board`. Per-file responsibilities live
  in **[docs/MAP.md](./docs/MAP.md)** — read it before touching the core.
- **The hook/steering line (R28/R51)** — code only where it must *block* (secret gate),
  *inject context* (session-start), or *guarantee control-flow* (autopilot). Everything
  advisory is **STEERING**, not hooks. Don't add advisory prose as a hook, and don't add a
  hook for anything a document can say.

## Hard constraints

- **[docs/requirements.yaml](./docs/requirements.yaml) is the contract** — one entry per observable
  behaviour, each satisfying a need in [docs/needs.yaml](./docs/needs.yaml) and naming the tests
  that verify it; `dev/trace.sh` gates both directions. Add or reverse one *there*, visibly — never
  silently. Decisions and rejected options go to **[docs/adr/](./docs/adr/README.md)**; the evidence
  behind the older requirements is frozen in
  [adr/PROVENANCE.md](./docs/adr/PROVENANCE.md), which is history and is never edited.
- **Generic (R9).** No hardcoded language/framework/ecosystem allowlists — delegate
  *recognition* to the model, detect *structure* generically. Wide-audience product (R1).
- **Files ≤ 300 lines; best-effort hooks** (never break the action that triggered them — R68).
- **Hook work is bounded (R81).** A hook may read the project; it may not do work that grows
  with repo size, file count, history, or store age. Ceilings are **measured by `./check.sh`**,
  not asserted — an unmeasured budget is not a budget.
- **The hooks that fire are NOT the ones you edit.** They are served from
  `~/.claude/plugins/cache/*/companion/<version>/`; this tree is only the source. If that version
  is behind `plugins/companion/.claude-plugin/plugin.json`, every change you make here is **inert
  in this session** — check it before claiming a hook or command works, and name the version that
  actually ran. (This lives here, not in a hook, because a hook shipped inside the plugin is as
  stale as the lag it is trying to report.)
- Verify everything with **`./check.sh`** — CI runs the same script. It does **not** run the
  mutation gate: that is `./check.sh --mutate` (CI shards it). A green `check.sh` is evidence
  about tests, never about mutation coverage.

Project docs: **[docs/MAP.md](./docs/MAP.md)** · **[docs/ROADMAP.md](./docs/ROADMAP.md)** ·
**[AGENTS.md](./AGENTS.md)** · **[docs/adr/PROVENANCE.md](./docs/adr/PROVENANCE.md)** ·
**[docs/GLOSSARY.md](./docs/GLOSSARY.md)** (coined vocabulary, R37 — on-demand, not injected).
