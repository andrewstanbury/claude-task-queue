# CLAUDE.md

This repo is the source of **`companion`** — a Claude Code plugin: a *steering document*
plus a *tiny enforced core*, organized as one loop: **propose → queue → drain** (R52). (It
replaced a four-plugin system on 2026-07-11; see **R24**. Single-plugin packaging is the
current shape, not a hard requirement — R52 freed it while keeping R24's anti-sprawl principle.)

## The working agreement lives in one file

**[plugins/companion/STEERING.md](./plugins/companion/STEERING.md)** is how Claude works on
any project the companion is installed in — queue discipline, the brutal-honest
recommendation posture, clean-as-you-go standards, autopilot. When installed, the companion's
SessionStart hook puts it in context once per session. **When working *on this repo*, read it —
it governs how you work here too.**

## Architecture (R24) — two kinds of thing, kept separate

- **Steering** (prose the model reads, ignorable-by-nature) → `STEERING.md`. One file, not
  scattered across hooks.
- **Enforced core** (must block, inject, or guarantee control-flow) → `plugins/companion/bin/`:
  - `secret-guard.sh` — PreToolUse: blocks a write that would commit a credential (`exit 2`).
    The one real content-gate; a leaked key is irreversible.
  - `session-start.sh` — SessionStart: injects STEERING + re-surfaces this repo's open tasks
    from an earlier session (scoped by the store's `.root` stamp; no cross-repo bleed) + surfaces
    the repo's `docs/LESSONS.md` gotchas if present (R30·d7). Fires on `compact` too, so it
    **re-anchors after a compaction** (R30·d2) — re-injecting the queue + LESSONS (not the full
    STEERING, R32).
  - `tq` — **THE task queue.** The companion owns its store (`~/.claude/companion/tasks`) and
    deliberately does **not** use Claude Code's native task tools (R8/R10). `tq report` reprints
    the queue on every `add`/`doing`/`done`.
  - `statusline.sh` — a `statusLine` command (not a hook), grouped by plugin-relevance (R34):
    ⠋ beacon (animates on activity, R30·d9) · **│ 🛡 gate ✈️ autopilot 📦 ship-mode │** (active
    features) · **│ 📋 open ❓ parked ⏳ blocked │** (the queue, its own section) · model · ⇡in ⇣out ·
    project · branch (+ ↑ahead ↓behind). Wire it with `/companion:setup` (`refreshInterval:3`).
  - **Autopilot** (R26) — `/companion:autopilot on\|off` sets a persisted per-repo flag;
    while on it's *enforced*: `stop-autopilot.sh` (Stop) auto-continues the drain and
    `ask-guard.sh` (PreToolUse) blocks asking. **Ship-mode** (R34, `autopilot ship on\|off`): while
    on, the Stop hook auto-commits each turn's work to an `autopilot/*` branch (never main, no
    push) for review + `/companion:ship-it`. `lib/companion.sh` holds the shared helpers.
  - **The hook/steering line (R28, sharpened by R51)** — code only where it must *block*
    (secret gate), *inject context* (session-start), or *guarantee control-flow* (autopilot).
    Everything advisory — judgment (wireframe-first, weigh-against-direction, present-parked-first)
    *and* nudges (blast-radius, size, outcome-recap, the context-triggered recommendations) — is
    **STEERING**, not hooks. (R27 retired the edit-gates + intent reminder; **R51 retired the last
    *execute* hook, `touch.sh` — formatting is now steering-nudged, not enforced**.) Whole-project
    cleanliness sweeps live in `/companion:advise` (which absorbed `/companion:audit`, R32).
  - **Commands** — `/companion:setup` (status line), `/companion:autopilot`,
    `/companion:ship-it` (verify→commit→push→merge; review-optimized output — clean
    messages, curated commits, structured PR bodies, R40), `/companion:resume`
    (R38/R39 — triage handoff: step 1 turns autopilot off + re-surfaces earlier tasks *preserving
    their ❓/⏳/📋 class* (absorbs the former `/companion:resume`, folded 2026-07-17), then walks the
    parked/blocked pile recommendation-first, auto-runs when autopilot is turned off),
    `/companion:advise` (R29/R32 — independent brutal-honest
    critique of a target as recommendation-first options you pick one at a time, then queued — it
    *only* critiques), `/companion:redesign` (R54/R55 —
    whole-app contract-preserving rebuild against the logged UX+QA contract, in bounded check-gated
    passes; **runs `/companion:document` first**, and the per-module rebuild engine is inlined — a
    single bounded target is one pass, absorbing the former `/companion:regen`, R55 amended 2026-07-18),
    `/companion:document` (R41 — the producer side of advise: scan an existing repo for
    load-bearing, undocumented decisions and record them tiered check › 🔒 › 🔓, with
    strength-of-why + provenance, so advise stops guessing and can't reverse an undocumented choice).
    *(The `/companion:features` toggle CLI was removed 2026-07-18, R50 — per-repo secret/steering are
    now set by a hand-written flag or the `CLAUDE_COMPANION_SECSCAN=0` env; autopilot/ship keep their
    own command. The flag mechanism + enforced-core readers are unchanged.)*

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
**[AGENTS.md](./AGENTS.md)**, **[docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)**,
**[docs/GLOSSARY.md](./docs/GLOSSARY.md)** (coined vocabulary, R37 — on-demand, not injected).
