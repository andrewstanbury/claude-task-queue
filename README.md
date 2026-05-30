# claude-task-queue

A **native-first** companion to [Claude Code](https://docs.claude.com/en/docs/claude-code)'s built-in task list. It doesn't invent a queue, a status bar, or a second source of truth — it leans entirely on the tasks Claude already creates, and adds the one thing the native system doesn't do on its own: **carry your unfinished work across sessions.**

## The idea

As Claude Code works it maintains a real task list — it calls its native task tools (`TaskCreate` / `TaskUpdate`) and persists each task as a JSON file under `~/.claude/tasks/<session-id>/`:

```json
{ "id": "55", "subject": "Wire engine", "activeForm": "Wiring engine",
  "status": "in_progress", "blocks": [], "blockedBy": [] }
```

That list already gives you decomposition, `to-do / doing / done` (`pending` / `in_progress` / `completed`), dependency edges, and an inline render in the terminal — for free.

But the native list is **per-session working memory**. Start a new session in the same repo tomorrow and yesterday's unfinished tasks are invisible to the model. That gap — *continuity* — is the only thing this project fills.

## What it does

**1. Resume bridge** (a `SessionStart` hook). When a new session starts, it scans the native task store for **open tasks left by earlier sessions in the same repo** and hands them to Claude as a short note, so it can re-adopt the relevant ones into its native list. Everything you see stays native — there's no new UI.

It's deliberately small: it lists the in-progress task(s) plus the most-recently-touched todos (capped), and skips sessions you haven't touched in a while so abandoned backlogs don't keep resurfacing. It's the only part of this plugin that enters Claude's context — and only when there's genuinely carried-over work.

**2. `tq`** — a zero-token terminal reader of the native store, for when *you* want to eyeball what's open across every project. It never enters Claude's context.

## Read-only by design

This plugin **never writes to Claude Code's task store.** `~/.claude/tasks` belongs to the model — it creates and updates tasks there as a normal part of working, and this plugin only ever *reads* those files.

That's a deliberate boundary, not a limitation:

- **No second source of truth.** There's no parallel queue, no database, no sync layer that could disagree with what Claude actually sees. The native store is the single source of truth; we render it.
- **No desync.** Because we never mutate tasks, the plugin can't drift out of step with the model's own view. The `tq` reader and the resume note always reflect exactly what's on disk.
- **The model stays in control.** Even the resume bridge doesn't write tasks — it hands Claude a short *note*, and Claude decides what to re-adopt via its own native `TaskCreate`. To change a task, you tell Claude; it updates the store; we read the result.

The guiding rule for anything added here: **lean on native Claude Code features, and either read the store or feed the model context — never write task files directly.** It keeps the project small and impossible to desync.

## What you see

When you resume work in a repo with unfinished tasks, Claude receives a note like:

```
3 open tasks carry over from earlier Claude Code sessions in this project. If
the user is continuing this work, recreate the relevant ones with TaskCreate —
set the in-progress one to in_progress; otherwise ignore this note.
  • [doing] Wire engine
  • [todo]  Add the status renderer
  • [todo]  Write the installer
```

In a terminal, `tq` shows the full picture (zero tokens, grouped by project):

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

The installer copies the plugin to `~/.claude/plugins/task-queue/` and registers the `SessionStart` hook in `~/.claude/settings.json` (idempotently — it never duplicates itself and leaves any other hooks you have untouched).

Add the CLI to your PATH:

```bash
ln -sf "$HOME/.claude/plugins/task-queue/bin/tq" /usr/local/bin/tq
```

Uninstall (removes only our own hook entry; never touches `~/.claude/tasks`):

```bash
~/.claude/plugins/task-queue/uninstall.sh
~/.claude/plugins/task-queue/uninstall.sh --purge-state   # also drop the caches
```

## CLI

```
tq            full to-do/doing/done table, grouped by project
tq list       same
tq status     one-line summary of open work across all projects
tq path       print the native tasks directory being read
tq help       help
```

All read-only — there are no add/start/done commands ([by design](#read-only-by-design)). To change a task, just tell Claude.

## How project grouping works

A task folder is named by session id. The plugin finds that session's transcript at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, reads its `cwd`, and resolves the **git repo root** (falling back to the cwd itself when the session didn't run inside a repo). A session's cwd never changes, so the mapping is cached under `~/.claude/state/task-queue/`.

## Configuration

| Var | Effect |
|---|---|
| `CLAUDE_TQ_RESUME_MAX` | Max todos listed in the resume note (default `7`; in-progress tasks are always shown). |
| `CLAUDE_TQ_RESUME_MAX_AGE_DAYS` | Skip sessions untouched longer than this in the resume note (default `14`). |
| `CLAUDE_TQ_TASKS_DIR` | Where native task folders live (default `~/.claude/tasks`). |
| `CLAUDE_TQ_PROJECTS_DIR` | Where session transcripts live (default `~/.claude/projects`). |
| `CLAUDE_TQ_STATE_DIR` | Where the caches are written (default `~/.claude/state/task-queue`). |

## Requirements

- Bash 4+
- `jq`
- Claude Code 2.x (uses its native task store under `~/.claude/tasks`)

## Tests

```bash
bats tests/
```

The suite fakes a task store + transcripts via the `CLAUDE_TQ_*` overrides and asserts both the `tq` output and the resume note the hook injects. No model calls — there's nothing to mock.

## License

MIT. See [LICENSE](./LICENSE).
