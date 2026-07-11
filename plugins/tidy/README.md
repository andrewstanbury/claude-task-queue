# tidy

Keeps the code Claude writes clean and safe as it goes: it formats each file the moment
it's edited, blocks secrets before they land, and won't let a turn finish on a red test
suite — so you don't inherit a mess or a broken tree.

## What it does

- **Formats every file right after it's edited** — the `PostToolUse` hook
  (`tidy-touch.sh`) detects the language, applies **behavior-preserving formatting only**,
  and surfaces linter findings for Claude to address. It never changes what your code does.
- **Blocks secrets before they're written** — the `PreToolUse` hook (`tidy-presecret.sh`)
  scans content about to be written and denies the write if it looks like a hardcoded
  credential.
- **Surfaces post-work debt at end-of-turn** — the `Stop` hook (`tidy-verify.sh`) does
  NOT run your tests (you run those manually). On a dirty tree it makes one non-blocking
  pass: import cycles touching your change, and a prune nudge when files cross the size
  budget. It never blocks your work.
- **Surfaces blast radius** — when you touch a file, it points out the dependents that
  ride on your change (`lib/blast.sh`).
- **Sets a clean-as-you-go standard once per session** — the `SessionStart` hook
  (`tidy-standard.sh`) reminds Claude to leave touched files cleaner than it found them,
  and nudges when a file grows over budget.
- **Opt-in gates:** regression and coverage checks are available but off by default, so
  nothing forces tests you didn't ask for.

## Commands

- `/tidy:audit` — read-only whole-project weight report (file size, blast radius, cruft),
  auto-queuing the cleanup as tasks.

## What it does to your repo

It **writes the formatter's output to files you edit** — formatting only, no behavior
changes and no other edits. It does NOT run your tests — everything else (post-work
debt surface, blast radius, size budget, audit) is read-only reporting.

## Turning it off / tuning

- **Remove it:** `/plugin uninstall tidy@andrewstanbury`.
- **Keep it, silence one behavior** (full list in [../../docs/CONFIG.md](../../docs/CONFIG.md)):
  - `CLAUDE_TIDY_CHECKS=0` — stop the end-of-turn debt/cycle surface (the whole Stop hook).
  - `CLAUDE_TIDY_SIZE_CHECK=0` — stop the file-size prune nudge.
  - `CLAUDE_TIDY_SECSCAN=0` — stop the pre-write secret scan.

## Requirements

`jq` and Bash (macOS's built-in 3.2 is fine); `git` for blast-radius awareness.
Formatters/linters are your project's own tools — tidy invokes what's already there and
skips what isn't. Missing `jq` degrades to a silent no-op.
