---
description: Wire the companion status line into your settings.json (once per machine)
---

Wire the companion's status line into the user's Claude Code settings so it renders in the
CLI. The status line shows, grouped: ⠋ beacon · │ 🛡️ secret gate · ✈️ autopilot · 📦 ship-mode │
(active features) · │ 📋 open · ❓ parked · ⏳ blocked │ (the queue) · │ 5h▰▰▱▱▱23% 7d▰▰▰▱▱41% │
(**account** rate-limit usage) · model · ⇡ input ⇣ output
tokens · project · branch (+ *changes · ↑ahead ↓behind).

**The usage bars (R76)** read `.rate_limits` out of the payload Claude Code already pipes to the
status line — **no API call, no network, no token cost**. Green under 60%, yellow 60–84%, red at
85% and above, with a `↻` reset countdown once a window reaches 80%. They are **rolling windows, not a
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
3. Set `.statusLine` to `{ "type": "command", "command": "bash <ABSOLUTE_PATH>", "refreshInterval": 3 }`.
   If a `statusLine` already exists, show the current value and confirm before replacing it.
4. Write it back (valid JSON, preserving other keys). Confirm in one line that it's wired and
   will appear on the next render.

**Once *per machine*, not once ever.** `settings.json` is machine-local and the stored path is
absolute, so a repo carried to another machine (`/companion:resume`) has **no** status line until
`/companion:setup` runs there too — nothing else surfaces its absence. If the plugin cache path
moves on a version bump, the stored path rots silently (the line just stops rendering); re-run this.

`refreshInterval: 3` (seconds, R32) — the beacon animates only when there's work in motion, so it
needs *a* timer, but not a per-second one: at 3s it still advances (nobody reads a spinner at 1 Hz)
while cutting the idle cost — the jq + `git status` wake — ~3× versus 1s. (A no-color terminal shows
a static ● and doesn't need the timer at all.)
