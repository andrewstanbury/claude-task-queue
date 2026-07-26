---
description: "on|off|status (empty=status) · ship on|off · decisive on|off · sweep on|off — drain the queue autonomously, without stopping"
argument-hint: "[on|off|status | ship|decisive|sweep on|off|status]"
---

Toggle autopilot for this repo by running the toggle script, passing `$ARGUMENTS` through verbatim
(`on`, `off`, `status`, or `ship`/`decisive`/`sweep` + `on|off|status`; **empty → `status`**, the
script's own default — never assume `on`):

`"${CLAUDE_PLUGIN_ROOT}/bin/autopilot.sh" <on|off|status | ship|decisive|sweep on|off|status>`

- **on** — **keep going without stopping** (R36) — *not* "the owner is away"; they may be present,
  queuing up more tasks and keeping it on deliberately. Run autonomous: keep draining the `tq`
  queue, don't stop to ask, do all reversible work, and PARK what needs the owner's judgment
  (`❓ [parked]` decision / `⏳ [blocked]` owner-action; a visual/design/direction choice is parked
  too, not decided — R33). Enforced: the Stop hook auto-continues the queue and the ask-guard blocks
  AskUserQuestion (asking = stopping) while it's on. The flag persists across restarts.
- **off** — normal review loop resumes. **Immediately run the parked-pile review** (R38): walk the
  `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first, and record each pick back
  to `tq` **before** any new work — follow `/companion:review` (defer/bail allowed; no-op if the pile
  is empty). Do this whether the owner turned autopilot off by this command or in plain conversation.
- **ship on|off** — toggle **ship-mode** (R34). While ship-mode *and* autopilot are on, the Stop
  hook auto-commits each turn's work to an `autopilot/*` branch (reversible; **never the default
  branch, never a push**), so completed work is captured for the owner to review + `/companion:ship-it`
  on return. Shown as 📦 on the status line.
- **decisive on|off** — toggle **decisive mode** (R59). While decisive *and* autopilot are on,
  instead of parking *every* decision, autopilot auto-picks its own recommended option for
  **reversible** choices (design / wording / direction included — overrides R33), records each pick
  as a `tq note`, and keeps going; it still parks (`❓`) / blocks (`⏳`) only the irreversible,
  externally-binding, or data-destructive. The audit trail is the safety — `/companion:review` reads
  the picks back. Shown as ✈️⚡ on the status line.

- **sweep on|off** — toggle **sweep mode** (R77). The Stop hook stops treating a `❓`-only queue as
  finished, so autopilot works the parks that were **marked reversible when they were set aside** —
  `❓ [parked] rev: <choice> … ; rec: <pick>` — applying each recorded `rec:`. **Eligibility is that
  marker, not a judgement made now:** no `rev:` ⇒ treated as irreversible ⇒ never swept (the safe
  default for every park written before this existed), and the same for `⏳` (blocked *on the owner*
  acting in the world — no mode can clear it) and `decompose:` parks (R65 — questions, not options).
  It pairs with **plain autopilot**, which is what parks taste calls (R33); **decisive** parks only
  the irreversible and must never mark those `rev:`. Scope is this session's parks. The run is
  bounded by its own counter — the no-progress cap can't bound a sweep, since completing a swept
  park resets it. Every pick is a `tq note`, so `/companion:review` still walks them. Shown as 🧹.
  **Say the trade-off plainly when turning it on:** it reverses R33 for marked parks — a reversible
  taste call is normally the owner's even when trivially undoable — and by the time autopilot goes
  off, the pile the R38 review exists to walk is empty by construction.

Relay the script's one-line confirmation to the user.
