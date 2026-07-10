---
description: Audit the whole project against the clean-code guidelines (file size, blast radius, cruft, performance hot-paths) and auto-queue the cleanup as tasks
allowed-tools: Bash, TaskCreate, TaskList
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tidy-distill.sh"

The report above is a read-only, whole-project **weight report** measured against this
project's own guidelines — heaviest / over-budget files (the **file-size** budget), cruft
markers, junk artefacts, and the **complexity surface** (dependencies + top-level areas,
the drivers of **blast-radius** growth). It only surfaces measurable facts; turning them
into work is your job.

**Also run a PERFORMANCE pass — model-driven and generic.** The report above is static
structure; performance is a RUNTIME property, so this part is your judgement, not the script.
Recognise the project's HOT / REALTIME paths yourself from the code and its engine — a frame /
update / physics / tick loop, render or draw calls, input handlers, high-frequency event
callbacks, shaders or GPU work, anything on a per-frame or per-request budget — and flag
changed or existing code that likely costs time THERE: memory allocated / garbage created per
frame, O(n) or worse work run every frame, unbounded growth, blocking or synchronous I/O in the
loop, or repeated expensive lookups that could be cached, precomputed, or moved off the hot
path. Queue each likely regression as a task with a concrete fix (PARK it if the fix is
ambiguous or high-blast-radius). Stay GENERIC — bake in NO engine/framework/language
assumptions; recognise the hot path from the project's own structure (you already know every
engine). The ONLY concrete thing to run is the project's OWN profiler / benchmark command, if
it has one.

**Be honest about the hard limit: this audit CANNOT measure fps, frame-time, or thermals** —
those are runtime, seen only by PROFILING the running build on the target device (a handheld's
fan/thermals show up in a playtest, not in source). So never assert a number; for any
perf-sensitive change, queue a task to capture a BEFORE/AFTER profile (frame time, allocations,
draw calls — plus a thermal/fan check during playtest on battery/handheld targets) and mitigate
only what the measurement confirms. And do NOT chase cold-path or one-time costs — optimising
off the hot path is premature and just adds noise; a perf finding needs a realtime/hot path or
a real measured cost behind it.

**This is a manually-triggered audit, so queue aggressively — the trigger IS the owner's
approval.** Turn the findings (weight report + your performance pass) into a live cleanup backlog:

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
