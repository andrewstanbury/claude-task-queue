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
- **Rules stay generic (wide audience)** — NO hardcoded language/framework/ecosystem
  allowlists. Such a list rots and silently biases the suite to one audience. Instead:
  delegate *recognition* to the model (it already knows every framework); hardcode only
  *invocation* a hook genuinely can't avoid (e.g. the actual formatter command), and
  even then prefer the project's OWN configured tool; detect *structure* generically
  (manifest present, source/test layout, file types). New detection must work for any
  ecosystem, not one.

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
- **2 · Verify + stay aligned** — confirm intent in plain language; verify the change
  observably (tests are OPT-IN — a characterization test when it earns the safety net,
  else types/build/run); existing suite green before done; weigh against recorded decisions. Verify observably; keep choices boring &
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
  the Stop hook AUTO-CONTINUES the queue while any non-deferred task is still open (so the
  session can't idle waiting for an absent owner), `AskUserQuestion` is **hard-blocked**
  by a PreToolUse guard, and the approval checkpoint is skipped. **A prompt is presence,
  though** — autopilot ≠ absent: a fresh prompt stamps an owner-present marker (per
  session, `CLAUDE_TQ_PRESENT_WINDOW`, cleared when the Stop hook enters autonomous
  drain), and while it's fresh the guard lets asks through and the capture loop stays
  interactive for that one owner-driven turn, so typing to an autopilot session is never
  trapped in "can't ask you, keep parking". The autonomous drain that follows still
  parks. Set the window to `0` for lights-out autopilot (even your own prompts stay
  autonomous). Self-verify (you have a
  shell), do all reversible work, and **DEFER what the owner will want**, tagged by kind
  (the two ways to defer): a **`❓ [parked]` DECISION** they must make — an important
  direction or design/structural choice, a new dependency or seam, a data-model/interface
  change, a genuinely ambiguous high-blast-radius fork, or approving anything
  irreversible/externally-binding — or a **`⏳ [blocked]` OWNER-ACTION** where the work
  waits on a manual step only they can take (a device, an external/paid service, an
  owner-only test, a check you physically cannot run). Only `❓` decisions hold the
  return-review gate; `⏳` items are surfaced (digest + hud `⏳N`) and the queue drains
  *around* them, resurfacing when the blocker clears — so the owner returns to a reviewable
  pile. **A human PLAYTEST is the one exception — never parked:** finish the work, mark it
  done with a "playtest pending" note, and keep draining; never stall the queue for a
  game's feel/visuals you can't run yourself. **Decide the routine, low-stakes, cheap-to-undo calls yourself** (recommended
  option, recorded) and keep moving; the test is what a wrong call would COST to undo,
  not mere uncertainty. And **never stall on the absent owner**: if a decision blocks all
  progress and genuinely can't be parked, take your recommended (safest, most reversible)
  default, record it, and leave a `❓` note to override — defaulting beats idling. The
  auto-continue is bounded by a per-prompt counter
  (`CLAUDE_TQ_AWAY_MAX_CONTINUE`, default 15) so a stuck model can't spin. `off` prints a
  digest of what completed, the `❓` decisions, and the `⏳` owner-blocked items, and ARMS
  a return-review gate: edits are blocked (tq-review-guard PreToolUse) until you've reviewed
  each parked `❓` — as a blocking AskUserQuestion, recommended option first — and cleared
  the `❓` pile, so you see autopilot's deferred decisions before any more code lands
  (`⏳` items are relayed, not gated) (`CLAUDE_TQ_REVIEW_GATE=0`
  disables; re-enabling autopilot drops the gate). A staleness nudge fires if it's left on.
- **Per-feature commands** — each mode is a typeable slash command (discoverable via
  Claude Code's `/` menu): `/task-queue:autopilot`,
  `/task-queue:agents` (each toggles + announces the new state), `/task-queue:resume`
  (pick up where an earlier session left off — reinstate its open tasks),
  `/task-queue:ship-it` (verify → PR → squash-merge completed work to main)
  and `/task-queue:status` (what's on + open work). They replaced
  the single `/tq` hub. You never *need* them — plain language drives every mode ("keep
  going while I'm gone" → autopilot on) — they're the power-user surface. Agents also
  honors a global default env (`CLAUDE_TQ_AGENT_MODE=on`) so the owner can enable it
  across every repo from settings.json without a per-repo toggle; an explicit per-repo
  `off` still wins (a tombstone). The shipped default stays **off** (opt-in).

Project docs: **[AGENTS.md](./AGENTS.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[docs/MAP.md](./docs/MAP.md)**.
