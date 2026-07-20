# Claude Code companion

One [Claude Code](https://claude.com/claude-code) plugin that makes Claude a disciplined
pair: it turns your requests into a live task queue, decides with **brutally honest,
multiple-choice recommendations** that name what each option would change, keeps code clean
as it changes it, and keeps working on its own without stopping — while a small enforced core stops
committed secrets and remembers unfinished work between sessions.

It's built around one idea: **steering is a document, enforcement is code, and the two should
never be confused.** Almost everything the companion "does" is one steering document Claude
reads once per session. The only things that are code are the things that must actually
*execute or block*.

| Part | What it is |
|---|---|
| **Steering** ([STEERING.md](plugins/companion/STEERING.md)) | The working agreement: how Claude queues work, challenges the ask, recommends against a **requirements ledger** (🔒 locked / 🔓 open), keeps changes clean, and runs autonomously without stopping. Put in context once per session. |
| **Secret gate** | Before any write, blocks a file that would commit a credential — the one thing native permissions can't scan. A leaked key is irreversible. |
| **Resume / Review** | `/companion:resume` re-surfaces this repo's unfinished tasks (session pickup; also automatic at session start). `/companion:review` walks the backlog waiting on you — parked ❓ decisions + blocked ⏳ actions — one at a time, and runs when you turn autopilot off. |
| **Ship** | `/companion:ship-it` — verify your gate, commit, push, and open/merge a PR. |
| **`tq`** | The task queue — self-owned, so it works everywhere (including the newest models where Claude's built-in task tracking is switched off) and doesn't depend on Claude Code internals. It reprints the queue on every change, so the CLI always shows what's in progress and next. |
| **Autopilot** | `/companion:autopilot on` — Claude keeps working the queue **without stopping**, parking decisions it shouldn't make alone. It's "keep going," *not* "you're away": keep it on and keep queuing tasks while you watch. Enforced (won't stop or ask while on), persists across restarts. `ship on` also auto-commits work to an `autopilot/*` branch; `decisive on` auto-picks the recommended option for reversible decisions (recording each) and parks only the irreversible. |
| **Status line** | One glance line, grouped with `:` dividers: ⠋ beacon · `v<x.y.z>` · `:` active features `:` (each shown only when relevant — `🛡️✗` only if the gate is off, ✈️ autopilot, 📦 ship-mode; omitted entirely when none) · `:` 📋 ❓ ⏳ `:` (the queue) · model · ⇡⇣ tokens · project · ⎇ branch · ↑↓ ahead/behind. Wire it once with `/companion:setup` (legend below). |

Bash + `jq`, zero build, one install.

## Commands

- **`/companion:setup`** — wire the status line into your settings (one-time).
- **`/companion:advise [target]`** — an independent, brutally-honest **critique** of a target
  (default: the whole project), presented as recommendation-first choices, then queued. Doubles
  as a cleanliness sweep (size · debt · blast-radius · perf). Critique only — never edits.
- **`/companion:redesign`** *(experimental)* — a contract-preserving rebuild of the whole app from
  your logged UX + quality-attribute contract, as bounded, check-gated passes. It runs
  **`/companion:document` first** to log the contract, applies on a branch, stays gated on your
  safety checks, auto-reverts on red, and confirms each step. A single bounded target is just one
  pass (this absorbed the former `/companion:regen`).
- **`/companion:autopilot on|off`** — keep working the queue without stopping — keep it on and keep queuing tasks.
  Add **`autopilot ship on`** to auto-commit completed work to an `autopilot/*` branch (reversible,
  never main, no push) for you to review + ship on return. Add **`autopilot decisive on`** to have it
  **pick the recommended option** for reversible decisions (design/wording included) and record each,
  parking only what's irreversible — shown as `✈️⚡`; review the auto-picks any time with `/companion:review`.
- **`/companion:resume`** — **re-surfaces this repo's unfinished tasks** from an earlier session
  (turning autopilot off first, preserving each task's ❓/⏳/📋 class). Session pickup only; it hands
  off to `/companion:review` for anything waiting on your input.
- **`/companion:review`** — walks the backlog that needs *you* — parked ❓ decisions + blocked ⏳
  owner-actions — one at a time, recommendation-first, recording each pick before new work.
  **Runs automatically when you turn autopilot off** — so decisions deferred while it ran get your
  input before it moves on. A clean no-op when nothing's parked.
- **`/companion:ship-it`** — verify → state the case → commit → push → **merge to main → prune the
  merged branches** (local + remote; shared repos are confirmed first).

## Status line legend

Three plugin sections then generic — `⠋` beacon `-` **active features** `-` **the queue** `-` model · git:
`⠋` health beacon (spins while working) · `v<x.y.z>` the installed plugin version · `🛡️✗` secret gate
**off** (shown only when disabled — no icon when it's on) · `✈️` autopilot on (`✈️⚡` decisive) · `📦` ship-mode armed · `📋` open · `❓` parked ·
`⏳` blocked tasks · `⇡`/`⇣` input/output tokens · project · `⎇` branch · `*N` uncommitted · `↑`/`↓`
commits ahead/behind upstream. *(`⇡⇣` are tokens; `↑↓` are git — two arrow pairs, different meanings.)*

## Documentation

The full design lives under [`docs/`](docs/) — the contract a rebuild must preserve, plus the map
and ledger. `/companion:ship-it` keeps this index current (R57).

- **[docs/flows/](docs/flows/)** — the user-experience contract: one readable page per user flow (happy path + tests + quality bar + change-log), with shared [conventions](docs/flows/_patterns.md) and a global [quality bar](docs/flows/_quality-bar.md).
- **[docs/INVARIANTS.md](docs/INVARIANTS.md)** — the safety/correctness net: the must-holds, each tied to an executable check.
- **[docs/REQUIREMENTS.md](docs/REQUIREMENTS.md)** — the requirements ledger (🔒 locked / 🔓 open / ⚰️ retired), the source of truth for durable decisions.
- **[docs/MAP.md](docs/MAP.md)** — the code map: every file and what it does.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — where it's heading.
- **[docs/GLOSSARY.md](docs/GLOSSARY.md)** — the coined vocabulary.

## Requirements

- **`jq`** and **Bash** (macOS's built-in 3.2 works). Without `jq`, the hooks degrade to a
  silent no-op rather than breaking your session.
- **`git`** — for cross-session resume and repo-aware behavior. Non-git folders are fine.

## Install

```
/plugin marketplace add andrewstanbury/claude-task-queue
/plugin install companion@andrewstanbury
```

Or run `/plugin` and pick it from the **Discover** tab.

> **One thing to turn on:** the enforced core works the moment it's installed, but the *status
> line* is the one opt-in — run **`/companion:setup`** once to wire it (nothing prompts you
> otherwise).

## What installing does

The enforced core works as soon as it's enabled — the only opt-in is the status line (`/companion:setup`).

- **Each session start:** the working agreement (STEERING.md) is put in context once, and any
  unfinished tasks from an earlier session in this repo are surfaced.
- **Before a write:** a file that looks like it contains a hardcoded credential is blocked
  (override with `CLAUDE_COMPANION_SECSCAN=0`).
- **Everything else** — the queue discipline, the recommendation posture, clean-as-you-go — is
  Claude following the steering document, not a hook forcing anything.

The **autonomous** behavior (keep working the queue without stopping, parking decisions for you)
only runs when you turn it on — `/companion:autopilot on` (or just "keep going"). It means *keep
going*, not *you're gone* — you can stay and keep queuing tasks. Nothing hazardous arms on install.

## Turning it off

- **Remove it:** `/plugin uninstall companion@andrewstanbury`.
- **Silence the secret gate but keep the plugin:** `CLAUDE_COMPANION_SECSCAN=0`.
