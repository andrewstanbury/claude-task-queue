# hud

One read-only status line that shows, at a glance, what the companion plugins are doing —
project health, which modes are on, test state, parked items, token use, and branch —
without spending a single model token to render it.

## What it does

- **Renders one consolidated status line** — `hud-status.sh` reads the state the sibling
  plugins already maintain (plus the JSON Claude Code pipes in) and prints a single line:
  health, feature/mode state, tests, **`❓`** decisions and **`⏳`** owner-blocked items
  (the two things parked for you), token use, and current branch.
- **Costs zero model tokens** — it's a status-line command, not a hook. No model calls, no
  hooks, no writes: it only reads and prints, so it can't interfere with anything.
- **Flags when safety checks are off** — a `🛡✗N` marker tells you how many guardrails are
  currently disabled.

Its value comes from the sibling plugins: hud is a window onto task-queue, tidy, and
charter, so it's most useful with them installed.

## Commands

- `/hud:setup` — wire the status line into your `~/.claude/settings.json` (a one-time,
  version-resilient step; the status line can't self-activate).
- `/hud:legend` — explain what each symbol in the status line means (and which safety
  checks are off).

## What it does to your repo

**Nothing to your project.** The only file it writes is your `~/.claude/settings.json`,
and only when you run `/hud:setup`, to register the status-line command. After that it
purely reads and prints.

## Turning it off / tuning

- **Remove it:** `/plugin uninstall hud@andrewstanbury`. (You may also want to remove the
  `statusLine` entry `/hud:setup` added to `~/.claude/settings.json`.)
- hud has no behavior worth an env off-switch — if you don't run `/hud:setup`, it does
  nothing at all. Run `/hud:legend` any time to decode the line. Full config reference:
  [../../docs/CONFIG.md](../../docs/CONFIG.md).

## Requirements

`jq` and Bash (macOS's built-in 3.2 is fine). Missing `jq` degrades to a silent no-op.
