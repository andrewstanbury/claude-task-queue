# Configuration reference

The companion is deliberately near-configuration-free — almost all behavior is the steering
document (`plugins/companion/STEERING.md`), which you change by editing prose, not env vars.
The only knobs are for the enforced core. Set them as environment variables (shell profile or
Claude Code settings env). Defaults are safe.

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_COMPANION_SECSCAN` | `1` | The pre-write secret gate. `0` disables the block (a write with a credential-looking literal is allowed through). |
| `CLAUDE_COMPANION_TOUCH` | `1` | The clean-as-you-touch pass (format the edited file + blast-radius + size). `0` disables it. |
| `CLAUDE_COMPANION_SIZE_BUDGET` | `300` | Lines over which the clean-as-you-touch pass flags a file as oversized (also the default `/companion:audit` threshold). |
| `CLAUDE_COMPANION_TASKS_DIR` | `~/.claude/companion/tasks` | The companion's **own** task store (deliberately not `~/.claude/tasks` — the companion doesn't use native tasks). What `tq` writes and `session-start` / the status line read. |
| `CLAUDE_COMPANION_SESSION_ID` | *(from `CLAUDE_CODE_SESSION_ID`)* | Overrides the session id `tq` writes under. For tests. |

## State

The only state is the companion's own task store (`~/.claude/companion/tasks/<session-id>/`):
one JSON file per task plus a `.root` file stamping that session's repo (so resume scopes to a
repo without reading any native session transcript). It's not secret and safe to delete;
removing a session's dir just clears that session's queue.

There are **no throttle files, mode flags, or per-repo markers** — the old system's state
machinery went away with the hooks that needed it. Autopilot is now just how the model behaves
per the steering doc when you tell it you're stepping away; nothing is written to track it.
