---
description: Resume an earlier session — re-surface this repo's carried-over tasks (preserving their ❓/⏳/📋 class) and reinstate them, so you pick up where you left off before starting new work
---

Run a **session resume**: re-surface this repo's tasks carried over from an earlier session and
reinstate them, preserving each item's classification. This is the on-demand twin of the SessionStart
hook's automatic re-surface — run it any time you want to pull earlier-session work back mid-session.
It is **session-pickup only**: to then *decide* the parked/blocked pile it re-surfaces, run
`/companion:review` (the parked-pile review, R38) — that split keeps pickup and triage as two clear
moves (R39, re-split 2026-07-19).

It's judgment + workflow, not enforcement — it proposes, you choose, it records (R28). It's
owner-present by nature (the review it hands off to asks questions), so it's meant for when autopilot
is **off** — and it turns autopilot off itself, first, so a re-surfaced decision comes back to *you*,
not to the next autopilot drain (R39).

0. **Clear the flag first (conversational path).** If you got here because the owner asked in plain
   language to turn autopilot off (not via `/companion:autopilot off`, which already does this), the
   `resume.sh` in step 1 clears the persisted flag for you — but if you need it clear *before* running
   anything else, run `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off`.

1. **Re-surface earlier-session tasks (session pickup, R39).** Run
   `"${CLAUDE_PLUGIN_ROOT}/bin/resume.sh"`: it turns **autopilot off first** — announced in one line
   when it was on (relay that notice; never a silent clobber of a persisted intent — re-arm is a
   manual `/companion:autopilot on`), quiet no-op when already off — and lists this repo's still-open
   tasks carried over from earlier sessions (the SessionStart hook does this automatically each new
   session; this is the on-demand twin). Reinstate the ones still relevant (skip anything already
   done or no longer wanted), **preserving each item's classification** — a decision comes back
   parked (`tq add "❓ [parked] <the choice + options + your recommendation>"`), an owner-only action
   blocked (`tq add "⏳ [blocked] <action>"`), a plain doable task open (`tq add "<subject>"`).
   **Never promote a parked decision into a plain open task** — that would let the next drain
   autopilot the answer instead of asking you (R39·D). Restore anything in progress with
   `tq doing <id>` and pick up from its breadcrumb. Clean no-op if nothing carried over.

2. **Hand off to the review.** Once the pile is reinstated, any **❓ parked** / **⏳ blocked** items
   among it are waiting on your input — run **`/companion:review`** to walk them one at a time,
   recommendation-first, before starting new work. (Plain `📋 open` tasks need doing, not deciding —
   just drain them in order.) If nothing carried over, there's nothing to review; go straight to work.
