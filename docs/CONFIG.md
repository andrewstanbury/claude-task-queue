# Configuration reference

The companion is deliberately near-configuration-free — almost all behavior is the steering
document (`plugins/companion/STEERING.md`), which you change by editing prose, not env vars.
**R100:** there is no more enforced core to have knobs for — `CLAUDE_COMPANION_AUTOPILOT_CONTINUE`
and `CLAUDE_COMPANION_AUTOPILOT_MAX` (the old Stop-hook's auto-continue toggle and no-progress cap)
are gone along with `stop-autopilot.sh`; nothing reads them anymore. Set what's left as
environment variables (shell profile or Claude Code settings env). Defaults are safe.

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_COMPANION_SECSCAN` | `1` | The advisory secret scanner (`check-secrets.sh` / MCP `check_for_secrets`). `0` disables it — it returns clean regardless of content. Not enforced either way (R100/Pass 3): this only changes what the scanner reports, never what gets written. |
| `CLAUDE_COMPANION_TASKS_DIR` | `~/.claude/companion/tasks` (legacy) or `<repo>/.companion/tasks` (flat, repo-scoped — the common case since R96) | The companion's **own** task store (deliberately not `~/.claude/tasks` — the companion doesn't use native tasks). What `tq` writes and `resume.sh` / the status line read. |
| `CLAUDE_COMPANION_SESSION_ID` | *(from `CLAUDE_CODE_SESSION_ID`)* | Overrides the session id `tq` writes under. For tests, and for the MCP server (forwards an inherited id; synthesizes one only as a last resort). |
| `CLAUDE_COMPANION_STATE_DIR` | `~/.claude/companion` | Root for the companion's non-task state — the per-repo autopilot/ship/decisive/sweep/burndown flags. |
| `CLAUDE_COMPANION_CHANGE_WINDOW_DAYS` | `14` | How far back `resume.sh` looks in `docs/CHANGES-OUTSIDE-GIT.md` for recent out-of-band changes (R93). |
| `CLAUDE_PLUGIN_ROOT` | *(set by Claude Code)* | Resolves `bin/tq` and `bin/check-secrets.sh` from the MCP server (`mcp-server/index.js`); falls back to a path relative to the server file when unset (standalone/manual runs). |
| `CLAUDE_PROJECT_DIR` | *(set by Claude Code)* | The MCP server's cwd for `tq`/`check-secrets.sh` subprocess calls, so it doesn't depend on its own `process.cwd()`. Falls back to `process.cwd()` when unset. |

## State

State is small and safe to delete: the companion's own task store (flat at
`<repo>/.companion/tasks/` for the common case, or `~/.claude/companion/tasks/<session-id>/` for
the legacy/global-override path — one JSON file per task plus a `.root`/`.repo` stamp identifying
the owning repo, so resume scopes to a repo without reading any native session transcript), and
the per-repo **mode flags** (`~/.claude/companion/<mode>/` or committed under `.companion/modes/`
depending on R96's repo-state migration — one empty file per repo where a mode is on). Nothing is
secret; removing a session's dir clears that session's queue, and removing a mode flag just turns
it off.

There are **no throttle files or per-edit markers** — the R28 realignment deleted the gate state
(design/review/intent markers) along with the hooks that wrote it, and R100 deleted the rest
(the autopilot no-progress/run-bound counter file, `~/.claude/companion/autopilot/continue-*`,
along with `stop-autopilot.sh`). What remains is only the task store and the mode flags.
