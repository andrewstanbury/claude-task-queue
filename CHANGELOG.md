# Changelog

Notable changes. Per-change detail lives in `git log`; this file keeps the headlines.

## companion 2.0.1 — 2026-07-12

- **Docs reconcile** (no behavior change) — `AGENTS.md` and `docs/ROADMAP.md` had drifted (last
  reconciled at 1.3.0): refreshed the enforced-core lists (touch.sh format-only + autopilot), the
  command set (`audit`→`advise`), the test-file split (`companion-{core,hud,fuzz}.bats`), and the
  decision arc through R32. Documented `tq`'s single-writer assumption in its header.

## companion 2.0.0 — 2026-07-12

Self-critique pass: `/companion:advise` run on the plugin itself (an independent 4-lens critic
panel) found a real bug and that several 1.7–1.9 additions over-reached (ledger R32). All 9 fixes:

- **BREAKING — `/companion:audit` retired**, merged into `/companion:advise` (which now also does
  the whole-project cleanliness sweep; few findings → one-at-a-time, many → queued directly).
- **Bug fix** — the status line mis-parsed a model name or project path containing a space (default
  `IFS` split the tab-separated fields); now `IFS=$'\t'`, with a regression test.
- **`touch.sh` drops the `pre-commit` fast-path** — it could hang an edit for minutes on first run
  and ran linters, not just formatters; per-extension formatters (config-aware) remain.
- **`pre-compact.sh` deleted** — it was an advisory nudge wearing a hook, contradicting R28; the
  reliable compaction re-anchor (SessionStart) stays.
- **Compaction re-anchor trimmed** — re-injects the queue + LESSONS + a pointer, not the full
  ~2.4k-token STEERING (saves that per compaction).
- **Status line `refreshInterval` 1 → 3s** — keeps the beacon while cutting the idle wake ~3×.
- **Secret gate**: vendor-anchored key shapes still block (exit 2); the fuzzy `name=value`
  heuristic now only *warns*, so it can't false-block a legitimate edit.
- **`tq cancel <id>`** — retract a mis-queued task (cancelled; excluded from counts + resume, file
  kept) instead of a false `done` or a lingering `open`.
- **README** — a commands list (incl. `advise`), a status-line glyph legend, and a "turn on the
  status line" callout.

## companion 1.9.0 — 2026-07-12

Completes the R30 Claude-first refinements (Batch 3 of 3):

- **Compaction re-anchor** (R30·d2) — `session-start.sh` fires on `source=compact`, so after the
  context is summarized it re-injects STEERING + the live queue (with each task's done-when) +
  LESSONS, with a compaction-aware lead. A new `pre-compact.sh` (PreCompact) nudges the model to
  freshen the in-progress breadcrumb/done-when just before the summary.
- **Challenge slot + devil's-advocate** (R30·d6) — `/companion:ship-it` now requires stating
  risks / what-changes / R-IDs before committing, and spawns a devil's-advocate sub-agent (an
  independent context prompted to attack the change) for consequential ships.
- **Audit is a sub-agent panel** (R30·d5) — `/companion:audit` fans out one lens per sub-agent
  (size / debt / blast-radius / perf), synthesizes, and queues — main context stays clean.

## companion 1.8.0 — 2026-07-12

- **Tasks carry a `done-when`** (R30·d1) — `tq add … --done "<acceptance>"` (or `tq done-when <id>`);
  the acceptance test renders in the report + SessionStart resume, so a task re-read after a
  context compaction re-derives the right next action instead of guessing at a bare subject.
- **STEERING is checklist-first** (R30·d3) — each section opens with an imperative "Moves"
  checklist; the prose rationale stays below it. Scannable for compliance, keeps the *why*.
- **CI hardening** (R30·d8) — a hook-fuzz test (every hook survives empty / garbage / truncated /
  huge / emoji stdin without crashing) + strict conditions locked in: scrubbed git identity, so a
  test that forgets `-c user.email` fails in CI rather than in a user's repo.

## companion 1.7.0 — 2026-07-12

- **Project `LESSONS.md`** (R30·d7) — a curated, model-maintained file of repo-specific gotchas
  (portability/test/CI traps), injected each session by `session-start.sh` so a new session doesn't
  re-learn them. Gotchas only; decisions stay in the ledger, work in the queue.
- **Activity-only beacon** (R30·d9) — the status-line beacon now animates only while there's work
  in motion (autopilot draining or a task in-progress) and shows a static ● when idle.
- **Formatter respects the project's toolchain** (R30·d4) — `touch.sh` prefers the project's own
  `pre-commit` on the touched file when configured, and honors black-vs-ruff from `pyproject`,
  before falling back to the per-extension formatter.
- **Playtests are autopilot-conditional** (ledger R31) — under autopilot the companion no longer
  raises playtests (it captures a `⏳ [blocked] playtest` task instead, resurfaced on return);
  with autopilot off it offers a quick playtest when the change has a human-observable surface.

## companion 1.6.0 — 2026-07-12

- **`/companion:advise`** (ledger R29) — an independent, brutally-honest critique ritual. Takes a
  target (file / subsystem / decision / topic; default: the whole project), spawns a critic
  **panel** with distinct lenses so the critique comes from contexts that didn't build the thing,
  and presents each recommended change as a **recommendation-first `AskUserQuestion`, one at a
  time**; then closes the loop into `tq` + an offered ledger entry. Every critic may conclude "no
  change" — a manufactured delta is the fake pushback the steering doc forbids. Operationalizes
  the R5/R17 challenge posture as an on-demand command; owner-present (blocked under autopilot).

