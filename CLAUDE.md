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
  including the prompt in front of you; when the work is architecturally significant,
  rests on an assumption, or the viable approaches diverge on a meaningful axis,
  PRESENT a recommended approach + 2-3 alternatives (like the design-preview) and let
  the owner pick — this ranked shape is the default for any surfaced fork, but only
  enumerate genuinely viable options; a clear low-stakes winner you just decide and
  record; a better option that retires a prior
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
- **Autopilot mode** (`/task-queue:autopilot` — merges the old *solo/away* + *pause*) —
  when the owner steps away, run fully autonomous. **Enforced, not advised:** the Stop
  hook auto-continues the queue while non-deferred work remains, `AskUserQuestion` is
  hard-blocked, and the approval checkpoint is skipped — *but a fresh prompt is presence*,
  so typing to an autopilot session stays interactive for that one turn (the autonomous
  drain after still parks). Self-verify (you have a shell), do all reversible work, and
  **DEFER what the owner will want, tagged by kind**: a **`❓ [parked]` DECISION** — a
  direction / design / structural choice, a new dependency or seam, a data-model/interface
  change, a genuinely ambiguous high-blast-radius fork, or approving anything
  irreversible/externally-binding — or a **`⏳ [blocked]` OWNER-ACTION**, a manual step only
  they can take (a device, an external/paid service, an owner-only test). Only `❓` holds
  the return-review gate; `⏳` items are surfaced (hud `⏳N`) and the queue drains *around*
  them. **A human PLAYTEST is the one thing never parked** — finish, mark done with a
  "playtest pending" note, keep draining. **Decide the routine, cheap-to-undo calls
  yourself** (recommended option, recorded); the test is what a wrong call would COST to
  undo. And **never stall on the absent owner** — if an unparkable decision blocks all
  progress, take your safest-reversible default, record it, leave a `❓` to override. `off`
  prints a digest and ARMS a return-review gate (edits blocked until the `❓` pile is
  reviewed + cleared). *Full enforcement map + env knobs (`CLAUDE_TQ_PRESENT_WINDOW`,
  `_AWAY_MAX_CONTINUE`, `_REVIEW_GATE`) → [AGENTS.md](./AGENTS.md), [docs/CONFIG.md](./docs/CONFIG.md).*
- **Per-feature commands** (discoverable via the `/` menu; you never *need* them — plain
  language drives every mode, e.g. "keep going while I'm gone" → autopilot on):
  `/task-queue:autopilot`, `/task-queue:agents` (toggle + announce), `/task-queue:resume`,
  `/task-queue:review`, `/task-queue:ship-it`, `/task-queue:status`. Agents also honors a
  global default (`CLAUDE_TQ_AGENT_MODE=on`); a per-repo `off` tombstone still wins. Shipped
  default **off** (opt-in). Details in [AGENTS.md](./AGENTS.md).

Project docs: **[AGENTS.md](./AGENTS.md)**, **[docs/ROADMAP.md](./docs/ROADMAP.md)**,
**[docs/MAP.md](./docs/MAP.md)**.
