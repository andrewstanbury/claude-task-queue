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

This repo runs its own companion plugins; their standing guidance is summarised
here (one line each — full rationale in [docs/ROADMAP.md](./docs/ROADMAP.md)) so
the SessionStart hooks re-anchor briefly instead of repeating in full. The
`claude-companion` marker above is what tells them to stay quiet.

- **0 · Self-describing first** — keep the map / quality-attributes / decisions
  current and growth visible; gate substantive work on them existing. Keep a thin
  plain-language owner layer (what it is / how to run it).
- **1 · Contain blast radius** — cover the dependents of what you touch; one owner
  per concern; watch that total coupling doesn't climb. **YAGNI: burden of proof is
  on adding** a dep/abstraction/layer.
- **2 · Verify + stay aligned** — confirm intent in plain language; characterize
  before you change (no tests → pin current behaviour first); suite green before
  done; weigh against recorded decisions. Verify observably; keep choices boring &
  reversible; honor the owner's *outcome* not their implementation; autonomy on the
  reversible, plain-language consent on the consequential.
- **3 · Subtract as you add** — net surface flat or smaller; reuse before create;
  ratchet, never sweep. **4 · Deliberate prune** (`/tidy:audit` + `/tidy:distill`)
  for cross-module debt.
- **Native task list = the live queue**; **document proportionally** (token
  efficiency is the payoff, not a separate chase).

Project docs: **[AGENTS.md](./AGENTS.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[docs/MAP.md](./docs/MAP.md)**.
