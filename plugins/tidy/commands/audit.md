---
description: Audit the whole project against the clean-code guidelines (file size, blast radius, cruft) and auto-queue the cleanup as tasks
allowed-tools: Bash, TaskCreate, TaskList
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tidy-distill.sh"

The report above is a read-only, whole-project **weight report** measured against this
project's own guidelines — heaviest / over-budget files (the **file-size** budget), cruft
markers, junk artefacts, and the **complexity surface** (dependencies + top-level areas,
the drivers of **blast-radius** growth). It only surfaces measurable facts; turning them
into work is your job.

**This is a manually-triggered audit, so queue aggressively — the trigger IS the owner's
approval.** Turn the findings into a live cleanup backlog:

1. **Auto-queue every actionable finding** as its own scoped `TaskCreate` task — do NOT
   run the per-item present-and-approve loop and do NOT ask; the owner ran this command to
   get a queued pile. One task per unit of work: each over-budget file (split into cohesive
   units / prune dead code / dedupe below budget), each junk artefact to delete, a triage
   task if cruft markers are notable, and any **doc↔code drift** you spot (README / ROADMAP
   / MAP referencing moved or removed files, stale examples). Fold in any **scar-tissue
   hotspots** already surfaced this session (repeatedly-fixed files) — characterize before
   cutting them.
2. **Order smallest-blast-radius first** — leaf files (nothing imports them) before
   high-fan-in ones — so the queue drains from the safest end, matching the decompose rule.
3. **The one exception — park, don't queue:** a finding that carries an *obvious* risk or
   reason not to auto-add — a deletion where you're not sure the code is dead, a
   high-blast-radius restructure, or anything irreversible / genuinely ambiguous — is
   PARKED as a `❓ [parked]` task for the owner instead of queued as work. That's the only
   thing that doesn't go straight into the backlog; everything clearly safe does.
4. Then **work the queue in auto** per the project's loop (autopilot-aware; fan disjoint
   file-level cleanups out to parallel agents when agent-mode is on). Keep net surface flat
   or smaller — reuse before create, delete what a change makes redundant; confirm before
   any deletion you parked.

Relay in one plain line what you queued (how many tasks, and anything you parked).
