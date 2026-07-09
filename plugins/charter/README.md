# charter

Helps Claude actually know your project before it changes it: at session start it flags
missing Claude-facing docs and the files your repo keeps having to fix, and at end-of-turn
it checks the change against the decisions you've already recorded.

## What it does

- **Primes each session with a project brief** — the `SessionStart` hook
  (`charter-standard.sh`) nudges Claude to capture the project's quality attributes
  (performance, security, reliability…) first when they aren't documented, so substantive
  work rests on something written down.
- **Surfaces "scar tissue"** — files the repo's git history shows have been fixed over and
  over (the ones most likely to bite again), so Claude treats them with extra care.
- **Checks alignment at end-of-turn** — the `Stop` hook (`charter-align-gate.sh`) puts your
  recorded decisions in front of Claude when a change plausibly bears on one: honor it, or,
  if the change reverses it, say so in plain language rather than silently overriding it.
- **Probes MCP-server health at startup** — the `SessionStart` hook
  (`charter-mcp-probe.sh`) checks that each configured MCP server is actually reachable and
  tells you in plain language when one is dead (so tools don't just silently go missing).
- **Detects project conventions generically** — structure-based, no hardcoded
  language/framework lists, so it works for any ecosystem.

## Commands

- `/charter:align` — reconcile open and proposed work against your recorded decisions and
  roadmap.

## What it does to your repo

It **writes nothing to your project.** Everything it does is read-only: it reads your docs,
your git history, and your MCP config, then surfaces what it finds as guidance for Claude
and notes for you. Any doc it suggests is written by Claude with your go-ahead, not by the
plugin.

## Turning it off / tuning

- **Remove it:** `/plugin uninstall charter@andrewstanbury`.
- **Keep it, silence one behavior** (full list in [../../docs/CONFIG.md](../../docs/CONFIG.md)):
  - `CLAUDE_CHARTER_ALIGN_GATE=0` — stop the end-of-turn decisions-alignment check.
  - `CLAUDE_CHARTER_MCP_PROBE=0` — stop the startup MCP-server health probe.
  - `CLAUDE_CHARTER_WEB=1|0` — force web-project convention detection on or off.

## Requirements

`jq` and Bash (macOS's built-in 3.2 is fine); `git` for scar-tissue history. Missing `jq`
degrades to a silent no-op.
