---
description: "(no args) — visual board: typed lanes, done as a real list, deps + rec: legible; what burn-down would propose next"
---

Run `"${CLAUDE_PLUGIN_ROOT}/bin/board.sh"` and relay its output **verbatim** — this command is a
render, not a judgment call, and the script already does the formatting.

**What this is, and isn't.** `tq report`/`delta` are the machine-facing, injected-every-turn views
and stay deliberately terse (R69) — DONE collapses to a count, subjects truncate at 72 chars. Board
is the opposite: explicitly invoked, never injected, so it costs nothing unless run, and can afford
to spend on legibility — DONE rendered as an actual checked-off list, full untruncated subjects, and
a per-task `⧗ waiting on #N` note instead of one global `→ next:` pointer. It groups into the SAME
typed lanes the queue already has (▸ in progress · ◻ open, pre-cleared · ❓ your decision · ⏳
owner-only · ⛔ ruled out · ✔ done) — no new taxonomy, no invented score.

**The "beyond the queue" section is read-only.** It's `candidates.sh`'s existing provenance ranking
(R82: parked-with-`rec:` › ROADMAP › TODO › untested flow page › repeatedly-failing component ›
last-resort invention) — the same ladder burn-down uses to decide what it may build when idle. Shown
here purely so the owner can see and correct what the plugin considers highest-signal; it does
**not** change what autopilot actually drains next, which stays queue order + `after #N`.

If the owner asks to act on something shown here — answer a `❓`, unblock a `⏳`, pull a "beyond the
queue" item in — that's an ordinary `tq`/`/companion:review` operation, not something this command
does itself.
