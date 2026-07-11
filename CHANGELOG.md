# Changelog

Notable changes. Per-change detail lives in `git log`; this file keeps the headlines.

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
