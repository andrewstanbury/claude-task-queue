---
description: "(no args) — build from recorded signals while the 7d window forecasts underspend; each result lands flagged-off on its own branch"
---

Fill genuinely idle capacity with work you already asked for, without merging anything or waking
you up. **Only runs when the gate says so, and the gate says no far more often than yes.**

**This is the one mode that authors its own work**, so read the refusals as the feature. If you are
reading this because you *want* something built, stop and queue it with `tq` instead — real queued
work always outranks generated work and will make this mode refuse to run at all.

1. **Ask permission from the forecaster, every single iteration.**
   Run `"$CLAUDE_PLUGIN_ROOT/bin/burn-down.sh" should-burn`. Non-zero → **stop immediately** and
   say which condition held you back (it prints the reason on stderr). Do not retry, do not
   reinterpret, do not "just do one small thing anyway". The conditions are: mode armed · a fresh
   rate-limit snapshot · 5h headroom to actually work · the 7d window forecast to end **under**
   target · **zero** queued tasks · fewer than 3 unreviewed `burndown/*` branches.
2. **Take ONE candidate, the highest-ranked.**
   Run `"$CLAUDE_PLUGIN_ROOT/bin/candidates.sh"` and take the **first line only**.
   - Rank 1–4 are signals *the owner recorded* — a parked decision carrying `rec:`, a ROADMAP item,
     a TODO, a flow with no automated test. Build these.
   - **Rank 5 is `invent`**, meaning nothing recorded remains. Do **not** build it. Park it as a
     `❓` proposal with your recommendation and stop the loop. Inventing work to fill a quota is
     precisely the failure this whole mode is shaped to avoid.
   - **A candidate may not be buildable at all** — a rank-1 park is often a *decision* ("should we
     push?", "which backend?"), not a feature. No pattern can tell those apart reliably, so this is
     your judgment: if building it would mean **making the owner's decision for them**, skip it,
     leave the park exactly as it is, and take the next candidate. Never convert a question into an
     implementation just because it ranked first.
3. **Open the container before writing anything.**
   `"$CLAUDE_PLUGIN_ROOT/bin/burndown-branch.sh" start "<the candidate line verbatim>"` — it
   creates `burndown/<slug>` off the default branch, refuses if the tree is dirty, and writes a
   manifest stating the reason, the flag name, how to try it and how to delete it. It prints the
   slug. If it refuses, respect the refusal.
4. **Build it behind the flag named in the manifest, defaulting OFF.**
   Implement the flag in **this project's own idiom** (env var, config key, build tag — whatever it
   already uses; R9 — never impose one). With the flag off, behaviour must be **byte-identical** to
   the default branch: that is what makes the branch safe to ignore. Keep the change as small as
   the candidate honestly requires; this is filling spare capacity, not a licence to redesign.
5. **Verify by exercising, then commit to the branch.**
   Run the project's own gate. Green → commit on `burndown/<slug>`. **Never** merge, **never**
   push, **never** touch the default branch. Red and you cannot fix it quickly → commit what you
   have with the failure stated plainly in the message, and move on; a branch that does not work is
   still honest, a branch that *claims* to work and does not is not.
6. **Record it and loop.** `tq add` a `❓ [parked] burndown: <slug> — <what it does>; flag: <NAME>;
   rec: <keep or discard, and why>` so it surfaces in `/companion:review`. Return to step 1.

**When the loop ends**, say in one line: what was built, which branches await review, and that the
expected outcome for each is *discard unless it earns its place*. Then stop — do not start
reviewing your own output.

**Never**: merge to the default branch · push · enable a flag by default · build a rank-5 invented
candidate · run when `should-burn` refuses · take a second candidate before finishing the first.
