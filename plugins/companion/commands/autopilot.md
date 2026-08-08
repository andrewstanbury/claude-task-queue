---
description: "on|off|status (empty=status) · ship on|off · decisive on|off · sweep on|off — drain the queue autonomously, without stopping"
argument-hint: "[on|off|status | ship|decisive|sweep on|off|status]"
---

Toggle autopilot for this repo by calling the **`autopilot_toggle`** tool on the `companion-tq`
MCP server (the portable surface, R100/Pass 5b — any MCP-capable client reaches the same flag this
way, not just Claude Code), passing `$ARGUMENTS` through: `mode` is `autopilot` (default) or
`ship`/`decisive`/`sweep`; `action` is `on`/`off`/`status`/`pause`/`resume` (pause/resume apply to
`mode: autopilot` only). **empty → `status`**, the tool's own default — never assume `on`.

**R100/Pass 4: none of this is enforced anymore.** `ask-guard.sh` and `stop-autopilot.sh` are
retired — nothing denies `AskUserQuestion`, nothing forces the session to continue instead of
stopping, and there is no more no-progress/run-bound cap. Everything below is what STEERING asks
you to do while the flag is on, not a guarantee. Watch your own progress; if you're spinning
without finishing anything, say so and stop rather than assuming a cap has your back.

- **on** — **keep going without stopping** (R36) — *not* "the owner is away"; they may be present,
  queuing up more tasks and keeping it on deliberately. Run autonomous: keep draining the `tq`
  queue, don't stop to ask, do all reversible work, and PARK what needs the owner's judgment
  (`❓ [parked]` decision / `⏳ [blocked]` owner-action; a visual/design/direction choice is parked
  too, not decided — R33) — **park it yourself**, `tq add`, right then; nothing auto-parks anymore.
  The flag persists across restarts.
- **off** — normal review loop resumes. **Immediately run the parked-pile review** (R38): walk the
  `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first, and record each pick back
  to `tq` **before** any new work — follow `/companion:review` (defer/bail allowed; no-op if the pile
  is empty). Do this whether the owner turned autopilot off by this command or in plain conversation.
- **ship on|off** — toggle **ship-mode** (R34). While ship-mode *and* autopilot are on, call the
  **`ship_checkpoint`** MCP tool yourself at natural stopping points (was automatic) to commit the turn's
  work to an `autopilot/*` branch (reversible; **never the default branch, never a push**), so
  completed work is captured for the owner to review + `/companion:ship-it` on return. Shown as 📦.
- **decisive on|off** — toggle **decisive mode** (R59). While decisive *and* autopilot are on,
  instead of parking *every* decision, decide it yourself: auto-pick your own recommended option for
  **reversible** choices (design / wording / direction included — overrides R33), record each pick
  as a `tq note`, and keep going; still park (`❓`) / block (`⏳`) only the irreversible,
  externally-binding, or data-destructive. The audit trail is the safety — `/companion:review` reads
  the picks back. Shown as ✈️⚡ on the status line.

- **sweep on|off** — toggle **sweep mode** (R77). Don't treat a `❓`-only queue as finished — work
  the parks that were **marked reversible when they were set aside** —
  `❓ [parked] rev: <choice> … ; rec: <pick>` — applying each recorded `rec:`. **Eligibility is that
  marker, not a judgement made now:** no `rev:` ⇒ treated as irreversible ⇒ never swept (the safe
  default for every park written before this existed), and the same for `⏳` (blocked *on the owner*
  acting in the world — no mode can clear it) and `decompose:` parks (R65 — questions, not options).
  `tq stopfields <sweep-bool>` carries this selection logic if you want to check it mechanically.
  It pairs with **plain autopilot**, which is what parks taste calls (R33); **decisive** parks only
  the irreversible and must never mark those `rev:`. Scope is this session's parks. Every pick is a
  `tq note`, so `/companion:review` still walks them. Shown as 🧹. **Say the trade-off plainly when
  turning it on:** it reverses R33 for marked parks — a reversible taste call is normally the
  owner's even when trivially undoable — and by the time autopilot goes off, the pile the R38
  review exists to walk is empty by construction.

**The queue running dry doesn't hand off to burn-down automatically anymore either (R82).** Call
**`burn_down`** (`action: "should_burn"`) yourself; if it says burn, take rank-1 from **`candidates`**
on its own branch via **`burndown_branch`** (`action: "start"`).

Relay the tool's one-line confirmation to the user.
