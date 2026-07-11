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
| **Clean-as-you-touch** | After you edit a file, it's auto-formatted (your project's own formatter), its blast radius (who depends on it) is surfaced, and it's flagged if it's grown too large. `/companion:audit` does the same across the whole project on demand. |
| **Resume** | Re-surfaces this repo's unfinished tasks when you start a new session. |
| **`tq`** | The task queue — self-owned, so it works everywhere (including the newest models where Claude's built-in task tracking is switched off) and doesn't depend on Claude Code internals. It reprints the queue on every change, so the CLI always shows what's in progress and next. |
| **Status line** | One glance line: secret gate · model · ⇡ input ⇣ output tokens · open-task count · project · branch. Wire it once with `/companion:setup`. |

Bash + `jq`, zero build, one install.

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

## What installing does

The companion works through hooks, so it takes effect as soon as it's enabled — no config step.

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
