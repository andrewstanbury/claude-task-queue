# claude-task-queue

Durable, project-scoped task queue for [Claude Code](https://docs.claude.com/en/docs/claude-code), with prompt auto-decomposition (Haiku triage), pause-resumable autopilot, and a status-bar reader.

**Why:** Claude Code's `TaskCreate` / `TaskList` tools are session-scoped and the orchestration ("decompose, order, pause, autopilot, fold new requests in") has to be re-stated to the model in every prompt. This plugin makes that orchestration:

- **Durable** — queue lives in `~/.claude/state/task-queue/<project>.jsonl`, survives `/clear` and machine restarts.
- **Project-scoped** — each cwd hashes to its own queue, so two repos don't mix.
- **Auto-decomposed** — a Haiku triage call breaks each non-trivial prompt into ordered tasks with size estimates, blockers, and parallelism hints.
- **Pause-resumable** — pause / resume / autopilot are state files the model + CLI both read.
- **Status-bar friendly** — `bin/tq-status.sh` emits a one-liner ready for [claude-statusbar](https://github.com/andrewstanbury/claude-statusbar) or your terminal prompt.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/andrewstanbury/claude-task-queue/main/install.sh | bash
```

Or clone + run locally:

```bash
git clone https://github.com/andrewstanbury/claude-task-queue.git
cd claude-task-queue
./install.sh
```

This copies the plugin to `~/.claude/plugins/task-queue/`, merges hook entries (`UserPromptSubmit`, `PreToolUse`) into `~/.claude/settings.json` keyed by `"id": "claude-task-queue"` so re-installs upsert cleanly, and creates the state directory.

Add the CLI to your PATH:

```bash
ln -sf "$HOME/.claude/plugins/task-queue/bin/tq" /usr/local/bin/tq
```

Uninstall (keeps your queues by default):

```bash
~/.claude/plugins/task-queue/uninstall.sh           # keep state
~/.claude/plugins/task-queue/uninstall.sh --purge-state
```

## Requirements

- Bash 4+
- `jq`
- `sha1sum` (coreutils — pre-installed on Linux; `brew install coreutils` on macOS)
- `claude` CLI on `PATH` (Haiku triage shells out via `claude -p --model haiku-4-5`)

## CLI

```
tq list                   # the queue as jsonl
tq get <id>               # one task as JSON
tq status                 # one-line status
tq pause                  # pause autopilot for this project
tq resume                 # un-pause
tq autopilot              # enter autopilot (writes ok, destructive still pauses)
tq one-at-a-time          # exit autopilot
tq start <id>             # mark in_progress
tq done <id>              # mark completed
tq cancel <id>            # mark cancelled
tq add <subject> [est] [tokenEst]   # append a manual task
tq clear                  # delete the queue + pause + autopilot files (confirms)
tq path                   # print the queue file path
```

## Status line

```bash
~/.claude/plugins/task-queue/bin/tq-status.sh
# → ▶ 4/11 · auto · 5: Wire engine (M, ~4k tok)
```

Drop into `claude-statusbar`'s `status.sh` to surface progress next to git branch + token use.

## Behavior

### Decomposition (UserPromptSubmit)

On every prompt, `tq-decompose.sh` runs:

1. **Skip** if disabled, blank, `/slash`, or `!bang`.
2. **Classify** trivial vs non-trivial (length, action verbs, multi-and).
3. **Non-trivial** → invoke `claude -p --model haiku-4-5` with the prompt + a small project profile + the existing queue. Haiku returns an ordered JSON array; the plugin appends each task to the queue.
4. **Inject** a small system-reminder with the queue's current counts, next task, and pause/autopilot state.

If Haiku is unreachable (timeout, no `claude` on PATH, malformed response), the plugin silently falls back to no-write — your conversation isn't blocked.

### Pre-tool gate (PreToolUse)

`tq-pretool.sh` classifies each tool call as low-risk / write / destructive:

| Class | Examples | Behavior |
|---|---|---|
| Low-risk | `Read`, `TaskList`, `Bash` matching `ls / cat / git status / git diff / grep / find` | Silent pass |
| Write | `Edit`, `Write`, other `Bash` | Allow when autopilot or no pause; block when paused |
| Destructive | `rm -rf`, `git push --force`, `git reset --hard`, `gh pr merge`, `eas update`, `aws s3 rm --recursive`, etc. | **Always block** — autopilot never overrides |

This is the "fewer interruptions for low-risk" + "always pause before irreversible" piece of the design.

## Environment overrides

| Var | Effect |
|---|---|
| `CLAUDE_TQ_DISABLED=1` | Skip the UserPromptSubmit decompose hook entirely. |
| `CLAUDE_TQ_PRETOOL_DISABLED=1` | Skip the PreToolUse gate (everything passes). |
| `CLAUDE_TQ_HAIKU_DISABLED=1` | Skip the Haiku call; queue gets no entries from auto-decompose. |
| `CLAUDE_TQ_STATE_DIR=...` | Move the state directory (used by tests). |
| `CLAUDE_HOME=...` | Override the installer's target (default `~/.claude`). |
| `CLAUDE_TQ_PLUGIN_DIR=...` | Override the installer's plugin destination. |

## Roadmap

- **v0.1** — queue + status bar + CLI + pause/resume + Haiku triage *(this release)*
- **v0.2** — versioned rule library (OWASP, WCAG, stack-specific) auto-attached to relevant tasks
- **v0.3** — autosnapshot (`git stash`-backed) + auto-rollback on test failure; explicit low-risk allowlist file
- **v0.4** — parallel-agent recommender + cache-warm task reordering pass
- **v1.0** — multi-user docs, signed-release tarball, plugin marketplace listing if applicable

## Tests

```bash
bats tests/
```

33 tests cover queue ops, classification heuristics, and CLI roundtrips. Haiku itself isn't unit-tested — it talks to the real API.

## License

MIT. See [LICENSE](./LICENSE).
