---
description: task-queue control — show modes or toggle them (solo · checkpoint · agent · undo · status)
argument-hint: "[solo|checkpoint|agent on|off] · undo · status"
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq.sh" $ARGUMENTS

The output above is task-queue's **control plane** for this repo — one command for
everything. Bare `/tq` shows which modes are on and how much work is still open; a
subcommand changes one:

- **`solo on|off`** — the autonomous mode (this replaces the old *away* and *pause*
  commands). When **on**: keep working without the owner, do NOT stop to ask
  (`AskUserQuestion` is blocked and the queue auto-continues), skip the approval
  checkpoint, and PARK anything that genuinely needs them — a design/ambiguous fork,
  an owner-only test, or any irreversible/binding action — as a `❓ [parked] …` task
  instead of guessing or executing it. Do all reversible work. **off** — the normal
  review loop resumes and the command prints a digest of what completed and what's
  parked; relay it and re-raise the parked `❓` items.
- **`checkpoint on|off`** — arm/disarm auto-snapshots of your working tree to a
  hidden ref (off your branch; history stays clean).
- **`undo`** — recover the working tree from the last checkpoint snapshot.
- **`agent on|off`** — fan independent, low-blast-radius tasks out to subagents.

You don't need this command in normal use — just say what you want in plain language
("keep going while I'm gone", "I'm back", "make a safety net") and I'll set the right
mode. Confirm the new state in one plain line; if a mode looks stale (e.g. solo still
on when you're clearly back), point it out.
