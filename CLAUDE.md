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
- **Autopilot mode** (`/task-queue:autopilot` toggles it — merges the old *solo/away* + *pause*) —
  when the owner steps away, run fully autonomous. This is **enforced, not advised**:
  the Stop hook AUTO-CONTINUES the queue while any non-`❓` task is still open (so the
  session can't idle waiting for an absent owner), `AskUserQuestion` is **hard-blocked**
  by a PreToolUse guard, and the approval checkpoint is skipped. Self-verify (you have a
  shell), do all reversible work, and **PARK the decisions the owner will want to make**
  (as a `❓ [parked]` task — the only way to defer) — an important direction or
  design/structural choice, a new dependency or seam, a data-model/interface change, a
  genuinely ambiguous high-blast-radius fork, plus any irreversible/externally-binding
  action or a check you physically cannot run — so the owner returns to a reviewable
  pile. **Decide the routine, low-stakes, cheap-to-undo calls yourself** (recommended
  option, recorded) and keep moving; the test is what a wrong call would COST to undo,
  not mere uncertainty. The auto-continue is bounded by a per-prompt counter
  (`CLAUDE_TQ_AWAY_MAX_CONTINUE`, default 40) so a stuck model can't spin. `off` prints a
  digest of what completed + what's parked; a staleness nudge fires if it's left on.
- **Per-feature commands** — each mode is a typeable slash command (discoverable via
  Claude Code's `/` menu): `/task-queue:autopilot`, `/task-queue:checkpoint`,
  `/task-queue:agents` (each toggles + announces the new state), `/task-queue:resume`
  (pick up where an earlier session left off — restore crashed edits + reinstate its
  open tasks), `/task-queue:ship` (verify → PR → squash-merge completed work to main)
  and `/task-queue:status` (what's on + open work). They replaced
  the single `/tq` hub. You never *need* them — plain language drives every mode ("keep
  going while I'm gone" → autopilot on) — they're the power-user surface. Checkpoint and
  agents also honor a global default env (`CLAUDE_TQ_CHECKPOINT_MODE` /
  `CLAUDE_TQ_AGENT_MODE=on`) so the owner can enable them across every repo from
  settings.json without a per-repo toggle; an explicit per-repo `off` still wins (a
  tombstone). The shipped default stays **off**, so the opt-in invariant below holds.
- **Crash-checkpoint** (`/task-queue:checkpoint`) — opt-in, per-repo. Auto-snapshots
  the working tree (tracked + untracked) to a hidden ref (`refs/tq/checkpoint`) on
  PostToolUse, off your branch so history stays clean and nothing is pushed; restore
  after a crash with `git restore --source=refs/tq/checkpoint --worktree -- .`. This
  is the **one deliberate exception** to "hooks are read-only" — the only hook that
  writes to git — so it stays opt-in and best-effort (never breaks the triggering edit).

Project docs: **[AGENTS.md](./AGENTS.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[docs/MAP.md](./docs/MAP.md)**.
