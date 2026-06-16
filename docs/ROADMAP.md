# ROADMAP — the vibe-coding companion system

A living **design record**: the direction, the durable decisions, and what's next.
Per-version history lives in git, not here (the human-facing CHANGELOG was removed
— see the 2026-06-16 redesign). Read [AGENTS.md](../AGENTS.md) for the conventions
and hard invariants that constrain everything below.

The goal: a set of Claude Code plugins that let you **vibe-code an entire project**
while Claude keeps it clean, well-documented, token-efficient, and low-debt —
**proactively, with minimal input**, entirely through the CLI. The owner reads no
code, no docs, and runs no commands; the system is automatic and artifact-free
(only **lean Claude-context** files, never human-facing prose).

## Prioritized criteria (in order)

Tuned for **existing, often legacy, under-tested projects that must stay clean as
they grow.** The forces that contain debt lead; the intent loop and payoff follow.

- **0 · Keep the project self-describing** *(precondition)* — a project map
  (file→responsibility, for blast radius), recorded decisions/ADRs, quality
  attributes, stack notes. Bootstrap if missing; gate substantive work on it. Kept
  as **lean Claude-context** files (charter authors them), not human docs.
- **1 · Contain blast radius** — know what a change ripples into (code +
  architectural) and cover it; one owner per concern; watch total coupling. **YAGNI:
  the burden of proof is on *adding* a dep/abstraction/layer.**
- **2 · Verify + stay aligned** — confirm intent in plain language; characterize
  before you change (no tests → pin current behaviour first); suite green before
  done (the verification floor); weigh work against recorded decisions (clean ≠
  correct); honor the owner's *outcome*, not their proposed implementation.
- **3 · Subtract as you add** — a new requirement leaves net surface flat or
  smaller; reuse before create, delete what a change makes redundant.
- **4 · Periodic deliberate prune** — for the cross-module debt touch-time bounding
  skips; now **automatic** (fires on a debt threshold, see tidy below).

**Payoff — token efficiency:** not *fewest* tokens but *highest-leverage* ones. A
well-mapped, small-filed, clean project is automatically cheap for Claude to load
and reason about. It accrues from 0–4; don't chase it directly.

## Architecture — four self-contained plugins