## companion 1.5.0 — 2026-07-12

- **Status bar redesign** — the single `📋 N` count split into `◻ open · ❓ parked · ⏳ blocked`,
  plus git `↑ahead ↓behind`. The parked-task scan behind it is now a single `jq` pass (~18×
  faster; it runs every second).
- **Architecture realignment (ledger R28)** — the hook/steering boundary is now decided by a
  component's *nature*: code only for what must **execute** (the formatter) or **block** (the
  secret gate), plus autopilot's control-flow guarantee — **judgment and nudges are steering.**
  This **retired the R27 edit-gates** (design-preview + return-review) and the intent→outcome
  reminder; `touch.sh` is now **format-only** (blast-radius + size → steering, R25 reshaped).
  Deleted `work-guard.sh`, `prompt.sh`, `intent-note.sh`; retired `CLAUDE_COMPANION_GATES` and
  `CLAUDE_COMPANION_SIZE_BUDGET`.
- Tests split into `companion-core.bats` / `companion-hud.bats`. CI hardening folded in from
  1.4.x (git identity in tests, jq broken-pipe, macOS bash-3.2 status-line crash).

## companion 1.4.0 — 2026-07-12

- **Animated status line** — a braille-orbit health beacon (`refreshInterval:1`), `│ 🛡 │`
  spacing fix, consolidated off the deprecated `hud` plugin onto `companion`. (Kept in 1.5.0.)
- **R27 edit-gates** (design-preview + return-review blocks, intent→outcome reminder) + 🎨/🔒
  status icons — **retired one day later in 1.5.0 (R28)** as the wrong side of the hook/steering
  line. `author` field added; macOS + CI hardening (1.4.1–1.4.2).

## companion 1.3.0 — 2026-07-12

- **`/companion:ship-it`** — verify the project's gate → commit → push → PR/merge to the
  default branch. Codifies the ship flow.
- **`/companion:resume`** + `bin/resume.sh` — manually re-surface this repo's unfinished tasks
  from an earlier session (the on-demand twin of the automatic SessionStart resume).
- Internal: the shared `lib/companion.sh` (renamed from `lib/autopilot.sh`) now holds the
  cross-session open-tasks helper, used by both SessionStart and manual resume.
- First step of "restore features onto the one-plugin spine" — the removed commands other than
  these two stay gone by owner choice.

## companion 1.2.0 — 2026-07-11

- **Autopilot is enforced + persisted** (ledger R26). `/companion:autopilot on|off` sets a
  per-repo flag that survives restarts; while on, the Stop hook auto-continues the queue (until
  only parked ❓/⏳ remain, no-progress capped) and a PreToolUse guard blocks `AskUserQuestion`.
  The status line shows ✈️. Env: `CLAUDE_COMPANION_AUTOPILOT_CONTINUE`, `_MAX`, `_STATE_DIR`.
- **Design-preview restored** to the steering doc: the full wireframe convention
  (`╔═╗` container, `▒` input, `█` primary, recommended-first) — steering-only, no gate.
- (These closed the two advisory-only gaps from the post-rebuild capability review.)

## companion 1.1.0 — 2026-07-11

- **Clean-as-you-touch** (`bin/touch.sh`, PostToolUse): after you edit a file, format it with
  the project's own formatter, surface its blast radius (dependents), and flag it if it's over
  the size budget. Non-blocking; `CLAUDE_COMPANION_TOUCH=0` disables, `CLAUDE_COMPANION_SIZE_BUDGET`
  tunes size. A conscious partial-reversal of the rebuild's austerity (ledger R25).
- **`/companion:audit`** — on-demand whole-project sweep (size / debt / blast-radius hotspots),
  queues the fixes via `tq`.
- The task queue is now fully self-owned (its own store, not native tasks), reprints on every
  state change, and a minimal status line returned. (Rolled up from the same day.)

## companion 1.0.0 — 2026-07-11

**Ground-up rebuild.** The four plugins (`task-queue`, `tidy`, `charter`, `hud`) were
replaced by one plugin, **`companion`**, built on a single principle: *steering is a
document, enforcement is code, never confuse the two.*

- **Steering** — all the prose that shapes how Claude works (task queue, the brutal-honest
  recommendation posture against the requirements ledger, clean-as-you-go, autopilot) now
  lives in one file, `plugins/companion/STEERING.md`, put in context once per session.
- **Enforced core** — the only behavior that must execute or block, kept as code: a pre-write
  secret gate (`secret-guard.sh`), cross-session task resume (`session-start.sh`), and the
  `tq` queue fallback for models with the native task tools gated off.
- **Retired**: the per-hook token-budget NFR, the cross-plugin drift-guard and mirrored
  detectors, the status line (`hud`), and every advisory Stop/PreToolUse prose-hook.
- ~12,500 lines → a few hundred. Rationale and reshaped requirements: `docs/REQUIREMENTS.md`
  (R24).

## Before 1.0.0

The four-plugin history (task-queue / tidy / charter / hud, versioned independently through
mid-2026) is in `git log` — the commit messages carry the same detail this file used to.
