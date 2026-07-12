# Configuration reference

The companion is deliberately near-configuration-free — almost all behavior is the steering
document (`plugins/companion/STEERING.md`), which you change by editing prose, not env vars.
The only knobs are for the enforced core. Set them as environment variables (shell profile or
Claude Code settings env). Defaults are safe.

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_COMPANION_SECSCAN` | `1` | The pre-write secret gate. `0` disables the block (a write with a credential-looking literal is allowed through). |
| `CLAUDE_COMPANION_TOUCH` | `1` | The clean-as-you-touch pass — runs the project's own **formatter** on the edited file (format-only; blast-radius + size are steering now, R28). `0` disables it. |
| `CLAUDE_COMPANION_TASKS_DIR` | `~/.claude/companion/tasks` | The companion's **own** task store (deliberately not `~/.claude/tasks` — the companion doesn't use native tasks). What `tq` writes and `session-start` / the status line read. |
| `CLAUDE_COMPANION_SESSION_ID` | *(from `CLAUDE_CODE_SESSION_ID`)* | Overrides the session id `tq` writes under. For tests. |
| `CLAUDE_COMPANION_STATE_DIR` | `~/.claude/companion` | Root for the companion's non-task state — currently the per-repo autopilot flags (`autopilot/`). |
| `CLAUDE_COMPANION_AUTOPILOT_CONTINUE` | `1` | The Stop-hook auto-continue while autopilot is on. `0` stops it auto-draining (autopilot then relies on the steering doc alone). |
| `CLAUDE_COMPANION_AUTOPILOT_MAX` | `8` | No-progress cap: consecutive end-of-turn stops with no task completed before autopilot yields (so a stuck model can't spin forever). |

## State

State is small and safe to delete: the companion's own task store
(`~/.claude/companion/tasks/<session-id>/` — one JSON file per task plus a `.root` file stamping
that session's repo, so resume scopes to a repo without reading any native session transcript),
and the per-repo **autopilot flags** (`~/.claude/companion/autopilot/`, one empty file per repo
where autopilot is on — R26 made it persist across restarts). Nothing is secret; removing a
session's dir clears that session's queue, and removing an autopilot flag just turns it off.

There are **no throttle files or per-edit markers** — the R28 realignment deleted the gate state
(design/review/intent markers) along with the hooks that wrote it. What remains is only what the
enforced core genuinely needs.
