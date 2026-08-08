---
description: "[branch] — re-surface and reinstate an earlier session's tasks, ❓/⏳/📋 class intact; names a handoff branch, else auto-detects"
argument-hint: "[branch — the handoff branch; default auto-detect]"
---

Run a **session resume**: re-surface this repo's tasks carried over from an earlier session and
reinstate them, preserving each item's classification. **This is the ONLY way any of this reaches a
session now (R100/Pass 2)** — there is no more automatic SessionStart hook; run it yourself, any
time you want the STEERING core, LESSONS, recent out-of-band changes, or earlier-session work back
mid-session. It is **session-pickup only**: to then *decide* the parked/blocked pile it re-surfaces, run
`/companion:review` (the parked-pile review, R38) — that split keeps pickup and triage as two clear
moves (R39, re-split 2026-07-19).

It's judgment + workflow, not enforcement — it proposes, you choose, it records (R28). It's
owner-present by nature (the review it hands off to asks questions), so it's meant for when autopilot
is **off** — and it turns autopilot off itself, first, so a re-surfaced decision comes back to *you*,
not to the next autopilot drain (R39).

0. **Autopilot** — step 1 clears it (early, before the handoff-checkout offer; `resume.sh` also
   clears it). Nothing to do up here.

**Carrying the queue between machines (R60/R72).** The task store is machine-local, so the queue
travels over git — the queue lives in `.companion/tasks` inside the repo, so **any commit carries
it and there is nothing to export** (R96). **Sending side:** mid-flight work → `/companion:handoff`
(one call — commits the working tree, queue included, to a pushed branch, R72); finished work →
`/companion:ship-it`. **Receiving side (this command):** clone or pull, then `resume.sh` re-surfaces
this repo's open tasks with their classes and breadcrumbs intact, whatever the clone path.
(Linear handoff is the supported flow; two machines editing the same queue concurrently is a git
merge like any other file.)

1. **Re-surface earlier-session tasks (session pickup, R39).** **First, check for a waiting handoff
   (R72)** — but **clear autopilot before you might ask**: if it's on, call **`autopilot_toggle`**
   (`action: "off"`) (announced) so the checkout offer below comes
   before any question (the `resume` tool clears it too, but that runs *after* this offer). Then
   `git fetch` and find the waiting handoff branch.

   **`$ARGUMENTS` names it, if you know it** (the sending machine's `ship.sh handoff` printed the
   branch): take that branch as authoritative, skip the detection below, and check it out — still
   *offering* first if the local tree is dirty (a checkout would clobber uncommitted work), straight
   through if it's clean. If the named branch doesn't exist on the remote, **say so, skip the
   checkout, and carry on with the local session pickup** — never fall back to guessing a *different*
   branch (that's how you import the wrong queue), and never abort the whole command: the pickup
   below is branch-independent and is the main job. Name the likely cause in one line (typo, or the
   sending machine hasn't pushed yet) so the owner can re-run with the right branch.

   **With no argument, auto-detect** a waiting handoff branch not checked out locally: a **`wip/*`**
   branch (a handoff made *on the default branch*) **or** a **feature branch ahead of the default**
   (a handoff made on a feature branch commits in place, so it keeps its own name; `git branch -r`
   ahead of the default is the general signal — a heuristic, so **pass the branch explicitly when
   you know it**). If one exists,
   surface it and offer to check it out **before** resuming — it carries the other machine's
   mid-flight tree, and resuming on the default branch instead would silently strand it.
   Then call the
   **`resume`** MCP tool (`companion-tq` server, R100/Pass 5b): it turns **autopilot off first** — announced in one line
   when it was on (relay that notice; never a silent clobber of a persisted intent — re-arm is a
   manual `/companion:autopilot on`), quiet no-op when already off — then prints the STEERING core,
   this repo's `LESSONS.md`, a version-lag warning if the installed plugin is behind, recent
   out-of-band changes, recorded rework, and this repo's still-open tasks carried over from earlier
   sessions — all of it, every time, since nothing injects any of it automatically anymore
   (R100/Pass 2). Reinstate the ones still relevant (skip anything already
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
