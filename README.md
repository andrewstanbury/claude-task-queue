# Claude Code companion plugins

Four self-contained [Claude Code](https://claude.com/claude-code) plugins that keep a
project clean, low-debt, and token-efficient — automatically, through hooks. They're built
to run hands-off: the native task list is the one place you steer.

| Plugin | Ver | Role |
|---|---|---|
| **task-queue** | 0.42.0 | Orchestrate — native task list as a live queue: per-prompt review loop, enforced design-preview + parked-review gates, two deferral markers (❓ decisions / ⏳ owner-blocked), lean autopilot drain (park-rule sent once, not per continuation), queue-aware agent fan-out, one-command ship |
| **tidy** | 0.42.0 | Change safely — format/lint on touch, blast-radius, verification floor (runs your existing tests), opt-in regression gate, quality floor, auto-prune + on-demand `/tidy:audit` (tests are opt-in, never forced) |
| **charter** | 0.23.0 | Know the project — doc & decisions gate, alignment floor, scar-tissue memory, language-agnostic convention detection |
| **hud** | 0.19.0 | Show — one read-only status line (health, feature state, tests, ❓ decisions + ⏳ owner-blocked, tokens, branch) |

Each plugin is independently installable · Bash + `jq` · zero build.

## Requirements

- **`jq`** and **Bash** (macOS's built-in 3.2 works — no Homebrew bash needed). Without `jq`, every plugin degrades to a silent no-op rather than breaking your session.
- **`git`** — for the repo-aware features (blast radius, scar tissue, ship-it). Non-git folders are handled gracefully.
- **`gh`** (GitHub CLI, authenticated) — only for `/task-queue:ship-it`. Without it, ship-it still commits and pushes your branch, then prints a PR link to open manually.

## Install

```
/plugin marketplace add andrewstanbury/claude-task-queue
/plugin install task-queue@andrewstanbury tidy@andrewstanbury charter@andrewstanbury hud@andrewstanbury
```

Or run `/plugin` and pick them from the **Discover** tab.

## What installing does

These plugins work through hooks, so they take effect as soon as they're enabled — there's
no separate config step. Concretely:

- **Each session start:** a short brief primes Claude (treat the task list as a queue, know
  the project). Once per session, then it goes quiet.
- **task-queue:** interprets each prompt into queued tasks and works them in order.
- **tidy:** formats the file you just edited — **formatting only, never behavior changes** —
  and, when a turn ends, runs your project's *existing* tests / quality gates before letting
  it finish. It writes to your working tree (the formatter's output) but applies no other edits.
- **charter:** flags missing Claude-facing docs and files the repo has historically had to
  fix a lot. It never writes project files itself.
- **hud:** after `/hud:setup`, shows a one-line status. Zero model-token cost.

The **autonomous** behaviors — blocking questions, auto-continuing the queue while you're
away — only turn on when you explicitly enable **autopilot** for a repo. Nothing hazardous
arms on install.

## Turning it off

- **Remove a plugin:** `/plugin uninstall <name>@andrewstanbury` (or manage it from `/plugin`).
- **Keep it installed but silence one behavior:** every hook has an environment off-switch.
  A few common ones — full list in **[docs/CONFIG.md](docs/CONFIG.md)**:
  - `CLAUDE_TQ_CAPTURE_DISABLED=1` — stop task-queue's per-prompt queue nudge.
  - `CLAUDE_TIDY_CHECKS=0` — stop tidy's end-of-turn test/quality run.
  - `CLAUDE_TIDY_SIZE_CHECK=0` — stop the file-size prune nudge.
  - `CLAUDE_CHARTER_ALIGN_GATE=0` — stop charter's decisions-alignment check.

## Per-plugin details

[task-queue](plugins/task-queue/README.md) ·
[tidy](plugins/tidy/README.md) ·
[charter](plugins/charter/README.md) ·
[hud](plugins/hud/README.md)

Full configuration reference: **[docs/CONFIG.md](docs/CONFIG.md)** ·
Changelog: **[CHANGELOG.md](CHANGELOG.md)**
