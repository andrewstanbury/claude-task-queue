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
flow. Keep both; don't prune them. *(2026-06-17: README re-added — the original
redesign deleted it as an owner-workflow doc; this restores it for discoverability,
which that decision didn't contemplate.)*

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
| **task-queue** | **Orchestrate** — the interpret→present→approve review loop, capture, order, cross-session resume, solo mode (gates the loop + enforced autonomy), the Stop-time intent→outcome gate (loop close) |
| **tidy** | **Change safely & cleanly** — format/lint on touch, blast-radius, verification floor, automatic prune |
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
  per-repo solo mode (merged away+pause, enforced autonomy) + opt-in agent-mode + roadmap hydration + schema-drift canary.
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
  lean while preserving 100% capture. *(2026-06-26: owner override — fire on every
  prompt; the "only multi-step fires" filter and `tq_looks_multistep` were removed,
  reversing the "trivial stays silent" decision below. 2026-06-27: split-from-
  interrupt — keep routing every prompt, but make the per-prompt injection lean (fat
  procedure + critique moved to the SessionStart policy, re-firing inline only on the
  consequential/design signal or the model's judgement), restoring the per-prompt
  efficiency the 2026-06-26 change had spent without a leaky "is this substantive"
  classifier — the model, not a regex, decides whether to interrupt.)* **Solo mode**
  (opt-in, per repo, `/tq solo` → `tq-away.sh`; merges the old away + pause) is the
  owner-away autonomy toggle, and it is ENFORCED: the Stop hook auto-continues the queue
  while non-`❓` work remains, a PreToolUse guard hard-blocks AskUserQuestion, the review
  loop is suppressed, and anything that genuinely needs the owner — a design/ambiguous
  fork, an owner-only test, and especially any irreversible/binding action — is PARKED as
  a `❓` task rather than guessed or executed, so it re-surfaces (open-questions bucket +
  hud count) for review on return. On a **visual/design**
  prompt the loop specializes into a **design preview**: the model presents a
  recommended design + 2-3 alternatives as faithful **ASCII mockups** in the
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
  owner before declaring done. `CLAUDE_TQ_INTENT_GATE=0` disables it; solo mode suppresses
  capture too. **Open-questions tracker:** answer-owed questions the model leaves
  hanging are recorded as native `❓` tasks; the capture hook re-surfaces any
  unanswered one on the **next** prompt (even a trivial/solo-mode one — a new prompt is
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
  On Stop: the **verification floor**
  (run the project's tests, block until green, bounded); the **quality floor**
  (before the tests, run the project's OWN declared typecheck/a11y/dep-rule gates —
  detect-and-run package.json scripts, install/invent nothing, heavy Lighthouse/CWV
  audits stay in CI — block until green, bounded; `CLAUDE_TIDY_QUALITY_FLOOR=0` to
  disable); the **import-cycle check** (madge, post-green, surface cycles touching the
  change); the **coupling-density trend** (nudge when import-edges-per-file — a
  size-normalized proxy, so healthy growth doesn't false-alarm — climbs past a
  threshold vs the last check; per-repo baseline, `CLAUDE_TIDY_COUPLING_TREND=0` to
  disable); the **regression gate**
  (block when a changed file is BOTH a scar-tissue hotspot — repeatedly fixed, by
  the same rework-ratio detector charter uses, mirrored + drift-guarded — AND still
  untested, so a fix to a proven debt-magnet gets pinned before it can silently
  regress; default-on but narrow, quiet once a test lands, `CLAUDE_TIDY_REGRESSION_GATE=0`
  to disable); and — only after a clean verify on a dirty tree — the **deliberate
  prune** when over-budget files cross a
  threshold (`CLAUDE_TIDY_PRUNE_THRESHOLD`, default 3): a weight report
  (`tidy-distill.sh`) + an instruction to prune now, as a **non-blocking
  systemMessage throttled once per debt episode** (re-fires only after debt drops
  below the threshold and re-crosses), routing cuts through the task-queue loop.
  Firing post-turn keeps it from derailing the user's intent. SessionStart no longer
  surfaces whole-project debt; the per-touch size nudge covers reactive size. No
  slash commands.
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
- **hud** — a static health beacon + solo + agent + the verification floor's ✓/✗
  tests + **🛡✗N disabled-floor marker** + context-window fill % + token throughput
  (⇡input ⇣output, current-context) + branch & dirty + model. Read-only, zero token
  cost. The owner's primary trust signal, so it stays **honest + legible**: `🛡✗N`
  surfaces when any anti-rework floor is off via a `CLAUDE_*=0` env var (always shown,
  never shed on narrow — a disabled guard otherwise leaves the green dot quietly lying),
  and `/hud:legend` decodes every symbol in plain language on demand (still zero ongoing
  cost) for the non-technical owner the symbol-only line was illegible to. The flag names
  are drift-guarded against the siblings that own them.

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
  The decision: encode these as **concrete generation-time rules** — no-seam +
  deletion-test (CLAUDE.md working standards #1) and unit-cohesion + complexity-altitude
  (the tidy SessionStart standard) — **not** as methodology labels, since a "SOLID
  checker" isn't mechanically viable. The test-fail block's **diagnose loop**
  composes with the regression gate.
- **Non-technical-owner posture** — autonomy on the reversible, plain-language
  consent on the consequential (the line is reversibility + cost + data-safety).
  Verification must be **observable** (demo it working; the owner verifies by seeing,
  not by reading tests or docs).
- **Subtractive force + quiet hooks** — bootstrap-once (policy in CLAUDE.md, marked
  `claude-companion`) then re-anchor in one line; state (carry-over, drift) is never
  suppressed, only policy prose.
- **Clean ≠ correct** — route charter's decisions/roadmap into the loop so new work
  is weighed against recorded direction before it lands.
- **Critique posture: selective, substantive-gated, bidirectional, self-challengeable**
  (2026-06-19) — the review loop EVALUATES before executing (steelman → challenge →
  recommend-against when warranted), challenging **both** the project's recorded
  constraints *and* the owner's own accumulated requirements/bias when they contradict
  or force a poor/over-engineered design. ~~**Not on every prompt** — only the
  substantive/consequential gate: mandated on-everything critique becomes theater and
  *false pushback trains rubber-stamping*, and per-prompt critique on trivial work
  breaks the zero-cost invariant.~~ *(2026-06-26: superseded — the owner chose to
  route every prompt through the loop, so the critique posture now rides every
  prompt too. The original theater/rubber-stamping risk is mitigated by the loop's
  "Be SELECTIVE — only on real signal" instruction and its scaling, not by gating
  which prompts fire. The "no per-prompt cost" framing is unchanged: classification
  is still local bash/jq; what changed is the loop now injects on every prompt.)*
  *(2026-06-27: refined by split-from-interrupt — the standing critique posture now
  lives in the SessionStart policy (stated once per session), and the heavy inline
  critique re-fires per-prompt only on the deterministic consequential/design signal;
  the default path carries only a lean selective cue and delegates the
  challenge/recommend-against to the model's judgement. This partially restores the
  2026-06-19 "not on every prompt" intent for the INLINE injection — the per-prompt
  token weight of the full critique no longer rides trivial prompts — without
  reversing the 2026-06-26 "route everything" decision: every prompt is still
  interpreted and queued; what re-gates on signal is the interrupt, not the loop.)*
  Claims only what's feasible (contradiction +
  named-anti-pattern detection; **not** general "bias" — no reference frame). Shipped
  in task-queue's existing UserPromptSubmit injection (no new hook/plugin).
  **Deferred** until the gap proves real (a YAGNI call): bidirectional charter
  alignment (challenge a standing decision, not just protect it) and an on-demand
  `/charter:challenge` audit. The mandate stays **challengeable** — "always question my
  requirements" must not become the one requirement never questioned.

## Decided against

- **Consolidating the 4 plugins into 1** (2026-05-31; **reaffirmed 2026-06-16**) —
  after the redesign's deletions the duplication is small; consolidation is deferred
  ("delete first, then judge"). Revisit only if it bites.
- **A charter doc-inventory state file** (2026-06-01) — the install boundary forces a
  fallback detector anyway, so it's net-additive. Chose the CI drift-guard test.
- **A hard, plugin-owned destructive-action *gate*** — a plugin can't own a reliable
  block. **Superseded 2026-06-16:** the gating is now **native** (`permissions.deny`/
  `ask` + `auto`-mode safety checks), which *is* harness-enforced — this also retired
  charter's fragile 2026-06-01 PreToolUse consent regex (it false-fired on `rm -rf`
  substrings in unrelated commands and only reminded; charter keeps the plain-language
  consent *posture*). **Narrow exception (2026-06-21):** tidy's PreToolUse **secret floor** does
  block a write — the one place a plugin gate earns its keep, because native
  permissions scan bash *commands*/code *style* but nothing scans file *content* an
  agent writes for committed credentials, and a leaked key is irreversible. Kept
  high-precision (prefix-anchored) so false blocks stay near-zero. This is the single
  concept imported from a separate governance system (claude-governance's T3
  obligations); its audit log, tier vocabulary, approver chains, and CI floor stay
  out (org-compliance machinery, not this system's single-owner bet).
- **Native plan mode for the present-before-work step** (2026-06-16) — rejected in
  favour of the task-queue's interpret→present→approve loop: plan mode is read-only
  and all-or-nothing per session, whereas the owner wants to run in auto and review
  only the *queue interpretation*. The loop is that, owned by task-queue.
- **One single CLAUDE.md as the only doc** (2026-06-16) — would conflict with
  charter's separate-file detection (it would nag "missing map/roadmap" every
  session). Chose **a few lean Claude-context files** (CLAUDE.md + map + decisions +
  per-plugin CONTRACTs); charter's model is unchanged.

## Anti-rework floors (the prevention taxonomy)

A taxonomy of rework causes, each closed by a **bounded, disable-able,
detect-not-decide Stop-time floor** (the hook supplies facts; the model judges):

| Open loop (cause of future rework) | Closed by | Disable |
|---|---|---|
| Tests red at "done" | tidy verification floor | `CLAUDE_TIDY_CHECKS=0` |
| Regression of a repeatedly-fixed file | tidy regression gate (← charter scar tissue) | `CLAUDE_TIDY_REGRESSION_GATE=0` |
| Silent reversal of a recorded decision | charter alignment floor | `CLAUDE_CHARTER_ALIGN_GATE=0` |
| Built ≠ what the owner asked | task-queue intent→outcome gate | `CLAUDE_TQ_INTENT_GATE=0` |

Durable decisions behind the table (blow-by-blow in git; detail in each CONTRACT):

- **Outcome memory is charter's, prevention is the verifiers'.** charter *detects*
  scar tissue — `charter_hotspots` flags files by the **rework ratio** (fix/revert ÷
  total touching a file ≥ 0.34, ≥ 2 reworks, existing files), the *disease* not raw
  churn, surfaced at SessionStart; tidy's regression gate then *prevents* recurrence
  (a changed file that's both a hotspot and untested must be pinned before "done").
- **Alignment is verified at both ends** — intent-time (the review loop weighs new
  work against recorded direction) and outcome-time (charter's align gate on the diff;
  task-queue's intent gate on the captured ask vs. the diffstat).
- **A requirement conflict is a surfaced trade-off, never a silent resolution**
  (2026-07-01) — the intent-time clause used to read "don't reverse a recorded
  decision" (old-always-wins, which quietly anchors new designs to legacy). It now
  reads "neither the old nor the new wins silently": a contradiction is flagged, and
  where the review loop presents options the conflicting one **names the recorded
  requirement it would retire**, so the owner can't pick a contradiction blind —
  retiring a requirement stays an explicit, recorded choice in either direction.
- **Cheap pre-filters keep the gates quiet** — escalate only on decision-bearing
  surfaces (deps/config/migrations), fenced-token overlap, or the hotspot subset.
  Precision over recall: a false block is noise.
- **Loop-proof + small-footprint** — each gate bounds itself (per-tree/per-ask consume
  or a per-session cap) and writes cache-only state, never the project.
- **YAGNI held** — the broader "a *tested* hotspot's fix should add a new case" tier
  was deliberately not built (over-nags). Further work is demand-driven.

## What's next

Demand-driven only — a new stack to lint, a real owner-not-at-the-terminal scenario,
or a pain point that surfaces. No new layers planned.

**Built (2026-07-07, later) — tests fully opt-in; autopilot never stalls for a playtest (tidy 0.41.0 / task-queue 0.40.0).**
Owner: "support the TDD pattern, don't force tests — let the user decide if/when." (1) **tidy** — the regression gate
(blocked untested scar-tissue hotspots) flipped from default-ON to **OPT-IN** (`CLAUDE_TIDY_REGRESSION_GATE=1`); the
per-edit coverage nudge flipped to opt-in (`CLAUDE_TIDY_COVERAGE=1`); the blast-radius nudge dropped its "cover with tests"
mandate ("make sure this change doesn't break them"). KEPT: the verification floor (runs EXISTING tests, silent when none)
— that's the TDD *support*, not forcing. (2) **task-queue** — `tq_park_rule` carves out a **human playtest** as the one
check you never park/stall for (a game's feel/visuals): finish the work, note "playtest pending", keep draining. Fixes the
contradiction where "a check you can't run → park it" made autopilot stall a game task. Two per-event budgets ratcheted for
the carve-out (960→1280, 780→1050). `./check.sh` green.

**Built (2026-07-07) — crash-recovery removed; three advisory→ENFORCED conversions (task-queue 0.39.0 / hud 0.17.0).**
Owner's throughline: most "features" were advisory text the model skips, so things "never happened" (agents rarely fanned
out, parked reviews were ignored). Fixes: (1) **removed crash-checkpoint entirely** — the hook, `refs/tq/checkpoint`, the
`/task-queue:checkpoint` command, lib, hud `🧷 logs` slot, `CLAUDE_TQ_CHECKPOINT_MODE`; `/task-queue:resume` kept (task
carryover only — owner explicitly wanted the explicit "bring my queue back" button). (2) **parked-review gate**
(`tq-review-guard`, PreToolUse-deny): when autopilot ends with a parked `❓` pile, edits are blocked until the owner has
reviewed each (menu) and cleared it; self-clears. (3) **design-preview gate** (`tq-design-guard`): a visual prompt arms a
marker (capture) that blocks edits until a wireframe AskUserQuestion is shown (ask-guard clears it) — show-before-build, no
rework. (4) **queue-aware agent fan-out**: capture names the independent unblocked tasks (`tq_ready_tasks`) and tells the
model to parallelize them — the hook selects, the model spawns (no hook can spawn agents). All three have `CLAUDE_TQ_*=0`
kill-switches + per-event token budgets. `./check.sh` green. **Parked for the owner: a Claude-only docs overhaul** — the
owner reads no `.md` files, so curate every doc (this repo's + what charter generates in other projects) for Claude, not
humans; trim the ROADMAP build-log (git holds history) and decide README/marketplace's fate.

**Built (2026-07-06, latest) — a prompt is presence: autopilot ≠ absent (task-queue 0.38.0).**
Owner hit the real footgun: while autopilot was on, typing a prompt left them stuck — the guard still hard-blocked
`AskUserQuestion`, the Stop hook kept auto-continuing, and the model looped on "the owner is away," parking instead of
engaging the person literally at the keyboard. Root cause: the away flag was a single per-repo bit that conflated
"declared they stepped away" with "absent right now." Fix: a **per-session owner-present marker** (`lib/away.sh` —
`tq_mark_present`/`tq_owner_present`, window `CLAUDE_TQ_PRESENT_WINDOW` default 1800s). tq-capture stamps it on every
prompt when away is on; the ask-guard and the capture loop consult it, so the **owner-driven turn stays interactive**
(asks allowed, loop fires with a present-note that overrides the standing "never ask" banner) while the **autonomous
drain that follows still parks** — tq-verify clears the marker when it enters auto-continue, and the window is a
self-expiring backstop if that clear never runs. Slash commands already jumped the queue (they exit tq-capture before
decomposition), so `/task-queue:autopilot` was always the instant manual out; this makes plain-language prompts safe too.
Window `0` = lights-out autopilot (even your own prompts stay autonomous), which also isolates the open-Q budget test.
Coverage: away.bats (present-allow, stale-deny, lights-out suppression, verify-clears-present), capture.bats (present
records intent, lights-out doesn't), token-budget (new away-present path, 789 chars). `./check.sh` green (353 checks).

**Built (2026-07-06) — toggle commands honor on/off, bare = on (task-queue 0.37.1).**
Follow-up to the grey-pill work below: the real footgun wasn't repaint, it was the commands. `/task-queue:autopilot`,
`:agents`, and `:checkpoint` hardcoded `toggle` in their `!` line and *discarded* the `on`/`off` argument the `/` menu lets
you type — so `… on` while already on ran a blind flip to **off** and the pill correctly greyed. Fixed by routing the arg
through: `action="$ARGUMENTS"; …/tq-*.sh "${action:-on}"`. Per the owner's call, a bare command now means **on** (type `off`
to turn off) rather than a surprise toggle; added `argument-hint: "[on|off]"` so the menu advertises it. Scripts already
accepted `on|off|toggle`, so no script logic changed — only which action the command hands them. `./check.sh` green.

**Built (2026-07-06) — zero-token-toggle honesty, no-stall autopilot, animated hud beacon (task-queue 0.37.0 / hud 0.16.0).**
Owner asked for token-free feature toggles + a status bar that reflects state (autopilot "stayed grey"). Brutally-honest
finding, surfaced and confirmed via AskUserQuestion: **no slash command can be zero-token** — the body is always handed to
the model; only the `!bash` prefix (with `respondToBashCommands:false`) is free, and the owner declined a `!tq` shim, so
toggles stay slash commands trimmed of their redundant relay (the `!` line already prints state). The grey pill was never a
state bug — hud read the flag correctly; nothing *repainted* the line until the next message. Fixed by `refreshInterval:1`
(hud-install.sh), which also drives a new **animated braille-orbit health beacon** (replaces the static ●, colour still =
health) and cost the deliberate no-refreshInterval/battery stance hud held — an owner-opted trade for a live line on their
handheld. Dropped the "tok" label (just ⇡/⇣ now). Autopilot gained a **never-stall** clause in `tq_park_rule` (rides into the
ask-guard deny + SessionStart + CLAUDE.md): an unparkable, progress-blocking decision defaults to the recommendation and drops
a ❓ to override, instead of pausing for an absent owner. Two pay-per-event token budgets ratcheted (760→960, 620→780) in the
same change. Tests pin the beacon paths, the never-stall clause, and the refreshInterval; `./check.sh` green.

**Built (2026-07-05) — parked-pile review menus + terminal-native hud palette (task-queue 0.36.0 / hud 0.15.0).**
Two owner-facing polish asks, one commit (#87). (1) **task-queue** — the parked-decision review got the
design-preview treatment. Turning autopilot *off* now prints the full parked `❓` pile as the return
checkpoint and soft-blocks new queue work until it's cleared, and every parked review — on autopilot exit
*or* any resurface — is presented as a blocking `AskUserQuestion` with 2-3 concrete options, recommended
first, instead of an open prose question. Same "verify by choosing, not by reading" posture the design
preview established, now applied to the decisions autopilot deferred. (2) **hud** — dropped the hardcoded
24-bit status-bar palette that churned through 0.11-0.14 (the scar-tissue the charter flagged) and emits
plain ANSI colors so the line inherits the user's terminal theme — the same palette the Claude Code CLI
renders with. Ending the palette-churn by *deleting* the palette, not tuning it again. Tests pin both paths;
`./check.sh` green.

**Built (2026-07-05) — green-CI fix for `tq-ship.sh` (0.35.2).** 0.35.0/0.35.1 shipped `main`
red: the new `bin/tq-ship.sh` had a best-effort sync line `git checkout … && git pull … || true` that CI's
shellcheck flags as SC2015 (`A && B || C` is not if-then-else), and `check.sh` runs `shellcheck -e SC1091`
with no severity floor so even an info-level finding exits 1. It passed *locally* because shellcheck 0.11.0
no longer flags the `|| true` idiom, but CI's older build does — a version-skew false-green. Rewrote the line
as an explicit `if git checkout …; then git pull … || true; fi` (behavior-identical, SC2015-safe on every
version). Lesson recorded: the local/CI shellcheck version gap can hide a red build behind a green `check.sh`.
task-queue v0.35.2.

**Built (2026-07-05, earlier) — cap the ❓ reminder + marketplace taglines (0.35.1).** Two efficiency
follow-ups. (1) The per-prompt open-questions reminder (`tq-capture.sh`) listed EVERY open ❓ on every
prompt — and 0.35.0's "park more decisions as ❓" made that pile grow, so it scaled badly per turn. Now
capped: first 4 + "…and N more" (same shape as the resume cap; fixed 4, no env knob). (2) `marketplace.json`
descriptions, which duplicated each `plugin.json` essay and drifted, were cut to one-line browse taglines —
a deliberately different register from the full `plugin.json` manifest, so there's nothing left to keep in
sync. Recorded the standing rule (memory): efficiency work = hook injections (runtime tokens); env-knob /
plugin.json / marketplace tidiness is maintenance-surface (zero runtime cost) — don't conflate. task-queue v0.35.1.

**Built (2026-07-05, later) — autopilot parks important decisions (corrects 0.34.0) + `/task-queue:ship`.**
Two more owner asks, same session. (1) The 0.34.0 "decides-not-parks" step below was **walked back
on the owner's review** — but sharpened, not naively reverted. The flaw: "reversibility" was the wrong
axis (git-reversible ≠ cheap-to-undo — a design direction is reversible yet expensive to unwind once
work is built on it). New threshold = what a wrong call would **COST to undo**, expressed as the same
"real signal" the normal review loop stops on: autopilot now PARKS important direction/design/structural
choices, new deps/seams, data-model/interface changes, ambiguous high-blast-radius forks, plus
irreversible/externally-binding actions — and DECIDES the routine, low-stakes rest. Goal the owner named:
come back to a **reviewable pile** of parked decisions, make the calls, autopilot resumes. One definition
of "worth the owner's attention," two modes — normal asks live, autopilot parks. (2) **`/task-queue:ship`**
(`bin/tq-ship.sh`) — one gated command from working tree to merged-on-main: verify green (the caller's
gate — a bash script can't know an arbitrary repo's tests), then branch-if-on-default → commit → push →
PR → squash-merge → delete branch → sync. Allowed unattended in autopilot **once green** (shipping a
verified, completed unit isn't a decision; any important decision inside it would have parked and blocked
completion first). v0.35.0.

**Built (2026-07-05) — `/task-queue:resume` + autopilot decides-not-parks.** Two owner
asks. (1) `restore` → **`resume`**: the crash-recovery command became the on-demand twin
of the SessionStart hook — `bin/tq-restore.sh` restores the working tree from the last
checkpoint AND re-surfaces earlier sessions' open tasks to reinstate, and is honest that a
slash command cannot reload the conversation itself (that is `claude --resume` at launch).
Reuses `tq_resume_context` + `tq-checkpoint.sh restore`, no new logic. (2) **Autopilot now
DECIDES the reversible calls** — design/taste/ambiguous forks included — taking the option
it would recommend and recording it for review, rather than parking them; parking is
narrowed to the genuinely IRREVERSIBLE/externally-binding or a check it physically cannot
run. Reversibility, not uncertainty, is the parking test (git + the armed checkpoint make
decisions undoable). Rationale: autopilot exists to make calls on the absent owner's behalf;
parking design/ambiguous forks defeated that. Touched the three parking strings (ask-guard,
signals banner, verify auto-continue) + the autopilot/CLAUDE.md/plugin.json prose; the
`PARK`/`❓ [parked]` tokens stayed so away.bats held. v0.34.0.

**Built (2026-07-03) — away-mode.** The "real owner-not-at-the-terminal scenario" the
"what's next" note was waiting for arrived (owner asked for it), so the in-CLI half is
built: `tq-away.sh` + the SessionStart AWAY block (autonomy + park-don't-ask, above). The
review surface is the existing `❓` open-questions bucket, deliberately reused (no new
marker, no hud-mirror change). Away `off` prints a return-digest (completed + parked
since the on-stamp); a staleness nudge guards against leaving it on. The *off-terminal
notification* half below stays scoped.

**Built (2026-07-03) — crash-checkpoint.** Closes the last crash gap (queue + mid-task
breadcrumb were already covered): uncommitted working-tree edits. Opt-in `tq-checkpoint.sh`
snapshots tracked+untracked work to a hidden `refs/tq/checkpoint` via a throwaway index
(HEAD/index/worktree/history all untouched, never pushed), wired on PostToolUse; hud shows
a `🧷 ckpt` armed marker. Chose snapshot-refs over WIP-commits to keep history clean, and
NO auto-push (push is the irreversible action away-mode parks — auto-doing it would
contradict that decision, and a local snapshot already covers a reboot-crash). This is the
**one hook that writes to git** — a deliberate, opt-in exception to the read-only invariant.

**Built (2026-07-03) — architecture/assumption present-options.** The design-preview flow
generalized (by model judgment, not a regex — per 2026-06-27 split-from-interrupt) to
architecturally-significant / assumption-dependent work, plus a strengthened ruthless-
challenge posture where retiring a prior requirement is a *visible* trade-off, never silent
(preserves fb152ac).

**Built (2026-07-03) — task-queue slash commands.** task-queue had NO commands (its verbs
were plain-language → bash). Added an *optional* `/task-queue:` control plane — `:status`
(modes + open-work readout, not a task re-listing), `:away`/`:checkpoint`/`:pause`/`:agent`
(on|off toggles), `:restore` (recover from the last checkpoint). Commands cover the
deterministic CONTROL plane only; queuing WORK stays natural-language + the native list
(no task-CRUD commands — that would duplicate native + betray "native list = the queue").
Natural language still triggers every mode too ("both"), so the README's "need never run a
command" promise holds — commands are additive, never required. The flag-plumbing dedup was
evaluated and rejected (deletion test; see memory).

**Built (2026-07-04, later) — per-feature commands + global-default checkpoint/agents.**
Superseding the `/tq` consolidation below, on the owner's call: the single `/tq` hub was
retired for **one typeable slash command per feature** — `/task-queue:autopilot`, `:checkpoint`,
`:agents` (each toggles + announces its new state), `:restore`, `:status`. Rationale: Claude
Code's `/` autocomplete makes discrete, described commands MORE discoverable for a non-technical
owner than subcommands hidden inside one command — the reverse of the "six slugs is clutter"
premise that drove the consolidation (lived usability beat maintainer tidiness). Names are the
owner's (autopilot/checkpoint/agents — not safety-net/helpers). Checkpoint and agents gained a
**global-default env** (`CLAUDE_TQ_CHECKPOINT_MODE` / `CLAUDE_TQ_AGENT_MODE=on`) so the owner can
arm them across every repo from `settings.json` without per-repo toggling; the **shipped default
stays off**, so the "checkpoint is opt-in" hard invariant holds, and an explicit per-repo `off`
writes a tombstone that wins over the global default. **hud** redesigned to match: the `$`
session-cost and `ctx %` slots dropped, the three when-on feature icons replaced by one
always-visible feature-status readout in full words (autopilot/checkpoint/agents on|off), and the
`Model:` label dropped (name kept). Versions: task-queue 0.32→0.33, hud 0.8.1→0.9.0.

**Built (2026-07-04) — solo mode (enforced autonomy) + the `/tq` command.** Away-mode was
advisory: it *told* the model not to block, but nothing stopped a normal end-of-turn `Stop`
from handing control back to an absent owner, and `AskUserQuestion` could still fire — so it
"paused even with away on" (the owner's report). Fixed at the one surface that controls
pausing, the Stop hook: **(A)** while away + non-`❓` work is queued, `tq-verify` returns
`decision:block` and auto-continues the queue, self-terminating when only `❓` parked items
remain, bounded by a per-prompt counter (`CLAUDE_TQ_AWAY_MAX_CONTINUE`, default 40) so it
can't spin; **(B)** a new PreToolUse guard (`tq-ask-guard`) hard-blocks `AskUserQuestion`
while away, redirecting to park-as-`❓`. Command UX then collapsed: the six `/task-queue:*`
slugs became one explorable `/tq` (bare = menu; `solo|checkpoint|agent on|off`, `undo`,
`status`), and *away* + *pause* merged into **solo** (`/tq solo`) — the ask-guard makes the
approval checkpoint moot, so one autonomous toggle covers both. **Visible trade-off:** the
standalone `pause` command is retired (folded into solo) — the "run in auto but stay present
& askable" middle ground is gone; the pause *flag* plumbing stays (env/legacy), and `solo
off` clears it. Supersedes the 2026-07-03 slash-command entry above (that `/task-queue:` set
is replaced by `/tq`). Natural language still drives every mode, so the "need never run a
command" promise holds.

**Scoped (not built) — async owner recap.** The one place an MCP integration earns
its keep: when the owner is *away from the terminal*, the Stop-time recap (today only
in-session) never reaches them. Now that away-mode exists, this would gate on that flag. Shape if/when that scenario is real: **trigger** — the
intent→outcome gate already composes the plain-language "did we build what you asked"
recap at Stop; reuse it, gated on an explicit owner-away signal (env opt-in or a
quiet-hours window), never on every Stop. **Payload** — that same recap text + the ✓/✗
verify outcome + any 🛡✗ disabled floors (so the away owner sees a degraded beacon they
can't), as one short message. **Delivery** — a single MCP send (e.g. Gmail
`create_draft`/email); no new plugin, no audit log, no two-way control loop. **Boundaries**
— additive weight only in the away case (silent otherwise), best-effort (a failed send
never blocks Stop), and it *reports*, it doesn't *act*. Don't build until "owner away"
actually happens — building it for a scenario that isn't occurring is the over-engineering
this system pushes back on.
