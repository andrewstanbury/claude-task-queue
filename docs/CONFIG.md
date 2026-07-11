# Configuration reference

The companion is deliberately near-configuration-free — almost all behavior is the steering
document (`plugins/companion/STEERING.md`), which you change by editing prose, not env vars.
The only knobs are for the enforced core. Set them as environment variables (shell profile or
Claude Code settings env). Defaults are safe.

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_COMPANION_SECSCAN` | `1` | The pre-write secret gate. `0` disables the block (a write with a credential-looking literal is allowed through). |
| `CLAUDE_COMPANION_TASKS_DIR` | `~/.claude/tasks` | Where the native task JSON store lives — what `tq` writes and `session-start` reads for cross-session resume. |
| `CLAUDE_COMPANION_PROJECTS_DIR` | `~/.claude/projects` | Claude Code's per-session store, read to scope resumed tasks to *this* repo (no cross-project bleed). |
| `CLAUDE_COMPANION_SESSION_ID` | *(from `CLAUDE_CODE_SESSION_ID`)* | Overrides the session id `tq` writes under. For tests. |

## State

The only state is the native task store (`~/.claude/tasks/<session-id>/*.json`) — the same
files Claude Code's native task list uses, written by `tq` when the native tools are gated
off. It's not secret and safe to delete; removing it just clears that session's queue.

There are **no throttle files, mode flags, or per-repo markers** — the old system's state
machinery (autopilot flags, alignment throttles, verify fingerprints) went away with the
hooks that needed it. Autopilot is now just how the model behaves per the steering doc when
you tell it you're stepping away; nothing is written to disk to track it.
