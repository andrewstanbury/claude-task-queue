---
description: Audit the whole project for cleanliness (size, debt, blast-radius, perf) via a sub-agent panel and queue the fixes
---

An on-demand, whole-project cleanliness audit — the deliberate complement to the per-edit
clean-as-you-touch hook. **Read-only analysis; queue the work, don't do it inline** (ratchet,
never sweep). Run it as a **sub-agent panel** (R30·d5) so each dimension is scanned in its own
context and only the findings come back — the main context stays clean. If sub-agents aren't
available, run the passes inline instead.

1. **Fan out — one lens per sub-agent.** Spawn a panel, each agent scanning the whole repo for
   one dimension (skip vendored/generated: `node_modules`, `dist`, `build`, `.git`, lockfiles).
   Each returns a structured list of findings — file, one-line problem, rough severity.
   - **Oversized files** — source files over the size budget (default 300 lines); worst first.
   - **Scar tissue (debt magnets)** — high git rework-ratio: `fix`/`revert`-flavored commits ÷
     total commits touching a file; flag ≥ ~0.34 with ≥ 2 reworks. Where debt concentrates.
   - **Blast-radius hotspots** — files with many dependents (widely referenced), where a change
     ripples far.
   - **Performance hot paths** *(judgment, no engine allowlist)* — recognise realtime/per-frame
     or hot-loop code generically and flag likely regressions; route anything you can't measure
     statically to a before/after profile rather than guessing.

2. **Synthesize.** Merge and dedupe the panel's findings into one ranked list. The **top
   priority is the overlap** — a file that's high fan-in *and* oversized *and* scar-tissue is
   where a cleanup pays off most. Drop anything that doesn't survive your own scrutiny (the panel
   can over-report; you're the filter). Each finding is licensed to be "actually fine" — don't
   manufacture work.

3. **Queue.** `tq add "<fix>" --done "<what 'clean' looks like>"`, smallest blast-radius first;
   park anything genuinely risky or ambiguous as `❓ [parked] <decision>`. Give the owner a
   one-line plain-language summary of what you queued. **Don't start the fixes unless they say
   go** — this is an audit, not a sweep.
