---
description: "(no args) — wire the status line into settings.json (once per machine), then elicit the quality attributes that must not be found late"
---

<!-- cli-only: wires the companion status line into Claude Code's own settings.json. There is no
     status line, and no settings.json, in another MCP client — this command has nothing portable to
     stand on by construction, which is different from a capability that merely has not been moved
     yet. See dev/command-lint.sh's portability floor. -->

Wire the companion's status line into the user's Claude Code settings so it renders in the
CLI. The status line shows, grouped: ⠋ beacon · │ 🛡️ secret gate · ✈️ autopilot (⚡ decisive, 🧹 sweep) · 📦 ship-mode │
(active features) · │ 📋 open · ❓ parked · ⏳ blocked │ (the queue) · │ ↻2h ▰▰▱▱▱ 23% ↻6d ▰▰▰▱▱ 41%▴ │
(**account** rate-limit usage) · model · ⇡ input ⇣ output
tokens · project · branch (+ *changes · ↑ahead ↓behind).

**The usage bars (R76)** read `.rate_limits` out of the payload Claude Code already pipes to the
status line — **no API call, no network, no token cost**. Green under 60%, yellow 60–84%, red at
85% and above. The label is a `↻` countdown to that window's reset (the `5h`/`7d` name shows instead when there is no usable timestamp), and the 7d percent carries `▴`/`▾` for whether you are on pace to spend the window before it resets. They are **rolling windows, not a
billing cycle** (the plans meter on 5-hour and 7-day windows, so there is no monthly percentage to
show), and they cover the whole **account**, not this repo. The field only exists for Claude.ai
Pro/Max and only after the session's first API response — each window independently — so on an API
key, or on the very first render, that section simply isn't there. Say so if the owner asks why
they can't see it; it isn't a wiring fault.

Do this:

1. Resolve the absolute path to the status line script: `${CLAUDE_PLUGIN_ROOT}/bin/statusline.sh`
   (expand `${CLAUDE_PLUGIN_ROOT}` to its real value — the status line runs outside the hook
   environment, so the stored command must be an absolute path, not the variable).
2. Read the user's `~/.claude/settings.json` (create `{}` if absent).
3. Set `.statusLine` to `{ "type": "command", "command": "bash <ABSOLUTE_PATH>", "refreshInterval": 10 }`.
   If a `statusLine` already exists, show the current value and confirm before replacing it.
4. **REPAIR a wrong `refreshInterval`, don't leave it (R81).** If `statusLine` already points at
   this script but carries a different interval — including the old `3` — rewrite it to `10` and
   say so in one line. A stale low interval is the single largest idle cost the companion imposes
   (measured: ~212 CPU-seconds/hour/window at 3s, fork/exec-dominated), and it is invisible: the
   line renders perfectly either way, so nothing else would ever surface it.
5. Write it back (valid JSON, preserving other keys). Confirm in one line that it's wired and
   will appear on the next render.

6. **ELICIT THE QUALITY BAR (R118) — the half nothing ever asked for.** This project already had
   the strong machinery: `docs/flows/_quality-bar.md` is where quality attributes live,
   `requirements.yaml` pairs every behaviour with the tests that verify it, and `dev/trace.sh` gates
   both directions. What nothing did was **ask** — so a repo runs for months with an empty bar and
   nothing notices until a publish is what surfaces it. That is the "find out way too late,
   redesign the whole thing" case this step exists to prevent.

   Run **`bin/quality-bar.sh check`** first. **Silent → the bar is already paired; say so in one
   line and stop.** Do not re-interview someone who has answered.

   Otherwise ask — **recommendation-first, batched, `AskUserQuestion`** — for *the attributes that
   would force a redesign if discovered late*. Seed the menu from what the repo evidently is
   (R9: recognize it, don't consult an allowlist) — a web UI raises **accessibility**, anything
   holding user records raises **security** and **data handling**, anything with a hot path raises
   **performance**. Offer 3-4 concrete candidates plus "none of these". **Ask for at most 4-5
   total**: a long bar is filler, and filler is what makes the check ignorable.

   **For each one accepted, ask the second question — and it is the point of the whole step:
   HOW will this be checked?** An attribute with no validation is a standard nobody can fail.
   Record each as one line under `floor`:

   > `- <ID> <the standard> → validated by: <the gate, test, or review question>`

   **`reviewed at ship — "<the question>"` is a first-class answer, not a placeholder.** Most
   quality attributes are judgment — "native-first", "prevention over detection" — and a tool that
   demanded a mechanical gate for each would manufacture fake ones, which read as coverage and are
   worse than an honest human check. Say this when you ask, so the owner does not feel pushed into
   inventing a script.

   **Existing project?** Say plainly that they are answering for choices the codebase has already
   made implicitly, and that the useful output is the *gap* — the attribute that matters and has no
   check today. Offer to record it with `→ validated by: NOTHING YET — <what would be needed>`,
   which is honest and is exactly what a pre-publish review should surface.

   From then on the ship boundary reports any attribute naming no validation (via
   `contract-drift.sh`, advisory). A project that wants the ship to actually stop runs
   `quality-bar.sh check --strict`.

**Once *per machine*, not once ever.** `settings.json` is machine-local and the stored path is
absolute, so a repo carried to another machine (`/companion:resume`) has **no** status line until
`/companion:setup` runs there too — nothing else surfaces its absence. If the plugin cache path
moves on a version bump, the stored path rots silently (the line just stops rendering); re-run this.

`refreshInterval: 10` (seconds, R32·5 → widened by R81) — the beacon animates only when there's
work in motion, so it needs *a* timer, but a fast one is the companion's largest idle cost. Each
wake is ~13 process spawns and a `git status`; **measured at 3s that is ~212 CPU-seconds per hour,
per open window**, and it is *sys*-dominated — fork/exec churn, not computation. On a laptop or a
handheld that is the difference between the SoC reaching deep idle and never quite getting there.
At 10s the spinner still visibly steps and the wake rate drops ~70%. The git segment is
additionally cached for ~10s (`CLAUDE_COMPANION_SL_CACHE_TTL`, `0` disables), so branch and the
dirty count may lag by up to that long — the accepted trade. (A no-color terminal shows a static ●
and doesn't need the timer at all; dropping `refreshInterval` entirely is the zero-idle option.)
