# ROADMAP — the vibe-coding companion system

A living **design record**: the direction, the durable decisions, and what's next.
Per-version history lives in git, not here (the human-facing CHANGELOG was removed
in the 2026-06-16 redesign — git history has the detail). Read [AGENTS.md](../AGENTS.md) for the conventions
and hard invariants that constrain everything below.

The goal: a set of Claude Code plugins that let you **vibe-code an entire project**
while Claude keeps it clean, well-documented, token-efficient, and low-debt —
**proactively, with minimal input**, entirely through the CLI. The owner reads no
code, no docs, and runs no commands; the system is automatic and artifact-free
(only **lean Claude-context** files, never human-facing prose). *Two sanctioned
human-facing surfaces (owner-requested):* (1) `flow.sh` at the repo root (`./flow.sh`
/ `make flow`) renders an at-a-glance colored workflow diagram in the terminal — in
the hand-drawn visual format, but **derived live** from the repo (hook wiring, the
review-loop steps, versions, permission state) so it can't drift; and (2) a lean
`README.md` for **GitHub discoverability** — a *different audience* than the
artifact-free principle addresses (repo visitors deciding whether to install, not the
owner operating the system). The README is deliberately high-level (what it is, the
flow, the 4 plugins, install) so it ages slowly, and points at `flow.sh` for the live
flow. Keep both; don't prune them.

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
- **2 · Verify + stay aligned** — confirm intent in plain language; verify the
  change observably (types/build/run; tests are opt-in — run them yourself when they
  earn the safety net); weigh work against recorded decisions (clean ≠ correct);
  honor the owner's *outcome*, not their proposed implementation.
- **3 · Subtract as you add** — a new requirement leaves net surface flat or
  smaller; reuse before create, delete what a change makes redundant.
- **4 · Periodic deliberate prune** — for the cross-module debt touch-time bounding
  skips; now **automatic** (fires on a debt threshold, see tidy below).

**Payoff — token efficiency:** not *fewest* tokens but *highest-leverage* ones. A
well-mapped, small-filed, clean project is automatically cheap for Claude to load
and reason about. It accrues from 0–4; don't chase it directly. **Enforced as an
NFR:** `tests/token-budget.bats` runs each hook in its representative path and fails
CI if its injected text exceeds a per-hook **character budget** (~4 chars/token) —
recurring injections (SessionStart steady-state, per-prompt) budgeted tightest,
per-event Stop blocks given more room. Growing a budget is a deliberate ratchet
(bump the number in the same change). So the system's defining quality attribute
can't silently regress.

## Architecture — four self-contained plugins

