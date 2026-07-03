---
description: Away-mode — run fully autonomous and PARK anything needing you (on|off)
argument-hint: "on|off"
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tq-away.sh" $ARGUMENTS

Away-mode is now set as shown above (no argument = status).

- **on** — the owner is away: from now on, do NOT block on them (no AskUserQuestion,
  no "please run this test" — self-verify), and PARK anything that genuinely needs them
  (a design/ambiguous fork, an owner-only test, or any irreversible/binding action) as a
  `❓ [parked] …` task instead of guessing or executing it. Do all reversible work.
- **off** — the owner is back: the review loop resumes, and the command prints a digest
  of what completed and what's parked. Relay that digest and re-raise the parked `❓`
  items so nothing waits unseen.
