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

### 0.19.0
- `⏳N` owner-blocked count in the status line.

### 0.18.0
- Status-line alignment with the opt-in test changes.

### 0.16.0 – 0.17.0
- Trimmed toggles; animated autopilot beacon; enforced-gate indicators.

### Earlier
- Icon-led feature slot (✈️ autopilot · 🧷 checkpoint · 🤖 agents); token-throughput
  slot; `🛡✗` disabled-floor marker + `/hud:legend`; Claude-muted terminal palette.
