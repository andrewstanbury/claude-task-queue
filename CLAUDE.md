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

The priority order (full rationale in [docs/ROADMAP.md](./docs/ROADMAP.md)):

- **0 · Self-describing first** — keep the project's map / quality-attributes /
  decisions current and its growth visible (size guard); gate substantive work on
  that manual existing. You can't contain ripple in a project you can't load.
- **1 · Contain blast radius** — before a change, understand how far it ripples and
  contain it: cover the dependents of a touched file, one owner per concern. *Also
  watch the trend* — total coupling shouldn't climb as features land (compounding
  debt is blast-radius-at-scale). The safety net when tests/specs are absent, and
  it **bounds where you clean up**.
- **2 · Verify + stay aligned** — confirm intent in the owner's plain language;
  **characterize before you change** (no tests → pin current behaviour first, blast
  radius says what to pin); suite green before you're done; weigh the work against
  recorded decisions so it's the *right* change. The net the non-technical owner
  can't make.
- **3 · Subtract as you add** — net surface **flat or smaller**: reuse before
  create, delete what's now redundant; **ratchet, never sweep**. **4 · A deliberate
  prune** (`/tidy:audit` + `/tidy:distill`) catches the cross-module debt that
  touch-time bounding skips.
- **Native task list = the live queue** — capture multi-step work, work it in
  dependency order, advance as you finish.
- **Document proportionally** — don't over-document; the baseline is the project
  map + what's-next, the rest scales with complexity. Token efficiency is the
  *payoff* of the above, not a separate chase.

Project docs to consult: **[AGENTS.md](./AGENTS.md)** (conventions + quality
attributes), **[docs/ROADMAP.md](./docs/ROADMAP.md)** (direction, status,
decisions), **[docs/MAP.md](./docs/MAP.md)** (file→responsibility map).
