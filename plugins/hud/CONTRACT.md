# CONTRACT — what the hud plugin depends on

hud is a `statusLine` renderer. It is **read-only** — it reads stdin and a few
on-disk state files and prints one line. It never writes anything.

> **Observed against:** Claude Code 2.x · last verified **2026-06-01**.

## Dependencies

### 1. `statusLine` stdin payload

- **Fields read:** `.model.display_name` / `.model.id`, `.session_id`,
  `.workspace.current_dir` / `.cwd`, `.context_window.used_percentage`,
  `.context_window.context_window_size`, `.terminal_width`.
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
and every slot collapses gracefully if the source is absent:

- **Tasks:** `~/.claude/tasks/<session-id>/*.json` (native store) — open count +
  in-progress subject. Override: `CLAUDE_HUD_TASKS_DIR`.
- **Paused:** task-queue's flag at `~/.claude/state/task-queue/paused/<encoded-root>`.
  Override: `CLAUDE_HUD_PAUSE_DIR`.
- **Agent-mode:** task-queue's flag at `~/.claude/state/task-queue/agent/<encoded-root>`.
  Override: `CLAUDE_HUD_AGENT_DIR`.
- **Tests (verification floor):** tidy-verify's last-outcome marker at
  `~/.claude/state/tidy/verify/result-<session-id>` (`pass`/`fail`/`timeout`) —
  rendered as `✓/✗/⚠ tests` and feeding the beacon color. Override:
  `CLAUDE_HUD_VERIFY_DIR`.
- **Docs health (charter baseline):** the same files charter checks for the
  project map (`docs/MAP.md`/`MAP.md`/`ARCHITECTURE.md`), roadmap
  (`docs/ROADMAP.md`/`ROADMAP.md`/`BACKLOG.md`), and quality attributes
  (`QUALITY.md`/`.adoc`, `docs/CLAUDE.md`, a QA section in a manual doc, or the
  `CLAUDE_CHARTER_QA_FILE` override) — shown as `docs ✓` / `docs N/3`.
- **Last tidy:** tidy's `~/.claude/state/tidy/activity.log` tail. Override:
  `CLAUDE_HUD_TIDY_LOG`.
- **Dirty tree:** `git status --porcelain` count for the cwd, shown as `*N` next
  to the branch.

This is a **soft coupling via file paths**: if a sibling plugin changes where it
writes, hud's defaults need updating in step. Documented here so that's traceable.

### 3. Environment

- Bash 4+, `jq`; `git` optional (branch slot). Honours `NO_COLOR` / `TERM=dumb`.

## Writes

Nothing. hud is purely a renderer.
