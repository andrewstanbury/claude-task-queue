# Changelog

All notable changes to the four plugins in this repo. Each plugin versions
independently; the entries below are grouped per plugin. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/).

## Unreleased

Launch-hardening pass (no version bumps yet):

- macOS portability fixes across the hook scripts.
- Full user-facing configuration reference at [docs/CONFIG.md](docs/CONFIG.md).
- Per-plugin READMEs.
- Secret scan extended to cover `NotebookEdit` writes.
- Stop-hook timeout so a slow verify can't stall turn completion.

## task-queue

### 0.42.2
- Fixed a return-review-gate lock: a crashed autopilot session's unresolved `❓`
  could block editing repo-wide forever — the parked-pile check now ages out
  abandoned sessions (same cutoff as the resume bridge).
- `tq_root_for_cwd` resolves a git submodule to its own working root instead of a
  shared `.git/modules` path (sibling submodules no longer collide to one flag key).
- Per-repo flag files now use an injective encoding (`/`→`%2F`), so two repos whose
  paths differ only by `-` vs `/` no longer share autopilot/agent/review state. NOTE:
  a one-time reset — flags set before this upgrade read as off until re-toggled.
- Extracted the resume bridge to `lib/resume.sh` so the per-prompt hot path doesn't
  parse it and `lib/tasks.sh` stays under the size budget.
- `tq-capture` runs best-effort (`set +e`) like the other per-prompt hooks.

### 0.42.0
- `⏳` owner-blocked marker (drains the queue around owner-action items); leaner
  autopilot drain; `/task-queue:ship` renamed to `/task-queue:ship-it`.

### 0.40.0
- Tests are fully opt-in (never forced); autopilot never stalls for a human playtest.

### 0.39.0
- Removed crash-recovery; enforced the parked-review + design-preview gates;
  queue-aware agent fan-out.

### 0.38.0
- A prompt is presence — autopilot ≠ absent (owner-present marker unblocks asks).

### 0.37.x
- Toggle commands honor explicit `on`/`off` (bare = on); trimmed toggles;
  no-stall autopilot.

### 0.35.x
- `/task-queue:ship` + `/task-queue:resume`; autopilot parks important decisions
  rather than guessing; per-prompt `❓` reminder cap; token/dedup cleanups.

### 0.34.0
- `/task-queue:resume`; autopilot decides-not-parks the routine calls.

### Earlier
- Per-feature slash commands replacing the single `/tq` hub; enforced autopilot
  (auto-continue + ask-block); away-mode, mid-task resume; every prompt routed
  through the review loop; requirement conflicts surfaced as visible trade-offs.

## tidy

### 0.42.1
- Verification-floor bounded counters (quality / coverage / regression / test) share
  `tidy_gate_count`/`tidy_gate_bump` helpers so the "can never loop" arithmetic lives
  in one place instead of four hand-copies.

### 0.42.0
- `/tidy:audit` — on-demand whole-project audit that auto-queues cleanup.

### 0.41.0
- Tests fully opt-in (never forced).

### Earlier
- Auto-format on touch (project's own formatter); blast-radius surfacing;
  import-cycle check; file-size budget with deliberate-prune routing.

## charter

### 0.23.0
- Language-agnostic convention detection; generic-rules invariant made explicit
  (no hardcoded language/framework allowlists).

### 0.22.0
- Docs optimized for Claude; charter token trim.

### Earlier
- React Native convention detection, disambiguated from web; structural web-app
  detection for the web-QA nudge.

## hud

### 0.20.5
- Feature-zone spacing: the wide toggle emoji (`✈️`/`🤖`) now hug the trailing `│` divider
  (tight, no leading space) so a font that under-fills the emoji's 2-cell slot no longer
  looks double-spaced before the bar — `│ 🤖 │` reads even.

### 0.20.4
- The health-beacon spinner now animates on a no-color terminal too — the braille frames
  read by shape, so `NO_COLOR` no longer freezes the beacon. Only a `TERM=dumb` terminal
  (which may not render braille) falls back to the static `●`.

### 0.20.3
- Tests outcome shows a self-colored emoji (`✅` pass / `❌` fail / `⚠️` timeout) instead
  of a text `✓`/`✗`, so it stays colorful even on a no-color terminal.

### 0.20.2
- Cleaner status line: feature toggles are now bare icons (`✈️` autopilot, `🤖` agents)
  shown only when on, tests show a bare check, and the edit-gates keep a short word only
  while armed (`🎨 design`, `🔒 review`). The `🛡` safety shield stays.
- Added a project-name anchor just left of the branch (truncated; wide terminals only)
  so multi-repo users can tell panes apart at a glance.
- Submodule-aware root resolution (matches task-queue) so a submodule's status line
  keys to its own root, not a shared `.git/modules` path; mirrors task-queue's new
  injective flag encoding.
- `❓`/`⏳` counters strip leading whitespace before matching, agreeing with
  task-queue's marker predicates (an indented subject no longer miscounts).

### 0.20.0
- Always-on `🛡` safety shield (green when every floor is on, `🛡✗N` when any are
  off) — a positive "you're protected" signal, not just an exception warning.
- Two edit-gate indicators: `🔒` when the return-review gate is armed and `🎨`
  while a design-preview is pending. (task-queue relocates the design marker into
  the shared state dir so the status line can read it read-only.)

### 0.19.0
- `⏳N` owner-blocked count in the status line.

### 0.18.0
- Status-line alignment with the opt-in test changes.

### 0.16.0 – 0.17.0
- Trimmed toggles; animated autopilot beacon; enforced-gate indicators.

### Earlier
- Icon-led feature slot (✈️ autopilot · 🧷 checkpoint · 🤖 agents); token-throughput
  slot; `🛡✗` disabled-floor marker + `/hud:legend`; Claude-muted terminal palette.