| Plugin | Responsibility |
|---|---|
| **task-queue** | **Orchestrate** — the interpret→present→approve loop, capture, order, advance, cross-session resume, pause |
| **tidy** | **Change safely & cleanly** — format/lint on touch, blast-radius, verification floor, automatic prune |
| **charter** | **Know the project + own the owner loop** — doc gate, map, decisions anchor, conventions, intent→demo→consent posture |
| **hud** | **Show** — a consolidated read-only status line (the owner's at-a-glance trust signal) |

Each plugin stays independently installable (the install boundary forbids shared
code — see AGENTS.md), Bash + `jq`, zero build, locality over decomposition.

## What each plugin does now

- **task-queue** — SessionStart policy (native task list = live queue) +
  cross-session **resume bridge** (the native list starts empty each session; this
  re-surfaces a repo's unfinished tasks — the system's confirmed native gap) +
  auto-advance + per-repo pause + opt-in agent-mode + roadmap hydration + an
  open-decisions ledger + schema-drift canary. Its centerpiece is the
  **interpret→present→approve loop**: on any substantive prompt (multi-step OR
  consequential) the capture hook has the model interpret the request, decompose it,
  judge each task for risk/alignment and parallel-vs-inline fan-out, **present its
  understanding + candid per-task recommendations (incl. skip) via AskUserQuestion**,
  and TaskCreate only what the user approves — weighed against recorded direction.
  Trivial prompts stay silent and run under auto mode.
- **tidy** — on touch: format + lint (Go/web/Python/shell, fast file-scoped tools) +
  blast-radius + coverage/size/currency nudges. On Stop: the **verification floor**
  (run the project's tests, block until green, bounded). The **deliberate prune**
  fires automatically at SessionStart when over-budget files cross a threshold
  (`CLAUDE_TIDY_PRUNE_THRESHOLD`, default 3) — a weight report (`tidy-distill.sh`) +
  an instruction to prune now, routing cuts through the task-queue loop. No slash
  commands.
- **charter** — at SessionStart, a compact **proportional brief** gating substantive
  work on the project's Claude manual (quality attributes, map, decisions anchor,
  roadmap, stack, established conventions), detect-not-author, quiet once summarised
  in CLAUDE.md. Owns the **owner loop** (confirm intent → demonstrate → recap). On
  demand: `/charter:align`. Action-time consent is native (see below) — charter
  carries only the standing posture, no hook.
- **hud** — a static health beacon + paused + agent + the verification floor's ✓/✗
  tests + context-window fill % + branch & dirty + model. Read-only, zero token cost.
  With no logs or docs to read, this beacon is the owner's primary trust signal.

## Durable design decisions

- **Native-first.** Where Claude Code does it natively, use the native mechanism and
  don't reimplement: the native **task list** (the queue), native **permissions /
  `auto` mode** (safe autonomy + destructive-action gating), native **statusLine**
  (hud), native **AskUserQuestion** (the present-before-queue interaction), native
  **subagents** (agent-mode fan-out). Hooks earn their keep only where they *execute*
  on an event or read state a session can't see.
- **Run in auto.** The user's `~/.claude/settings.json` sets
  `permissions.defaultMode: "auto"` (auto-approve **with background safety checks**)
  plus a hard-block `deny` set (`rm -rf /` and `~`) and an `ask` set (force-push,
  `reset --hard`). This is the safe-autonomy posture the owner asked for.
- **Proportionality over maximalism** — every practice scaled to complexity/risk.
- **Verification + simplicity over methodology labels** — tests as a safety net (the
  floor), SOLID's essence, DDD's ubiquitous language, **YAGNI**, boring & reversible.
- **Non-technical-owner posture** — autonomy on the reversible, plain-language
  consent on the consequential (the line is reversibility + cost + data-safety).
  Verification must be **observable** (demo it working; the owner verifies by seeing,
  not by reading tests or docs).
- **Subtractive force + quiet hooks** — bootstrap-once (policy in CLAUDE.md, marked
  `claude-companion`) then re-anchor in one line; state (carry-over, drift) is never
  suppressed, only policy prose.
- **Clean ≠ correct** — route charter's decisions/roadmap into the loop so new work
  is weighed against recorded direction before it lands.

## Decided against

- **Consolidating the 4 plugins into 1** (2026-05-31; **reaffirmed 2026-06-16**) —
  after the redesign's deletions the duplication is small; consolidation is deferred
  ("delete first, then judge"). Revisit only if it bites.
- **A charter doc-inventory state file** (2026-06-01) — the install boundary forces a
  fallback detector anyway, so it's net-additive. Chose the CI drift-guard test.
- **A hard, plugin-owned destructive-action *gate*** — a plugin can't own a reliable
  block. **Superseded 2026-06-16:** the gating is now **native** (`permissions.deny`/
  `ask` + `auto`-mode safety checks), which *is* harness-enforced. See the reversal
  below.
- **Native plan mode for the present-before-work step** (2026-06-16) — rejected in
  favour of the task-queue's interpret→present→approve loop: plan mode is read-only
  and all-or-nothing per session, whereas the owner wants to run in auto and review
  only the *queue interpretation*. The loop is that, owned by task-queue.
- **One single CLAUDE.md as the only doc** (2026-06-16) — would conflict with
  charter's separate-file detection (it would nag "missing map/roadmap" every
  session). Chose **a few lean Claude-context files** (CLAUDE.md + map + decisions +
  per-plugin CONTRACTs); charter's model is unchanged.

## Status — 2026-06-16 (native-leaning redesign)

Reoriented the system to be **CLI-only, automatic, and artifact-free** for an owner
who reads no code/docs and runs no commands:

- **Removed the human-readable logging subsystem + the three `*-doctor.sh`
  diagnostics** — nobody reads them. Kept the functional state dir and the
  schema-drift canary.
- **Replaced charter's PreToolUse consent regex with native permissions.**
  *Reversal recorded:* the 2026-06-01 "non-blocking consent surfacing" hook is
  removed — it was fragile (it false-fired on `rm -rf` substrings inside unrelated
  commands) and only reminded. Native `auto` mode + `deny`/`ask` is harness-enforced
  and stronger; charter keeps the plain-language consent *posture*.
- **Generalized the task-queue review-gate into the default interpret→present→approve
  loop** for any substantive prompt (the centerpiece the owner values).
- **Made the deliberate prune automatic** (debt-threshold trigger) and deleted the
  `/tidy:distill` + `/tidy:audit` slash commands.
- **Deleted the human-facing docs** (README, CHANGELOG); kept lean Claude-context.

**What's next:** demand-driven only — a new stack to lint, a real owner-not-at-the-
terminal scenario (the one place an MCP integration, e.g. emailing the owner a
plain-language recap, would earn its keep), or a pain point that surfaces. No new
layers planned.
