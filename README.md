# claude-task-queue

A **zero-token, read-only** view of [Claude Code](https://docs.claude.com/en/docs/claude-code)'s native task list — surfaced on your status line as **to-do / doing / done**, aggregated across every session and project.

## The idea

Claude Code already maintains a task list. As the model works it calls its native task tools (`TaskCreate` / `TaskUpdate`), and Claude Code persists each task as a JSON file under `~/.claude/tasks/<session-id>/`:

```json
{ "id": "55", "subject": "Wire engine", "status": "in_progress", "blockedBy": [] }
```

`status` is exactly the state model you want: `pending` = **to-do**, `in_progress` = **doing**, `completed` = **done**.

Because the model writes those files as a normal part of working, **reading them costs nothing.** This plugin is *only* a reader: it scans the native task store, maps each task back to its project, and renders a one-liner to your status line. No second source of truth, no decomposition call, no hooks that enter the model's context — **0 tokens per turn.**

> Earlier versions of this plugin shelled out to Haiku on every prompt to *build* a parallel queue. That was redundant with work the model already does — and the opposite of "minimal token usage." v0.2 deletes all of it.

## What you see

Status line (always visible, never enters context):

```
⚑ 3 proj · 7 todo · 2 doing — ▶ "Wire engine" [task-queue]
```

- `3 proj` — projects with open work
- `7 todo · 2 doing` — open tasks across everything (done is omitted; lifetime totals are just noise on one line)
- `▶ "…" [project]` — the most recently active *doing* task and which project it's in

Full table in a terminal (also zero tokens):

```
$ tq
task-queue  ·  5 todo · 1 doing · 12 done
  ▶ Wire engine
  ▢ Add the status renderer
  ▢ Write the installer
webapp  ·  3 todo · 0 doing · 8 done
  ▢ …
```

Only open tasks are listed; done is shown as a count so the table stays bounded.

## Install

```bash
git clone https://github.com/andrewstanbury/claude-task-queue.git
cd claude-task-queue
./install.sh
```

The installer copies the plugin to `~/.claude/plugins/task-queue/` and sets `statusLine` in `~/.claude/settings.json` — **only if you don't already have one** (it never clobbers an existing status line; see "Composing" below).

Add the CLI to your PATH:

```bash
ln -sf "$HOME/.claude/plugins/task-queue/bin/tq" /usr/local/bin/tq
```

Uninstall (removes our status line only if it's still ours; never touches `~/.claude/tasks`):

```bash
~/.claude/plugins/task-queue/uninstall.sh
~/.claude/plugins/task-queue/uninstall.sh --purge-state   # also drop the label cache
```

## CLI

```
tq            full to-do/doing/done table, grouped by project
tq list       same
tq status     the one-line status (same as the status line)
tq path       print the native tasks directory being read
tq help       help
```

All read-only. There are no add/start/done commands by design: the **model** owns the tasks, so the plugin never mutates them and never desyncs from what Claude sees. To change a task, just tell Claude.

## Composing with an existing status line

If you already run [claude-statusbar](https://github.com/andrewstanbury/claude-statusbar) or another status line, the installer leaves it alone. Add the queue segment yourself by calling:

```bash
~/.claude/plugins/task-queue/bin/tq-status.sh
```

from your own `status.sh` and appending its output next to git/branch/tokens.

## Requirements

- Bash 4+
- `jq`
- Claude Code 2.x (uses its native task store under `~/.claude/tasks`)

## How project grouping works

A task folder is named by session id. The plugin finds that session's transcript at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, reads its `cwd`, and labels it with the **git repo root's** basename (falling back to the cwd's own basename when the session didn't run inside a repo). A session's cwd never changes, so the mapping is cached in `~/.claude/state/task-queue/project-cache.tsv` (the plugin's only writable state).

## Environment overrides

| Var | Effect |
|---|---|
| `CLAUDE_TQ_TASKS_DIR=...` | Where native task folders live (default `~/.claude/tasks`). |
| `CLAUDE_TQ_PROJECTS_DIR=...` | Where session transcripts live (default `~/.claude/projects`). |
| `CLAUDE_TQ_STATE_DIR=...` | Where the label cache is written (default `~/.claude/state/task-queue`). |

## Tests

```bash
bats tests/
```

The suite fakes a task store + transcripts via the `CLAUDE_TQ_*` overrides and asserts the status line and grouped table. No model calls — there's nothing to mock.

## License

MIT. See [LICENSE](./LICENSE).
