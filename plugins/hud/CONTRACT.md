# CONTRACT — what the hud plugin depends on

hud is a `statusLine` renderer. It is **read-only** — it reads stdin and a few
on-disk state files and prints one line. It never writes anything.

> **Observed against:** Claude Code 2.x · last verified **2026-05-31**.

## Dependencies

### 1. `statusLine` stdin payload

- **Fields read:** `.model.display_name` / `.model.id`, `.session_id`,
  `.workspace.current_dir` / `.cwd`, `.context_window.total_input_tokens`,
  `.context_window.total_output_tokens`, `.terminal_width`.
- **Token note:** on current Claude Code, `total_input_tokens` /
  `total_output_tokens` are **current-context** counts (most recent exchange),
  not cumulative session totals. hud labels them up/down; read accordingly.
- **Config:** wired by the user's `statusLine` setting (`type: command`,
  `command`, `refreshInterval`). A plugin can ship a *default* statusLine but the
  user's config wins, so wiring is a documented opt-in.
- **If it changes:** affected slots fall back (model `?`, tokens `0`, etc.).

### 2. Sibling plugins' on-disk state (read-only; soft path coupling)

hud reads the *state files* the other plugins write — **not their code** (the
install boundary forbids cross-plugin sourcing). It reimplements the tiny reads,
and every slot collapses gracefully if the source is absent:

- **Tasks:** `~/.claude/tasks/<session-id>/*.json` (native store) — open count +
  in-progress subject. Override: `CLAUDE_HUD_TASKS_DIR`.
- **Paused:** task-queue's flag at `~/.claude/state/task-queue/paused/<encoded-root>`.
  Override: `CLAUDE_HUD_PAUSE_DIR`.
- **Quality attributes:** the same files charter checks (`QUALITY.md`, ADRs, a QA
  section in `CLAUDE.md`/`AGENTS.md`/`README.md`).
- **Last tidy:** tidy's `~/.claude/state/tidy/activity.log` tail. Override:
  `CLAUDE_HUD_TIDY_LOG`.

This is a **soft coupling via file paths**: if a sibling plugin changes where it
writes, hud's defaults need updating in step. Documented here so that's traceable.

### 3. Environment

- Bash 4+, `jq`; `git` optional (branch slot). Honours `NO_COLOR` / `TERM=dumb`.

## Writes

Nothing. hud is purely a renderer.
