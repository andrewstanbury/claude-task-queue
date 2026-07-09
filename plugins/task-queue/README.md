# task-queue

Turns Claude Code's native task list into a live work queue: every prompt you send is
interpreted, broken into tasks, and worked in order — so nothing you asked for quietly
falls off the end of a long session.

## What it does

- **Reads each prompt into queued tasks** and works them in dependency order — the
  `UserPromptSubmit` hook (`tq-capture.sh`) re-anchors Claude to treat the task list as
  the queue on every prompt.
- **Resurfaces open work at session start** so a crash-and-relaunch picks up where you
  left off — the `SessionStart` hook (`tq-resume.sh`) reloads this repo's carried-over
  tasks.
- **Checks that the result matches the ask** when a turn ends — the `Stop` hook
  (`tq-verify.sh`) replays your plain-language request against the actual change before
  Claude calls the work done.
- **Autopilot (opt-in per repo):** when you step away, the queue keeps draining on its
  own. Decisions only you can make get parked as **`❓`** markers (a choice you must make
  — a direction, a new dependency, anything hard to undo); work waiting on a manual step
  only you can take gets **`⏳`** (blocked on you — a device, a paid service, a test you
  must run). The queue works *around* `⏳` items and holds the `❓` ones for your review.
- **Return-review gate:** turning autopilot off arms a guard (`tq-review-guard.sh`) that
  blocks further edits until you've walked the parked `❓` decisions — so you see what was
  deferred before more code lands.
- **Agent fan-out (opt-in):** independent tasks can be split across parallel helper
  agents to go faster.

## Commands

- `/task-queue:autopilot [on|off]` — keep working on my own while you're away.
- `/task-queue:agents [on|off]` — split big jobs across parallel helpers.
- `/task-queue:resume` — reload this repo's open tasks after quitting.
- `/task-queue:review` — walk the parked `❓` decisions and `⏳` blocked items, then resume.
- `/task-queue:ship-it` — verify, then commit, push, PR, and squash-merge to main.
- `/task-queue:status` — show what's on (autopilot / agents) and what work is still open.

## What it does to your repo

It **writes nothing to your project files.** It drives Claude Code's own task list and
keeps a little per-repo state (mode toggles, parked markers) under the plugin's data
directory. It reads — never rewrites — your task store. `/task-queue:ship-it` is the one
command that touches git (commit / push / PR / squash-merge), and only when you run it.

## Turning it off / tuning

- **Remove it:** `/plugin uninstall task-queue@andrewstanbury`.
- **Keep it, silence one behavior** (full list in [../../docs/CONFIG.md](../../docs/CONFIG.md)):
  - `CLAUDE_TQ_CAPTURE_DISABLED=1` — stop the per-prompt queue nudge.
  - `CLAUDE_TQ_AWAY_MAX_CONTINUE=15` — cap how many times autopilot auto-continues per prompt (default 15).
  - `CLAUDE_TQ_REVIEW_GATE=0` — don't block edits on the return-review of parked `❓` decisions.
  - `CLAUDE_TQ_DESIGN_GATE=0` — don't require a wireframe preview before visual changes.

## Requirements

`jq` and Bash (macOS's built-in 3.2 is fine). `git` for resume/ship-it awareness;
`gh` (authenticated) only for `/task-queue:ship-it` — without it, ship-it still commits
and pushes, then prints a PR link to open by hand. Missing `jq` degrades to a silent no-op.
