# CONTRACT — what this plugin depends on

claude-task-queue is **read-only over Claude Code's own task store** and works by
reading a few of Claude Code's internal files and hook payloads. **None of these
are documented, stable APIs** — they are observed behaviour. This file records
exactly what we lean on so that, when something breaks after a Claude Code
update, you know where to look first.

> **Observed against:** Claude Code 2.x · last verified **2026-05-30**.
> If you re-verify on a newer version, bump that date.

All of this knowledge is centralized in [`lib/tasks.sh`](./lib/tasks.sh) and the
two entrypoints in [`bin/`](./bin). If a dependency below changes, that is where
the fix goes — nothing else in the repo encodes these assumptions.

## The hard invariant

**We never write Claude Code's task store.** `~/.claude/tasks` belongs to the
model; the plugin only ever *reads* it or *injects context that nudges the
model*. It never calls `TaskCreate`/`TaskUpdate` and never edits a task file.
This is the line that keeps the plugin from becoming a second, desyncing source
of truth — do not cross it. See the `never-mutate-native-store` design note.

## Dependencies

### 1. Native task store layout & schema

- **Path:** `~/.claude/tasks/<session-id>/<n>.json` (one file per task).
  Overridable in tests via `CLAUDE_TQ_TASKS_DIR`.
- **Fields read:** `id` (string), `subject`, `status`
  (`"pending" | "in_progress" | "completed"`), `blockedBy` (array of ids).
  We also use file **mtime** as a recency signal.
- **Used by:** the resume bridge (open tasks from prior sessions) and the
  advance hook (next unblocked task).
- **If it changes:** carry-over and/or auto-advance silently stop. The plugin
  degrades to policy-only injection — it does not error out.

### 2. Transcript → repo mapping

- **Path:** `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`.
  Overridable via `CLAUDE_TQ_PROJECTS_DIR`.
- **Assumption:** a line near the **head** of that transcript carries a `cwd`
  field; we read it and resolve the **git repo root** (falling back to the cwd).
  This is how a task folder (keyed by session id) is scoped to a repo. Result is
  cached in `${CLAUDE_TQ_STATE_DIR}/root-cache.tsv` (a session's cwd is immutable).
- **If it changes:** sessions can't be mapped to repos, so cross-session resume
  stops surfacing tasks. Advance is unaffected (it uses the session id from the
  hook payload directly).

### 3. `SessionStart` hook payload (stdin)

- **Fields read:** `session_id`, `cwd` (and `source` is present but unused).
- **Output contract:** we emit
  `{ "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "<text>" } }`
  — injected into the session context once.

### 4. `TaskCompleted` hook payload (stdin)

- **Fields read:** `session_id`, `task_id` (the just-completed task), and `cwd`
  (used to resolve the repo root for the pause check; falls back to the session
  transcript if absent).
- **Timing is treated as unknown:** we do **not** assume the store file has been
  rewritten when the hook fires. The advance logic treats `task_id` as closed
  for `blockedBy` purposes, so it is correct whether the hook runs before or
  after the native write.
- **Output contract:** same shape as above, with
  `"hookEventName": "TaskCompleted"`.

### 5. Hook wiring & env

- `hooks/hooks.json` wires both entrypoints; Claude Code expands
  `${CLAUDE_PLUGIN_ROOT}` (plugin dir) and `${CLAUDE_PLUGIN_DATA}` (writable
  per-plugin state, used for the root cache).
- Requires **Bash 4+** and **`jq`** on PATH.

## How this is (and isn't) tested

The `bats` suite (`tests/tasks.bats`) **fakes** the layouts above via the
`CLAUDE_TQ_*` overrides. That fully exercises our *logic*, but by construction it
**cannot detect a change in Claude Code's real format** — those tests would stay
green while production silently broke.

The real boundary is therefore verified three other ways:

- **`tests/packaging.bats`** guards the shipped artifact (version sync, valid
  JSON, hook scripts exist) — see CI.
- **`bin/tq-doctor.sh`** is the on-demand check: it validates every dependency
  above against the *live* environment (not a fake), including a **schema
  canary** that samples real task files and confirms they still carry the
  `id`/`status` fields we read. Run it first when something stops working.
- **Manual end-to-end:** after `claude plugin update task-queue`, start a fresh
  session, create two tasks, complete the first, and confirm the
  `Next unblocked task: #…` note appears. Run this whenever you bump the
  "observed against" version above.

## Where the plugin writes (never the task store)

Three small files, all outside `~/.claude/tasks`:

- **Root cache** — `${CLAUDE_PLUGIN_DATA}/root-cache.tsv` (session→repo mapping;
  in plugin data so it survives updates).
- **Activity log** — `~/.claude/state/task-queue/activity.log` (overridable via
  `CLAUDE_TQ_LOG_DIR`, disabled via `CLAUDE_TQ_LOG_DISABLED`). A fixed home, so
  `tq-doctor` — run by hand with no plugin env — reads the same file the hooks
  write. Best-effort and append-only; it never blocks a hook.
- **Pause flags** — `~/.claude/state/task-queue/paused/<encoded-repo-root>`
  (overridable via `CLAUDE_TQ_PAUSE_DIR`). One empty file per paused repo; its
  presence is the pause. A fixed home for the same reason as the log: the
  `TaskCompleted` hook and `bin/tq-pause.sh` (run by the model in plain bash)
  must resolve the identical path.

If a dependency here drifts, prefer making the plugin **degrade quietly** (no
output) over guessing — a missing nudge is invisible; a wrong one is noise.
