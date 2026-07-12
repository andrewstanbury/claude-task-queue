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
  - `touch.sh` — PostToolUse: clean-as-you-touch, **format-only** — run the project's own
    formatter on the edited file (R25/R28; blast-radius + size are steering, not a hook). Plus
    `/companion:audit` for a whole-project sweep.
  - `session-start.sh` — SessionStart: injects STEERING + re-surfaces this repo's open tasks
    from an earlier session (scoped by the store's `.root` stamp; no cross-repo bleed) + surfaces
    the repo's `docs/LESSONS.md` gotchas if present (R30·d7).
  - `tq` — **THE task queue.** The companion owns its store (`~/.claude/companion/tasks`) and
    deliberately does **not** use Claude Code's native task tools (R8/R10). `tq report` reprints
    the queue on every `add`/`doing`/`done`.
  - `statusline.sh` — a `statusLine` command (not a hook): ⠋ beacon (animates only on activity —
    autopilot draining or a task in-progress; static ● when idle, R30·d9) · 🛡 secret gate · model ·
    ✈️ autopilot · ⇡in ⇣out · ◻ open · ❓ parked · ⏳ blocked tasks · project · branch (+ ↑ahead
    ↓behind). Wire it with `/companion:setup` (sets `refreshInterval:1` for the beacon).
  - **Autopilot** (R26) — `/companion:autopilot on\|off` sets a persisted per-repo flag;
    while on it's *enforced*: `stop-autopilot.sh` (Stop) auto-continues the drain and
    `ask-guard.sh` (PreToolUse) blocks asking. `lib/companion.sh` holds the shared helpers.
  - **The hook/steering line (R28)** — code only where it must *execute* (format) or *block*
    (secret gate) or *guarantee control-flow* (autopilot). Judgment (wireframe-first,
    weigh-against-direction, present-parked-first) and nudges (blast-radius, size, outcome-recap)
    are **STEERING**, not hooks. (This retired R27's edit-gates + intent reminder.)
  - **Commands** — `/companion:setup` (status line), `/companion:audit` (project sweep),
    `/companion:autopilot`, `/companion:ship-it` (verify→commit→push→merge), `/companion:resume`
    (manual re-surface of earlier open tasks), `/companion:advise` (R29 — independent brutal-honest
    critique of a target as recommendation-first options you pick one at a time, then queued).

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
