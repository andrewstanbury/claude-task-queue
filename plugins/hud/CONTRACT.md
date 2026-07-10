# CONTRACT — what the hud plugin depends on

hud is a `statusLine` renderer. It is **read-only** — it reads stdin and a few
on-disk state files and prints one line. It never writes anything.

> **Observed against:** Claude Code 2.x · last verified **2026-06-10**.

## Dependencies

### 1. `statusLine` stdin payload

- **Fields read:** `.model.display_name` / `.model.id`, `.session_id`,
  `.workspace.current_dir` / `.cwd`, `.context_window.used_percentage`,
  `.context_window.total_input_tokens`, `.context_window.total_output_tokens`,
  `.terminal_width`, `.cost.total_cost_usd`.
- **Token note:** the `total_input_tokens` (⇡) / `total_output_tokens` (⇣) figures
  are rendered as a dim `tok ⇡N ⇣N` slot (humanized k/M), shed on narrow terminals
  and gated on input > 0 so it's silent before the first API call and right after
  `/compact`. Like `used_percentage`, since Claude Code v2.1.132 these are
  *current-context* figures (input incl. cache; output = last response), **not**
  cumulative-session totals — the payload no longer exposes session-cumulative token
  counts.
- **Cost note:** `.cost.total_cost_usd` is the payload's running session spend.
  hud renders it as `$N.NN` (a low-key, color-neutral slot), shed on narrow
  terminals and silent when the field is absent or still `0.00`.
- **Context note:** `used_percentage` is the payload's pre-computed input-context
  fill (since Claude Code v2.1.132 the `context_window.*` figures reflect
  *current* context, not cumulative session totals). hud renders it as `ctx N%`
  with a green→yellow→red ramp, and the slot is silent when the field is absent
  (before the first API call, or right after `/compact`).
- **Config:** wired by the user's `statusLine` setting. Claude Code can't
  auto-wire a plugin status line, so `/hud:setup` (→ `bin/hud-install.sh`) does it
  once, writing a **version-resilient** command (execs the newest installed hud,
  so it survives updates). It sets **`refreshInterval: 1`** (second) — the beacon is
  an animated spinner advancing one frame per second, so it needs a timer on top of
  Claude Code's event-driven re-runs (each message / after compact). The cost is waking
  jq+git once a second on idle — a battery trade the owner opted into for a live status
  line. Override the target file with `CLAUDE_SETTINGS`.
- **If it changes:** affected slots fall back (model `?`, ctx hidden, etc.).

### 2. Sibling plugins' on-disk state (read-only; soft path coupling)

hud reads the *state files* the other plugins write — **not their code** (the
install boundary forbids cross-plugin sourcing). It reimplements the tiny reads,
and every slot collapses gracefully if the source is absent. Scoped to signals a
status line is the best surface for; it deliberately does **not** mirror state
shown elsewhere — the task list (Claude Code renders it natively), docs-health
(charter nudges it at session start), or last-tidy — which also removed the
heaviest cross-plugin doc-detection mirrors. Remaining reads:

- **Autopilot:** task-queue's away flag at `~/.claude/state/task-queue/away/<encoded-root>`
  (autopilot folded in the old away + pause; there is no separate pause flag). Rendered as a bare `✈️` (icon only, shown only when on)
  and colors the health beacon yellow. Override: `CLAUDE_HUD_AWAY_DIR`.
- **Agent-mode:** task-queue's flag at `~/.claude/state/task-queue/agent/<encoded-root>`.
  Override: `CLAUDE_HUD_AGENT_DIR`.
- **Tests (verification floor):** tidy-verify's last-outcome marker at
  `~/.claude/state/tidy/verify/result-<session-id>` (`pass`/`fail`/`timeout`) —
  rendered as `✓/✗/⚠ tests` and feeding the beacon color. Override:
  `CLAUDE_HUD_VERIFY_DIR`.
- **Dirty tree:** `git status --porcelain` count for the cwd, shown as `*N` next
  to the branch.
- **Unpushed/unpulled:** `git rev-list --count --left-right @{upstream}...HEAD`
  for the cwd, shown next to the branch as `↑N` (commits ahead of / not yet pushed
  to the upstream) and `↓N` (behind / not yet pulled). Silent when there's no
  upstream. Computed only on wide terminals in a repo (same gate as the dirty
  count), so it adds no git call to a narrow render.
- **Open questions:** the native task store (`~/.claude/tasks/<session-id>/*.json`),
  counting pending/in_progress tasks whose subject starts with `❓`, rendered as
  `❓N`. A read of the *native task store schema* (`subject`/`status`) — the same
  schema task-queue depends on — and a mirror of `tq_open_questions`. Override:
  `CLAUDE_HUD_TASKS_DIR` (falls back to `CLAUDE_TQ_TASKS_DIR`).
- **Owner-blocked items:** same store, counting pending/in_progress tasks whose
  subject starts with `⏳` (task-queue's `⏳ [blocked]` marker — work waiting on a
  manual owner action), rendered as `⏳N` beside the `❓N` slot. Disjoint from the
  `❓` count by construction (a subject starts with one marker or the other);
  `tests/drift-guard.bats` guards that the two counters never overlap.
This is a **soft coupling via file paths**: if a sibling plugin changes where it
writes, hud's defaults need updating in step. Documented here so that's traceable.
(The `tq_roadmap_path`/`tq_decisions_path` and now `tq_open_questions` mirrors of
task-queue are covered by `tests/drift-guard.bats`.)

### 3. Environment

- Bash 4+, `jq`; `git` optional (branch slot). Honours `NO_COLOR` / `TERM=dumb`.

## Writes

Nothing. hud is purely a renderer.
