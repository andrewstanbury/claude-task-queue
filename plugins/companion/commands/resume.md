---
description: Re-surface and reinstate an earlier session's carried-over tasks, ❓/⏳/📋 class intact
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

0. **Autopilot** — step 1 clears it (early, before the handoff-checkout offer; `resume.sh` also
   clears it). Nothing to do up here.

**Carrying the queue between machines (R60/R72).** The task store is machine-local, so the queue
travels over git. **Sending side:** mid-flight work → `/companion:handoff` (one call — commits the
working tree + queue to a pushed branch, R72); finished work → `/companion:ship-it` (exports at
preflight). *(Manual fallback: `"${CLAUDE_PLUGIN_ROOT}/bin/tq" export` + commit `.companion/queue.json`
yourself.)* **Receiving side (this command):** step 1's `resume.sh` imports the carried
`.companion/queue.json`, re-stamping each task under *this* machine's path so it surfaces regardless
of clone location. Import is idempotent and dedups by subject, so a task already completed here is
never resurrected. (Linear handoff is the supported flow; two machines editing the same queue
concurrently is last-export-wins — status changes don't merge back.)

1. **Re-surface earlier-session tasks (session pickup, R39).** **First, check for a waiting handoff
   (R72)** — but **clear autopilot before you might ask**: if it's on, run
   `"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" off` (announced) so the checkout offer below isn't
   blocked by the ask-guard (`resume.sh` clears it too, but that runs *after* this offer). Then
   `git fetch` and look for a waiting handoff branch not checked out locally: a **`wip/*`** branch
   (a handoff made *on the default branch*) **or** the **named branch the sending machine relayed**
   (a handoff made on a feature branch commits in place, so it keeps its own name — `ship.sh handoff`
   printed that name; `git branch -r` ahead of the default is the general signal). If one exists,
   surface it and offer to check it out **before** importing — it carries the other machine's
   mid-flight tree + queue, and importing on the default branch instead would silently strand it.
   Then run
   `"${CLAUDE_PLUGIN_ROOT}/bin/resume.sh"`: it **imports any carried `.companion/queue.json` first**
   (R60 — relay the one-line import notice when it added tasks), then turns **autopilot off first** — announced in one line
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