| Plugin | Responsibility |
|---|---|
| **task-queue** | **Orchestrate** — the interpret→present→approve review loop, capture, order, cross-session resume, autopilot (gates the loop + enforced autonomy), the Stop-time intent→outcome gate (loop close) |
| **tidy** | **Change safely & cleanly** — format/lint on touch, blast-radius, post-work debt surface, automatic prune |
| **charter** | **Know the project + own the owner loop** — doc gate, map, decisions anchor (+ Stop-time alignment floor), conventions, outcome memory, intent→demo→consent posture |
| **hud** | **Show** — a consolidated read-only status line (the owner's at-a-glance trust signal) |

Each plugin stays independently installable (the install boundary forbids shared
code — see AGENTS.md), Bash + `jq`, zero build, locality over decomposition.

## What each plugin does now

- **task-queue** — SessionStart policy (native task list = live queue) +
  cross-session **resume bridge** (the native list starts empty each session; this
  re-surfaces a repo's unfinished tasks — the system's confirmed native gap — with
  an imperative restore instruction + an on-disk pointer to the prior session's task
  files so a crash-resume is high-fidelity without inlining descriptions per startup) +
  per-repo autopilot (merged away+pause, enforced autonomy) + opt-in agent-mode + roadmap hydration + schema-drift canary.
  (Moving down the queue is left to Claude Code's native task nudges.) Its
  centerpiece is the **interpret→decompose→queue review loop**: on **every prompt**
  the capture hook has the model interpret the request, decompose it, and TaskCreate
  the work — but the loop is **split from the interrupt** (2026-06-27): by default it
  runs **in auto** (interpret + queue + proceed), and the AskUserQuestion
  present-and-approve fires only on **real signal**. The full present-and-approve +
  critique is reserved for the deterministic high-stakes signal (consequential /
  design); on the default path the **interrupt decision is delegated to the model**,
  which surfaces a sign-off only when the work is ambiguous, high blast-radius, or it
  would recommend against the ask — judgements a per-prompt regex can't make. The
  full procedure + critique posture the lean path re-anchors to ride the
  **SessionStart policy** (stated once per session), keeping the per-prompt budget
  lean while preserving 100% capture. **Autopilot**
  (opt-in, per repo, `/task-queue:autopilot` → `tq-away.sh`; merges the old away + pause) is the
  owner-away autonomy toggle, and it is ENFORCED: the Stop hook auto-continues the queue
  while non-`❓` work remains, a PreToolUse guard hard-blocks AskUserQuestion, the review
  loop is suppressed, and anything that genuinely needs the owner — a design/ambiguous
  fork, an owner-only test, and especially any irreversible/binding action — is PARKED as
  a `❓` task rather than guessed or executed, so it re-surfaces (open-questions bucket +
  hud count) for review on return. On a **visual/design**
  prompt the loop specializes into a **design preview**: the model presents a
  recommended design + 2-3 alternatives as faithful **wireframe** mockups in the
  AskUserQuestion `preview` (native keyboard-nav + Enter, recommended first), and
  builds only the chosen one — the owner-loop's "demonstrate" moved *ahead* of the
  work (a non-technical owner verifies by seeing, not by reading code). Detected by
  a precision-tuned heuristic (visual intent + UI noun; architecture/API "design"
  and functional edits don't trip it). Fires even on a short single-sentence ask. On Stop, the
  **intent→outcome gate** closes the loop: the substantive prompt's plain-language
  ask is stashed at capture time (the *intent of record*) and replayed at "done"
  against the actual diff — blocking **once** (consumed per ask, so it can't loop)
  so the model verifies the OUTCOME matches the request and recaps in plain language,
  surfacing "built the wrong thing / only part / something extra" to the non-technical
  owner before declaring done. `CLAUDE_TQ_INTENT_GATE=0` disables it; autopilot suppresses
  capture too. **Open-questions tracker:** answer-owed questions the model leaves
  hanging are recorded as native `❓` tasks; the capture hook re-surfaces any
  unanswered one on the **next** prompt (even a trivial/autopilot one — a new prompt is
  exactly when they get buried), and **hud** shows an ambient `❓N` count so they get
  *noticed* without anyone re-raising them. Model-assisted recording (it judges which
  questions are answer-worthy; the hooks make them persistent + visible);
  `CLAUDE_TQ_OPEN_Q=0` disables. hud's count is a drift-guarded mirror of
  `tq_open_questions`.
- **tidy** — **before** a write (PreToolUse): the **secret floor** — scan the content
  a write would land for hardcoded credentials (prefix-anchored shapes + a
  placeholder-filtered generic pattern, pure regex so it works without gitleaks) and
  **block before it reaches disk**; tidy's one deliberate hard-stop, everything else
  fails open (`CLAUDE_TIDY_SECSCAN=0` disables). On touch: format + lint
  (Go/web/Python/shell, fast file-scoped tools) + blast-radius + coverage/size nudges.
  On Stop (the end-of-turn verification floor was REMOVED — tests are run manually):
  the **import-cycle check** (madge, surface cycles touching the
  change); the **regression gate**
  (block when a changed file is BOTH a scar-tissue hotspot — repeatedly fixed, by
  the same rework-ratio detector charter uses, mirrored + drift-guarded — AND still
  untested, so a fix to a proven debt-magnet gets pinned before it can silently
  regress; OFF by default (opt-in) and narrow, quiet once a test lands, enable with
  `CLAUDE_TIDY_REGRESSION_GATE=1`); and — on a dirty tree — the **deliberate
  prune** when over-budget files cross a
  threshold (`CLAUDE_TIDY_PRUNE_THRESHOLD`, default 3): a weight report
  (`tidy-distill.sh`) + an instruction to prune now, as a **non-blocking
  systemMessage throttled once per debt episode** (re-fires only after debt drops
  below the threshold and re-crosses), routing cuts through the task-queue loop.
  Firing post-turn keeps it from derailing the user's intent. SessionStart no longer
  surfaces whole-project debt; the per-touch size nudge covers reactive size. The
  automatic post-turn firing stays the default path; **`/tidy:audit` adds an on-demand
  trigger** (2026-07-07) for the case the auto-prune can't reach — a deliberate
  whole-project audit on a clean tree or below threshold — and, being manually invoked,
  auto-queues every finding as a cleanup task rather than nudging. This **retires the
  earlier "no slash commands" clause** for the prune: an explicit trade-off, matching how
  the task-queue command family already frames commands as an optional power-user surface
  over the automatic behavior (plain language still works; the command is discoverability).
- **charter** — at SessionStart, a compact **proportional brief** gating substantive
  work on the project's Claude manual (quality attributes, map, decisions anchor,
  roadmap, stack, established conventions), detect-not-author, quiet once summarised
  in CLAUDE.md. Also surfaces **outcome memory ("scar tissue")** — files the project
  has *repeatedly had to FIX*, derived from git history by the **rework ratio**
  (fix/revert commits ÷ total commits touching a file ≥ 0.34, min 2 reworks, existing
  files only), not raw churn — so the review loop treats debt magnets as high-risk
  before extending them. State, not policy: surfaced even in quiet mode, silent on a
  clean/new repo. Owns the **owner loop** (confirm intent → demonstrate → recap).
  On Stop, the **alignment floor**: when a finished change plausibly bears on a
  recorded decision (a dependency manifest / config / migration changed, or a
  backtick-fenced decision token appears in the diff — a cheap deterministic
  pre-filter that stays silent on routine edits), it blocks **once** and puts the
  recorded decisions in front of the model — honor them, or, on a reversal, surface
  it to the owner in plain language and confirm before it lands. Bounded like tidy's
  test floor (per-tree throttle + `CLAUDE_CHARTER_ALIGN_MAX` cap, never loops);
  `CLAUDE_CHARTER_ALIGN_GATE=0` disables it. This is the **outcome-time** complement
  to the review loop's **intent-time** alignment — alignment is now checked at both
  ends. On demand: `/charter:align`. Action-time consent is native (see below) —
  charter carries only the standing posture, no hook. A second SessionStart hook is
  the **MCP reachability probe**: it reads the MCP servers *declared* for the repo
  (merged from `~/.claude.json`, `.mcp.json`, `.claude/settings*.json`) and checks
  each actually responds — a bounded, parallel `initialize` handshake to stdio
  servers and a POST to http/sse endpoints — so the silent failure mode (a
  mis-installed/unreachable server whose tools just never appear) is surfaced to a
  non-technical owner in plain language. An HTTP auth challenge counts as reachable;
  only a fresh start probes (not compact/resume); self-disables when no servers are
  declared; never blocks; `CLAUDE_CHARTER_MCP_PROBE=0` disables it.
- **hud** — a static health beacon + autopilot + agent + **🛡 safety shield / 🛡✗N
  disabled-floor marker** + context-window fill % + token throughput
  (⇡input ⇣output, current-context) + branch & dirty + model. Read-only, zero token
  cost. The owner's primary trust signal, so it stays **honest + legible**: `🛡✗N`
  surfaces when any anti-rework floor is off via a `CLAUDE_*=0` env var (always shown,
  never shed on narrow — a disabled guard otherwise leaves the green dot quietly lying),
  and `/hud:legend` decodes every symbol in plain language on demand (still zero ongoing
  cost) for the non-technical owner the symbol-only line was illegible to. The flag names
  are drift-guarded against the siblings that own them.

## Durable decisions → the ledger

The durable design decisions and the "decided against" list now live in
[docs/REQUIREMENTS.md](./REQUIREMENTS.md) as status-tagged entries (per **R2** — challenge
or reverse one *there*, not here):

- **R10–R17** — native-first (+ the `tq` fallback for gated task tools), run-in-auto,
  proportionality, verification-over-methodology-labels, non-technical-owner posture,
  subtractive-force + quiet hooks, clean≠correct, and the critique posture.
- **R18–R21** — the decided-against set: a charter doc-inventory state file, a hard
  plugin-owned destructive-action gate (gating is native; tidy's secret floor is the one
  exception), native plan mode, and a single-CLAUDE.md-as-only-doc.
- **R22 (⚰️ retired)** — "consolidating the 4 plugins into 1" was superseded 2026-07-11 by
  **R4** (shared source + build step, keeping four installables).

## Anti-rework floors (the prevention taxonomy)

A taxonomy of rework causes, each closed by a **bounded, disable-able, detect-not-decide
Stop-time floor** (the hook supplies facts; the model judges). The durable decisions behind
this table are **R23** in the ledger (outcome-memory-is-charter's, alignment-at-both-ends,
requirement-conflict-is-a-surfaced-trade-off, cheap-pre-filters, loop-proof); blow-by-blow
in git, detail in each CONTRACT.

| Open loop (cause of future rework) | Closed by | Disable |
|---|---|---|
| Regression of a repeatedly-fixed file | tidy regression gate (← charter scar tissue) | opt-in; `CLAUDE_TIDY_REGRESSION_GATE=1` to enable |
| Silent reversal of a recorded decision | charter alignment floor | `CLAUDE_CHARTER_ALIGN_GATE=0` |
| Built ≠ what the owner asked | task-queue intent→outcome gate | `CLAUDE_TQ_INTENT_GATE=0` |

## What's next

Demand-driven only — a new stack to lint, a real owner-not-at-the-terminal scenario,
or a pain point that surfaces. No new layers planned.

## Build history

Cut 2026-07-07 — this project optimizes for Claude + cross-machine continuity, and nobody reads a prose changelog; the full dated build-log lives in `git log` (commit messages carry the same detail). This file keeps only the forward backlog above.
