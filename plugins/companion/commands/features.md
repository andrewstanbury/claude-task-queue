---
description: View or toggle companion's enforced-core capabilities per repo (secret gate, steering, autopilot, ship)
---

Run the feature surface, passing whatever argument the user gave (nothing / a name / `<name> on|off`):

`"${CLAUDE_PLUGIN_ROOT}/bin/features.sh" [<secret|steering|autopilot|ship> [on|off]]`

- **no argument** — list every capability's current state for this repo and relay the table.
- **secret** — the enforced credential gate (blocks a write that would commit a real key). Turning it
  **off** is guarded with a warning: a leaked key is irreversible, so this is the one flag to leave on
  absent a specific reason. Per-repo; the global `CLAUDE_COMPANION_SECSCAN=0` env var still overrides
  everywhere (CI escape hatch) and is shown as such.
- **steering** — inject the working agreement (`STEERING.md`) at session start. Off = this repo opts
  out of the ~2.4k-token injection (resume + LESSONS still fire). The one steering knob is inject
  on/off — individual clauses are **not** flag-per-clause (steering is ignorable-by-nature already, R28).
- **autopilot / ship** — reflected here for a single view, but they keep their own persisted flags;
  this **delegates** to `/companion:autopilot` rather than holding a second copy of that state.

Relay the script's output (the table, or the one-line `name → on|off` confirmation) to the user. If the
user disabled the secret gate, surface the warning too — don't swallow it.
