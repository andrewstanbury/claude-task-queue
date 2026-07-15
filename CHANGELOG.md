# Changelog

Notable changes. Per-change detail lives in `git log`; this file keeps the headlines.

## companion 2.12.1 — 2026-07-14

- **Surface the latest note on cross-session resume** — completes the notes-array feature from
  2.12.0, which *stored* `.notes[]` but nothing *read* it. `companion_open_tasks` (the
  resume / post-compaction re-anchor renderer) now shows a `└ note: <latest>` line under each
  carried-over task, beside the existing `└ done when:` line — so a crash/compaction resumes from
  the last breadcrumb, not just the subject. Falls back to legacy `.description` for pre-array
  tasks. Resume-only: the live `tq report` stays Design-D compact, so **R47** is untouched.

## companion 2.12.0 — 2026-07-14

- **Ported the two verified fixes from third-party PR #126** (author co-credited): `tq note` now
  **appends to `.notes[]`** instead of overwriting `.description`, so a second breadcrumb no longer
  erases the first; and the autopilot continue-nudge (`stop-autopilot.sh`) now names the next task's
  **`#id` + done-when**, so the model resumes against acceptance criteria, not a bare subject. The
  **symlink-safe `SELF` resolution** across all `bin/` scripts (relative `readlink` targets resolved
  against the symlink's own dir — fixes central-symlink installs) was salvaged from the same PR.
- **Declined the rest of #126, on review** — its `tq report` rewrite reversed locked **R47**; its
  statusline count refactor dropped in-progress tasks from the `📋` count (a regression, and not one
  of the PR's stated bugs); it added a dangling `lib/tidy.sh` reference; and it stripped `R##` comment
  anchors repo-wide (kept, per **R45/R46**). PR #126 superseded and closed with the rationale.

## companion 2.11.0 — 2026-07-14

- **The recommendation contract** (ledger **R49**, 🔒) — sharpens the brutal-honest posture from
  advisory prose the model skips into an explicit contract: a request that asks you to
  choose / redesign / compare / evaluate / "what do you recommend" **owes 2–4 genuinely different
  options, each naming its cost, the recommended one marked first, plus the honest read** (up to
  "don't do this"). It fires **identically off or on autopilot** — off, ask it live
  (`AskUserQuestion`); on, park the *same* payload in the `❓` subject so the resume review is a real
  choice, not a rubber-stamp. STEERING + the `ask-guard` deny message; refines **R36/R38/R39**;
  generic per **R9** (judgment by reading the request, never a keyword hook).

## companion 2.10.0 — 2026-07-14

- **`tq report` → Design-D compact** (ledger **R47**, 🔒) — the report is now a glyph-count header
  (`📋 ▸n ◻n ❓n ⏳n ✔n`), **one line per active task**, completed shown as a **count only**, and a
  trailing `→ next: #id` pointer. `done_when` is no longer rendered in the live report (it reprints
  on every `add`/`doing`/`done`, so its height is a constant tax) — it's still **stored** and
  re-surfaced on cross-session resume, so crash-resume is unaffected. STEERING notes the `→ next`
  pointer is a *mechanical* default: override it aloud when blast-radius/dependency says otherwise.
- **Testing policy: keep the enforcement spine, don't grow format tests** (ledger **R48**, 🔒) — an
  audit found the ~30-case suite is mostly real enforcement (secret gate, hook-fuzz contract,
  autopilot control-flow, ship-mode-never-touches-default, validators), not theater. Policy: keep
  `check.sh` green; when an intentional change reddens an assertion, **loosen it to behavioral**
  rather than pin cosmetics; don't add a format test per feature. Removed 4,500 lines of stale
  `hud-gates` worktree tests. Reshapes CLAUDE.md's "verify with `./check.sh`" into keep-green-don't-grow.

## companion 2.9.0 — 2026-07-13

- **`/companion:document` refinement + first dogfood run** (ledger R41 refined; R42–R46 added). The
  command now presents its candidate *whys* as the multiple-choice options — the owner picks or
  overrides, there is **always** an open-ended "write your own rationale," and **only an active pick
  records an entry** (an unchosen guess never becomes a 🔒). Running it on this repo recorded five
  previously-undocumented, load-bearing decisions: the `❓/⏳` prefix-view over `pending` (R42), the
  secret gate now covering `NotebookEdit`'s `.new_source` (R43), `tq`'s atomic temp-then-`mv` writes
  (R44), `stop-autopilot`'s redundant default-branch guard (R45), and `IFS=$'\t'` on tab-delimited
  reads (R46) — three backed by executable checks. Fixed two stale-doc drifts (statusline
  `refreshInterval` comments, MAP `touch.sh` row).

## companion 2.8.1 — 2026-07-13

- **De-dup autopilot flag teardown** — new `companion_autopilot_clear()` shared helper; `resume.sh`
  and `autopilot.sh off` both call it instead of a hand-rolled `rm -f`, so the teardown can't drift.
  Internal refactor, no behavior change (closes the R39 devil's-advocate follow-up).

## companion 2.8.0 — 2026-07-13

- **`/companion:document`** (ledger R41) — new command, the *producer* side of advise: scans an
  existing repo for load-bearing, undocumented decisions and records them tiered *executable check ›
  🔒 › 🔓 › dropped*, with strength-of-why setting the lock and a provenance tag — so advise stops
  guessing and can't reverse a critical choice that was never written down. Reuses the R29/R38 loop,
  writes the existing ledger (no new doc format), generic per R9, a command not a hook (R28).

## companion 2.7.0 — 2026-07-13

- **`/companion:ship-it` produces review-optimized output** (ledger R40) — structured commit/PR
  messages (What/Why/requirement-IDs/tasks/tests), curated one-commit-per-logical-unit history on
  `autopilot/*` merges instead of an opaque squash (reshapes R34's squash-on-ship; the per-turn
  capture is unchanged), structured PR bodies, and a right-size nudge for large/mixed diffs — so
  shipped work reads as easy-to-review even when no human reviews it.

## companion 2.6.0 — 2026-07-13

- **`/companion:resume` is a triage handoff** (ledger R39) — it turns autopilot off first
  (announced, never a silent clobber) so the resurfaced pile comes back to the owner, reinstates
  carried-over tasks preserving their `❓/⏳/📋` classification (never promoting a parked decision to
  a plain open task), then runs the R38 review. The fix lives in the task's *type*, so
  triage-vs-drain survives in either mode.

## companion 2.5.0 — 2026-07-13

- **Turning autopilot off starts a parked-pile review** (ledger R38) — new `/companion:review`:
  walks the `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first, and records each
  pick back to `tq` **before** any new work. Triggered two ways so neither path misses it — the
  `/companion:autopilot off` command invokes it, and a STEERING clause fires it on the plain-language
  "turn it off" path. Scope is parked+blocked only (open tasks need doing, not deciding); each item
  can be deferred and the owner can bail (default, not a wall); clean no-op when the pile is empty.
  A **command, not a hook** (R28 — presenting recommendations is `AskUserQuestion` workflow), reusing
  the `/companion:advise` loop (R29) rather than a parallel machine.

## companion 2.4.0 — 2026-07-13

- **Domain-glossary layer** (ledger R37) — a project the companion governs keeps a terse,
  Claude-facing `docs/GLOSSARY.md` mapping a *coined term → its meaning* (e.g. "materialization
  cascade"); Claude coins one when a concept recurs and reuses it when naming, so one word carries
  twenty and naming stays consistent. Joins the map + ledger + stack-notes as part of a
  self-describing project (STEERING), **loaded on demand — not injected each session** — so it can't
  erode the token-efficiency value (R3). Steering convention, not a hook (R28). The one idea mined
  from mattpocock/skills' `CONTEXT.md`; this repo dogfoods its own `docs/GLOSSARY.md`.

## companion 2.3.0 — 2026-07-12

- **Autopilot reframed as "keep-going," not "owner-away"** (ledger R36) — it means keep draining the
  queue without stopping; the owner may be present, queuing tasks and keeping it on deliberately.
  Behaviors are unchanged (don't stop to ask, park decisions + design/taste choices, reversible-only)
  — the "away / when they return" framing is gone from STEERING, the ask-guard, stop-autopilot, and
  the docs. This dissolves the R33 present/absent tension: there's no presence to detect.
- **Ship-mode won't commit a hardcoded secret** (R34 gap fix) — before an auto-commit checkpoint it
  scans the staged diff for high-confidence key shapes and skips (unstages) if one is present
  (`git add` isn't seen by the secret gate). The gate keeps its own inline copy of the regex so it
  never gains a fail-open dependency.

## companion 2.2.0 — 2026-07-12

- **Ship-mode** (ledger R34) — `/companion:autopilot ship on`: while autopilot is on, the Stop hook
  auto-commits each turn's work to an `autopilot/*` branch (reversible checkpoints; **never the
  default branch, never a push**) for you to review + `/companion:ship-it` on return. Shown as 📦.
  The safe subset of "auto-ship": commit is reversible; the push/merge stays your manual command.
- **ship-it prunes merged branches** (ledger R35) — after merging to the default branch, it deletes
  the branch it shipped (local + remote) and prunes other `--merged` branches via `git branch -d`
  (never `-D`, never the default/current); shared repos are confirmed before deleting remote branches.
- **Status line regrouped** (R34) — three plugin sections, then generic: ⠋ beacon · │ 🛡️ ✈️ 📦 │
  (active features) · │ 📋 ❓ ⏳ │ (the queue, its own section) · model · git. The shield gained an
  emoji variation selector (🛡️) so it renders at consistent width with the other icons.

## companion 2.1.0 — 2026-07-12

- **Status-line task icon** — the open-task count is now `📋 N` (was `◻N`), with a space after the
  icon (and after `❓`/`⏳`). The emoji renders consistently where `◻` could show as a tofu box.
  (The per-item bullet in the `tq` report + resume stays `◻`.)
- **Autopilot parks design choices** (ledger R33) — a visual/design/direction/wording choice is the
  owner's call even when reversible, so under autopilot it's parked (`❓`, with options +
  recommendation) and surfaced on return rather than auto-decided. Refines R26: reversibility was
  the only auto-decide axis; ownership of taste was the missing one. STEERING + the ask-guard
  message, no new hook.

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
