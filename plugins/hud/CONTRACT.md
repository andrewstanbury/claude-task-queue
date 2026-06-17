# CONTRACT — what the hud plugin depends on

hud is a `statusLine` renderer. It is **read-only** — it reads stdin and a few
on-disk state files and prints one line. It never writes anything.

> **Observed against:** Claude Code 2.x · last verified **2026-06-10**.

## Dependencies

### 1. `statusLine` stdin payload

- **Fields read:** `.model.display_name` / `.model.id`, `.session_id`,
  `.workspace.current_dir` / `.cwd`, `.context_window.used_percentage`,
  `.terminal_width`.
- **Context note:** `used_percentage` is the payload's pre-computed input-context
  fill (since Claude Code v2.1.132 the `context_window.*` figures reflect
  *current* context, not cumulative session totals). hud renders it as `ctx N%`
  with a green→yellow→red ramp, and the slot is silent when the field is absent
  (before the first API call, or right after `/compact`).
- **Config:** wired by the user's `statusLine` setting. Claude Code can't
  auto-wire a plugin status line, so `/hud:setup` (→ `bin/hud-install.sh`) does it
  once, writing a **version-resilient** command (execs the newest installed hud,
  so it survives updates). It sets **no `refreshInterval`** — the beacon is
  static, so Claude Code's event-driven re-runs (each message / after compact)
  keep every slot fresh without waking jq+git on an idle timer. Override the
  target file with `CLAUDE_SETTINGS`.
- **If it changes:** affected slots fall back (model `?`, ctx hidden, etc.).

### 2. Sibling plugins' on-disk state (read-only; soft path coupling)

hud reads the *state files* the other plugins write — **not their code** (the
install boundary forbids cross-plugin sourcing). It reimplements the tiny reads,
and every slot collapses gracefully if the source is absent. Scoped to signals a
status line is the best surface for; it deliberately does **not** mirror state
shown elsewhere — the task list (Claude Code renders it natively), docs-health
(charter nudges it at session start), or last-tidy — which also removed the
heaviest cross-plugin doc-detection mirrors. Remaining reads:

- **Paused:** task-queue's flag at `~/.claude/state/task-queue/paused/<encoded-root>`.
  Override: `CLAUDE_HUD_PAUSE_DIR`.
- **Agent-mode:** task-queue's flag at `~/.claude/state/task-queue/agent/<encoded-root>`.
  Override: `CLAUDE_HUD_AGENT_DIR`.
- **Tests (verification floor):** tidy-verify's last-outcome marker at
  `~/.claude/state/tidy/verify/result-<session-id>` (`pass`/`fail`/`timeout`) —
  rendered as `✓/✗/⚠ tests` and feeding the beacon color. Override:
  `CLAUDE_HUD_VERIFY_DIR`.
- **Dirty tree:** `git status --porcelain` count for the cwd, shown as `*N` next
  to the branch.
- **Open questions:** the native task store (`~/.claude/tasks/<session-id>/*.json`),
  counting pending/in_progress tasks whose subject starts with `❓`, rendered as
  `❓N`. A read of the *native task store schema* (`subject`/`status`) — the same
  schema task-queue depends on — and a mirror of `tq_open_questions`. Override:
  `CLAUDE_HUD_TASKS_DIR` (falls back to `CLAUDE_TQ_TASKS_DIR`).

This is a **soft coupling via file paths**: if a sibling plugin changes where it
writes, hud's defaults need updating in step. Documented here so that's traceable.
(The `tq_roadmap_path`/`tq_decisions_path` and now `tq_open_questions` mirrors of
task-queue are covered by `tests/drift-guard.bats`.)

### 3. Environment

- Bash 4+, `jq`; `git` optional (branch slot). Honours `NO_COLOR` / `TERM=dumb`.

## Writes

Nothing. hud is purely a renderer.
