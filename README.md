# Claude Code companion

One [Claude Code](https://claude.com/claude-code) plugin that makes Claude a disciplined
pair: it turns your requests into a live task queue, decides with **brutally honest,
multiple-choice recommendations** that name what each option would change, keeps code clean
as it changes it, and works on its own when you step away — while a small enforced core stops
committed secrets and remembers unfinished work between sessions.

It's built around one idea: **steering is a document, enforcement is code, and the two should
never be confused.** Almost everything the companion "does" is one steering document Claude
reads once per session. The only things that are code are the things that must actually
*execute or block*.

| Part | What it is |
|---|---|
| **Steering** ([STEERING.md](plugins/companion/STEERING.md)) | The working agreement: how Claude queues work, challenges the ask, recommends against a **requirements ledger** (🔒 locked / 🔓 open), keeps changes clean, and runs autonomously when you're away. Put in context once per session. |
| **Secret gate** | Before any write, blocks a file that would commit a credential — the one thing native permissions can't scan. A leaked key is irreversible. |
| **Clean-as-you-touch** | After you edit a file, it's auto-formatted with your project's own formatter (a behavior-preserving pass). Deeper cleanliness — blast radius, size, debt hotspots — is a whole-project sweep in `/companion:advise`. |
| **Resume** | Re-surfaces this repo's unfinished tasks when you start a new session — or on demand with `/companion:resume`. |
| **Ship** | `/companion:ship-it` — verify your gate, commit, push, and open/merge a PR. |
| **`tq`** | The task queue — self-owned, so it works everywhere (including the newest models where Claude's built-in task tracking is switched off) and doesn't depend on Claude Code internals. It reprints the queue on every change, so the CLI always shows what's in progress and next. |
| **Autopilot** | `/companion:autopilot on` when you step away — Claude keeps working the queue on its own and parks decisions for your return. Enforced (it won't stop or ask while on) and persists across restarts. |
| **Status line** | One glance line, grouped: ⠋ beacon · `│` 🛡 ✈️ 📦 `│` (active features) · `│` 📋 ❓ ⏳ `│` (the queue) · model · ⇡⇣ tokens · project · ⎇ branch · ↑↓ ahead/behind. Wire it once with `/companion:setup` (legend below). |

Bash + `jq`, zero build, one install.

## Commands

- **`/companion:setup`** — wire the status line into your settings (one-time).
- **`/companion:advise [target]`** — an independent, brutally-honest critique of a target
  (default: the whole project), presented as recommendation-first choices, then queued. Doubles
  as a cleanliness sweep (size · debt · blast-radius · perf).
- **`/companion:autopilot on|off`** — work the queue autonomously while you're away.
  Add **`autopilot ship on`** to auto-commit completed work to an `autopilot/*` branch (reversible,
  never main, no push) for you to review + ship on return.
- **`/companion:resume`** — re-surface this repo's unfinished tasks on demand.
- **`/companion:ship-it`** — verify → state the case → commit → push → **merge to main → prune the
  merged branches** (local + remote; shared repos are confirmed first).

## Status line legend

Three plugin sections then generic — `⠋` beacon `│` **active features** `│` **the queue** `│` model · git:
`⠋` health beacon (spins while working) · `🛡` secret gate on (`🛡✗` off) · `✈️` autopilot on ·
`📦` ship-mode armed · `📋` open · `❓` parked · `⏳` blocked tasks · `⇡`/`⇣` input/output tokens ·
project · `⎇` branch · `*N` uncommitted · `↑`/`↓` commits ahead/behind upstream. *(`⇡⇣` are tokens;
`↑↓` are git — two arrow pairs, different meanings.)*

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

The **autonomous** behavior (working the queue while you're away, parking decisions for you)
only runs when you tell Claude to — in plain language ("keep going while I'm gone"). Nothing
hazardous arms on install.

## Turning it off

- **Remove it:** `/plugin uninstall companion@andrewstanbury`.
- **Silence the secret gate but keep the plugin:** `CLAUDE_COMPANION_SECSCAN=0`.
