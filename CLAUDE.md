# CLAUDE.md

Maintainer guide: **[AGENTS.md](./AGENTS.md)** — read it first.

Hard invariants (do not violate):

- **Each plugin is self-contained** — no cross-plugin shared lib, no build step.
  Claude Code installs each plugin's subdir alone, so it can only use files under
  its own `${CLAUDE_PLUGIN_ROOT}`. The small duplication between plugins is intentional.
- **Hooks are best-effort and must never break the action that triggered them**
  (`set -uo pipefail`, swallow errors, exit 0 when silent).
- **`task-queue` is read-only** over `~/.claude/tasks`; **`tidy` only auto-applies
  behavior-preserving fixes** (formatting), surfacing everything else.
- **Zero per-prompt cost**; keep files cohesive (CI fails scripts over 300 lines).

Verify everything with **`./check.sh`** — CI runs the same script.

## Working standards <!-- claude-companion -->

This repo runs its own companion plugins. Their standing guidance is summarised
here so the SessionStart hooks re-anchor in one line instead of repeating in full
(the `claude-companion` marker above is what tells them to stay quiet):

- **Tests are the floor** — verify changed behaviour (a test where it earns its
  keep, else types/build/running it); the suite must be green before you're done.
- **Clean-as-you-go, subtract as you add** — reuse before create, delete what a
  change makes redundant, simplest design that fits; net complexity trends down.
- **Native task list = the live queue** — capture multi-step work, work it in
  dependency order, advance as you finish.
- **Document proportionally** — don't over-document; the baseline is the project
  map + what's-next, the rest scales with complexity.

Project docs to consult: **[AGENTS.md](./AGENTS.md)** (conventions + quality
attributes), **[docs/ROADMAP.md](./docs/ROADMAP.md)** (direction, status,
decisions), **[docs/MAP.md](./docs/MAP.md)** (file→responsibility map).
