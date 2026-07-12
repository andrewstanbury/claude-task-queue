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
  - `touch.sh` — PostToolUse: clean-as-you-touch — format the edited file, surface its blast
    radius, flag over-budget size (R25). Plus `/companion:audit` for a whole-project sweep.
  - `session-start.sh` — SessionStart: injects STEERING + re-surfaces this repo's open tasks
    from an earlier session (scoped by the store's `.root` stamp; no cross-repo bleed).
  - `tq` — **THE task queue.** The companion owns its store (`~/.claude/companion/tasks`) and
    deliberately does **not** use Claude Code's native task tools (R8/R10). `tq report` reprints
    the queue on every `add`/`doing`/`done`.
  - `statusline.sh` — a `statusLine` command (not a hook): ⠋ animated beacon · 🛡 secret gate ·
    🎨/🔒 R27 edit-gates when armed · model · ✈️ autopilot · ⇡in ⇣out · 📋 open tasks · project ·
    branch. Wire it with `/companion:setup` (sets `refreshInterval:1` for the beacon).
  - **Autopilot** (R26) — `/companion:autopilot on\|off` sets a persisted per-repo flag;
    while on it's *enforced*: `stop-autopilot.sh` (Stop) auto-continues the drain and
    `ask-guard.sh` (PreToolUse) blocks asking. `lib/companion.sh` holds the shared helpers.
  - **Gates** (R27) — two enforced blocks + one advisory reminder for three STEERING clauses.
    `prompt.sh` (UserPromptSubmit) records the intent of record + arms a design-preview marker on
    a visual prompt; `work-guard.sh` (PreToolUse[Write\|Edit]) **blocks** an edit until a visual
    change's wireframe is shown and until parked ❓ decisions are presented on return (both clear
    when the model presents — `ask-guard.sh` disarms); `intent-note.sh` (PostToolUse[Write\|Edit])
    surfaces the recorded intent once per request, on the first edit, as **advisory** context (no
    block). All stay silent under autopilot, disable with `CLAUDE_COMPANION_GATES=0`.
  - **Commands** — `/companion:setup` (status line), `/companion:audit` (project sweep),
    `/companion:autopilot`, `/companion:ship-it` (verify→commit→push→merge), `/companion:resume`
    (manual re-surface of earlier open tasks).

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
