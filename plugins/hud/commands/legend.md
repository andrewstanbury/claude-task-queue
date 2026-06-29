---
description: Explain what each hud status-line symbol means (and which safety checks are off)
allowed-tools: Bash
---

! "${CLAUDE_PLUGIN_ROOT}/bin/hud-status.sh" --legend

The key above decodes every symbol in the hud status line. If a `🛡✗N` marker is
showing, the "Currently disabled" line names which safety checks are switched off —
those gates won't fire until their `CLAUDE_*` env var is set back to `1` (or removed).
