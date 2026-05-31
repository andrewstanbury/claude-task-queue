# hud

A **consolidated status line** for the companion plugins — one glanceable line in
the Claude Code CLI showing what's happening, rendered **read-only** from state
the other plugins already maintain plus the `statusLine` payload. No hooks, no
project scanning, and **zero model-token cost** (it's terminal UI, not context).

```
⠇  Tasks: 3 ▶ Wire auth middleware  ⏸ paused  QA ✓  ✎ login.go  Tokens: ↑ 12.3k ↓ 4.6k  ⎇ main  Model: Opus 4.8
```

## Slots (left → right, each collapses when absent)

1. **Beacon** — an animated glyph (advances ~1×/sec with `refreshInterval: 1`); yellow when the queue is paused.
2. **Tasks** — open count + the in-progress task (from task-queue's native store).
3. **⏸ paused** — when auto-advance is paused for this repo.
4. **QA** — `✓` if the project documents quality attributes (charter's check), else `·`.
5. **Last tidy** — the file tidy last touched.
6. **Tokens** — `↑` up / `↓` down.
7. **Branch** — current git branch.
8. **Model** — display name.

> **On "tokens up/down":** these come from the payload's `total_input_tokens` /
> `total_output_tokens`, which on current Claude Code reflect **what's in the
> context window** (most recent exchange), not cumulative session totals. Labeled
> up/down for familiarity; read them as current-context in/out.

## Wiring (one-time)

The status line is owned by **your** `statusLine` config, so you opt in once:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/plugins/.../hud/bin/hud-status.sh",
    "refreshInterval": 1
  }
}
```

`refreshInterval: 1` keeps the beacon animating. **Already have a status line?**
Yours wins — compose by having your command call `hud-status.sh` and appending
its output. (The maintainer can wire this for you via the config skill.)

## Reads, never writes

hud reads **existing on-disk state** — the native task store, task-queue's pause
flags, charter's quality-attributes doc, tidy's activity log — and the stdin
payload. It does **not** depend on the other plugins' *code* (install boundary),
so each slot simply collapses if a plugin isn't installed. It honours `NO_COLOR`
and `TERM=dumb`. What it depends on is in [CONTRACT.md](./CONTRACT.md).

## Configuration

| Var | Effect |
|---|---|
| `CLAUDE_HUD_TASKS_DIR` | Native task store (default `~/.claude/tasks`). |
| `CLAUDE_HUD_PAUSE_DIR` | task-queue pause flags (default `~/.claude/state/task-queue/paused`). |
| `CLAUDE_HUD_TIDY_LOG` | tidy activity log (default `~/.claude/state/tidy/activity.log`). |
| `NO_COLOR` | Disable ANSI color. |

## Requirements

- Bash 4+ and `jq`; `git` optional (for the branch slot).

## Tests

```bash
bats tests/
```

## License

MIT.
