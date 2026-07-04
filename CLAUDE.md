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
  Per-hook **token budgets** are CI-enforced (`tests/token-budget.bats`) — growing
  one is a deliberate ratchet, bumped in the same change.

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
  on adding** a dep/abstraction/layer — no seam until something *actually varies*
  across it (1 adapter = hypothetical, 2 = real); deletion test: if removing a module
  only relocates its complexity, it was a pass-through.
- **2 · Verify + stay aligned** — confirm intent in plain language; characterize
  before you change (no tests → pin current behaviour first); suite green before
  done; weigh against recorded decisions. Verify observably; keep choices boring &
  reversible; honor the owner's *outcome* not their implementation; autonomy on the
  reversible, plain-language consent on the consequential. **Challenge ruthlessly** —
  including the prompt in front of you; when the work is architecturally significant
  or rests on an assumption, PRESENT a recommended approach + 2-3 alternatives (like
  the design-preview) and let the owner pick; a better option that retires a prior
  requirement is proposed as a *visible* trade-off (name what it retires), never a
  silent override.
- **3 · Subtract as you add** — net surface flat or smaller; reuse before create;
  ratchet, never sweep. **4 · Deliberate prune** fires automatically when debt
  crosses a threshold (over-budget files), routed through the task-queue loop.
- **Native task list = the live queue** — every prompt is interpreted, decomposed,
  and queued, then worked in auto; the AskUserQuestion sign-off (and the critique
  posture) re-gates on real signal — the consequential/design path or the model's own
  blast-radius/ambiguity judgement — not on every prompt (split-from-interrupt);
  **document proportionally** (token efficiency is the payoff, not a separate chase).
  An `in_progress` task carries a one-line progress breadcrumb in its description
  (what's done / what's next) so a crash resumes it mid-task, not from the top.
- **Solo mode** (`/tq solo on`; `off` on return — merges the old *away* + *pause*) —
  when the owner steps away, run fully autonomous. This is **enforced, not advised**:
  the Stop hook AUTO-CONTINUES the queue while any non-`❓` task is still open (so the
  session can't idle waiting for an absent owner), `AskUserQuestion` is **hard-blocked**
  by a PreToolUse guard, and the approval checkpoint is skipped. Self-verify (you have a
  shell), do all reversible work, and PARK anything needing the owner (design/ambiguous
  fork, owner-only test, or any irreversible/binding action) as a `❓ [parked]` task —
  the only way to defer to them. The auto-continue is bounded by a per-prompt counter
  (`CLAUDE_TQ_AWAY_MAX_CONTINUE`, default 40) so a stuck model can't spin. `off` prints a
  digest of what completed + what's parked; a staleness nudge fires if it's left on.
- **One control command `/tq`** — all modes are set through a single explorable command
  (`/tq` bare = menu + state; `/tq solo|checkpoint|agent on|off`, `/tq undo`, `/tq
  status`). It replaced the per-mode slash commands. You never *need* it — plain language
  drives every mode ("keep going while I'm gone" → solo on) — it's the power-user surface.
- **Crash-checkpoint** (`bin/tq-checkpoint.sh on`) — opt-in, per-repo. Auto-snapshots
  the working tree (tracked + untracked) to a hidden ref (`refs/tq/checkpoint`) on
  PostToolUse, off your branch so history stays clean and nothing is pushed; restore
  after a crash with `git restore --source=refs/tq/checkpoint --worktree -- .`. This
  is the **one deliberate exception** to "hooks are read-only" — the only hook that
  writes to git — so it stays opt-in and best-effort (never breaks the triggering edit).

Project docs: **[AGENTS.md](./AGENTS.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[docs/MAP.md](./docs/MAP.md)**.
