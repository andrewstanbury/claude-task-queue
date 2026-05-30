# claude-task-queue

A **native-first** Claude Code plugin that makes your task queue *live* — with a couple of event-driven hooks and **zero per-prompt cost**. It doesn't invent a queue, a database, or a status bar. It leans entirely on the task list Claude Code already maintains (and already renders in the CLI), and just primes the model to keep that list filled, ordered, carried across sessions, and moving.

## The idea

As Claude Code works it maintains a real task list — it calls its native task tools (`TaskCreate` / `TaskUpdate`) and persists each task under `~/.claude/tasks/<session-id>/`:

```json
{ "id": "55", "subject": "Wire engine", "activeForm": "Wiring engine",
  "status": "in_progress", "blocks": [], "blockedBy": [] }
```

When the model creates or updates tasks, Claude Code **renders that list live in the terminal**. That's the queue — it already exists and already renders. The catches are: the model only fills it when *it* decides to, the list is per-session working memory that starts empty every time, and once it's filled the model can lose momentum and let it stall. This plugin nudges all three, with two event-driven hooks and nothing else.

## What it does

### A `SessionStart` hook — *fill and resume*

Injects a single block of context, once, when a session begins:

**1. Queue policy (a standing instruction).** It tells the model to treat its native task list as the live work queue: capture described work with `TaskCreate` so it shows in the queue, work the queue in dependency order (honoring `blockedBy`), batch same-area tasks, prefer inline over subagents, and advance as you go without draining the backlog. Stated *once*, this governs the whole session — so population and ordering happen with **no per-prompt token cost**, reinforced by Claude Code's own built-in task nudges.

**2. Resume.** It reads the native store for **open tasks left by earlier sessions in the same repo** and appends them, so the model re-adopts your unfinished work into the (otherwise empty) list. Capped and recency-bounded so it stays a brief note, not a dump.

### A `TaskCompleted` hook — *advance*

Fires **only when the model marks a task done** — not per prompt — and, when there's a clear next step, injects a one-line note naming the next *unblocked* task (lowest id first, honoring `blockedBy`). That keeps the model moving down the queue in dependency order without being asked. It stays **silent** when another task is already `in_progress` (work is underway — a nudge would just distract) or when nothing is actionable (queue blocked, drained, or empty), so it never pushes the model to drain the backlog. To stay correct whether the hook fires before or after the native write, it treats the just-completed task as closed when checking dependencies.

After that, **Claude Code does the rest natively** — its task tools fill the queue, and its task view *is* the visible queue in the CLI. The plugin adds no UI, no second store, and nothing that runs per prompt: one short injection per session, plus one short note each time a task completes.

## Read-only by design

This plugin **never writes to Claude Code's task store.** `~/.claude/tasks` belongs to the model — it creates and updates tasks there, and this plugin only ever *reads* it (the resume bridge and the advance hook both scan task files) or *nudges the model* (every hook just injects context). It never calls `TaskCreate`/`TaskUpdate` itself.

That's a deliberate boundary:

- **No second source of truth.** There's no parallel queue that could disagree with what Claude sees. The native store is the single source of truth.
- **No desync.** Because we never mutate tasks, the plugin can't drift out of step with the model's own view.
- **The model stays in control.** Even the live-queue hook only *asks* the model to enqueue; the model decides and writes via its own native tools.

The guiding rule for anything added here: **lean on native Claude Code features, and either read the store or nudge the model — never write task files directly.**

## Install

This is a native Claude Code plugin (requires Claude Code 2.x with the plugin system). Add the marketplace and install:

```bash
claude plugin marketplace add andrewstanbury/claude-task-queue
claude plugin install task-queue@andrewstanbury
```

The plugin is **enabled by default** (`defaultEnabled: true`) — installing it is enough, no separate `enable` step. Its hooks are event-driven and add only a short injection per session (plus one short note per task completion), so the cost is minimal. Restart Claude Code (or start a new session) for the hooks to take effect. To opt out without uninstalling, run `claude plugin disable task-queue`.

- **Update:** `claude plugin update task-queue`
- **Disable / uninstall:** `claude plugin disable task-queue` · `claude plugin uninstall task-queue`

No install script, no editing `settings.json` — Claude Code wires and unwires the hooks for you.

## Configuration

The resume note is tunable via environment variables (read by the `SessionStart` hook):

| Var | Effect |
|---|---|
| `CLAUDE_TQ_RESUME_MAX` | Max todos listed in the resume note (default `7`; in-progress tasks are always shown). |
| `CLAUDE_TQ_RESUME_MAX_AGE_DAYS` | Skip sessions untouched longer than this (default `14`). |

The plugin caches each session's repo root under `${CLAUDE_PLUGIN_DATA}` so resolution stays fast across updates.

## How it stays scoped to a repo

A task folder is keyed by session id. The resume bridge finds that session's transcript at `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`, reads its `cwd`, and resolves the **git repo root** (falling back to the cwd itself outside a repo). Only tasks rooted at the repo you're starting in are carried over.

## Requirements

- Claude Code 2.x (native plugin system + task store under `~/.claude/tasks`)
- Bash 4+ and `jq`

## Tests

```bash
bats tests/
```

The suite fakes a task store + transcripts via `CLAUDE_TQ_*` overrides and asserts what each hook injects. No model calls — there's nothing to mock.

## License

MIT. See [LICENSE](./LICENSE).
