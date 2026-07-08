# CONTRACT — what this plugin depends on

claude-task-queue is **read-only over Claude Code's own task store** and works by
reading a few of Claude Code's internal files and hook payloads. **None of these
are documented, stable APIs** — they are observed behaviour. This file records
exactly what we lean on so that, when something breaks after a Claude Code
update, you know where to look first.

> **Observed against:** Claude Code 2.x · last verified **2026-06-16**.
> If you re-verify on a newer version, bump that date.

All of this knowledge is centralized in [`lib/tasks.sh`](./lib/tasks.sh) and the
entrypoints in [`bin/`](./bin). If a dependency below changes, that is where
the fix goes — nothing else in the repo encodes these assumptions.

## The hard invariant

**We never write Claude Code's task store.** `~/.claude/tasks` belongs to the
model; the plugin only ever *reads* it or *injects context that nudges the
model*. It never calls `TaskUpdate` and never edits a task file.
This is the line that keeps the plugin from becoming a second, desyncing source
of truth — do not cross it. See the `never-mutate-native-store` design note.

## Dependencies

### 1. Native task store layout & schema

- **Path:** `~/.claude/tasks/<session-id>/<n>.json` (one file per task).
  Overridable in tests via `CLAUDE_TQ_TASKS_DIR`.
- **Fields read:** `id` (string), `subject`, `status`
  (`"pending" | "in_progress" | "completed"`), `blockedBy` (array of ids).
  We also use file **mtime** as a recency signal.
- **Used by:** the resume bridge (open tasks from prior sessions).
- **Lifecycle (observed 2026-05-30):** while a session's list has **any open
  task**, completed entries are **retained** on disk (status `completed`); the
  folder appears to be cleared only once the list is **fully drained**. So the
  store may hold a mix of `pending`/`in_progress`/`completed` files, or be empty.
  *(An earlier revision of this file claimed completed files are removed
  individually on completion — that was a misread of a fully-drained list, and
  is corrected here.)* The resume bridge is robust either way: it **selects only**
  `pending`/`in_progress`, so lingering completed entries never leak into carry-over.
- **If it changes:** carry-over silently stops. The plugin degrades to
  policy-only injection — it does not error out.

### 2. Transcript → repo mapping

- **Path:** `~/.claude/projects/<encoded-cwd>/<session-id>.jsonl`.
  Overridable via `CLAUDE_TQ_PROJECTS_DIR`.
- **Assumption:** a line near the **head** of that transcript carries a `cwd`
  field; we read it and resolve the **git repo root** (falling back to the cwd).
  This is how a task folder (keyed by session id) is scoped to a repo. Result is
  cached in `${CLAUDE_TQ_STATE_DIR}/root-cache.tsv` (a session's cwd is immutable).
- **If it changes:** sessions can't be mapped to repos, so cross-session resume
  stops surfacing tasks.

### 2b. Committed roadmap/backlog file (read-only, optional)

- **Path:** one of `docs/ROADMAP.md`, `ROADMAP.md`, `docs/BACKLOG.md`,
  `BACKLOG.md` at the repo root. Override via `CLAUDE_TQ_ROADMAP_FILE`.
- **Use:** on a fresh SessionStart, if present, the resume bridge adds a nudge to
  *hydrate the live task list* from the backlog's open items. We only check the
  file **exists** — we don't parse it; the model reads it. Detection is duplicated
  from the charter plugin on purpose (the install boundary keeps plugins
  self-contained — see AGENTS.md).
- **If it's absent:** no hydration nudge; everything else is unchanged.

### 2c. Policy marker in the Claude manual (read-only, optional)

- **Path:** `CLAUDE.md` / `AGENTS.md` / `docs/CLAUDE.md` at the repo root,
  scanned for the literal token `claude-companion`.
- **Use:** on a fresh SessionStart, if present, the standing **policy** prose is
  replaced by a one-line re-anchor (bootstrap-once + drift-detect) — the manual
  is always loaded, so re-injecting it is a token tax. **State is never
  suppressed:** carryover, roadmap hydration, and drift signals still
  fire. When absent, the full policy is injected with a one-line tip to record it
  and add the marker. The token is shared by convention with the other companion
  plugins (each detects it independently — install boundary).

### 3. `SessionStart` hook payload (stdin)

- **Fields read:** `session_id`, `cwd`, and `source` — `source` selects the full
  policy block (`startup`/`clear`/unknown) vs. a lean re-anchor
  (`compact`/`resume`). An unknown/missing source falls back to the full block.
- **Output contract:** we emit
  `{ "hookSpecificOutput": { "hookEventName": "SessionStart", "additionalContext": "<text>" } }`
  — injected into the session context.

### 4. `UserPromptSubmit` hook payload (stdin)

- **Fields read:** `prompt` (the user's text) and `session_id`.
- **Behavior (`tq-capture.sh`):** injects a loop instruction on **every prompt**
  (local bash/jq checks — no model cost to classify; owner decision 2026-06-26), but
  **splits the loop from the interrupt** (2026-06-27). The **DEFAULT path** is a LEAN
  re-anchor — interpret the request in one line, decompose into tasks, `TaskCreate`,
  and **work it in auto** — that points at the full procedure on the SessionStart
  policy and **delegates the sign-off decision to the model** (which has read the
  prompt and can judge blast radius a regex can't): it surfaces an AskUserQuestion
  present-and-approve **only on real signal** (ambiguous / high blast-radius / would
  recommend against). The **HEAVY present-and-approve + critique** variant fires only
  on the deterministic high-stakes signal — `tq_looks_consequential` (irreversible/
  binding) and `tq_looks_design` (visual, show-first) in `lib/capture.sh` — where the
  cost of getting it wrong justifies the tokens and the interruption. The full
  procedure + critique posture the lean path re-anchors to ride the **SessionStart
  policy** (`tq-resume.sh`), stated once per session, not re-injected per prompt. It
  fires **regardless of existing queue state**. Only **slash/bang commands and empty
  prompts** are skipped (not user work). **Autopilot suppresses the interrupt:**
  when the repo is running autonomously (§ autopilot flag) and the owner isn't
  present for the turn, the present-and-approve is skipped and prompts run straight
  through in auto. Disabled with `CLAUDE_TQ_CAPTURE_DISABLED`. *(History: before
  2026-06-26 the loop fired only on multi-step / consequential / visual prompts and
  stayed silent on trivial ones; `tq_looks_multistep` was removed when that
  "substantive" gate was dropped.)*
- **Design preview (visual prompts):** when the prompt looks like a **visual/UI/
  layout** change (`tq_looks_design` in `lib/capture.sh` — a visual intent + a UI
  noun, or an inherently-visual term; precision-tuned so architecture/API "design"
  and functional edits don't trip it), the injected instruction becomes a
  *design-preview* loop: present a recommended design + 2-3 alternatives as faithful
  **ASCII mockups** in the AskUserQuestion `preview` field (recommended first, native
  arrow-key nav + Enter), build only the chosen one. Fires even on a short
  single-sentence ask; a *consequential* visual change keeps the consequential
  scrutiny and appends a design-preview note. Relies on AskUserQuestion supporting
  `preview` (monospace ASCII).
- **Open-questions reminder (always, if any):** before the loop logic, it reads the
  native task store for this session (`tq_open_questions` — pending/in_progress tasks
  whose subject starts with `❓`) and, if any exist, prepends a reminder so the model
  re-raises them. Fires on EVERY prompt (trivial or paused included) — a new prompt is
  when unanswered questions get buried. The model records them (TaskCreate `❓ …`) and
  clears them (TaskUpdate → completed); recording is model-assisted (the hook only
  re-surfaces). Disable with `CLAUDE_TQ_OPEN_Q=0`. hud mirrors the count (`❓N`).
- **Return-review nudge (only while the gate is armed):** when autopilot turned OFF
  leaving parked `❓` decisions, `tq-away.sh` armed a per-repo review marker and the
  PreToolUse guard (`tq-review-guard.sh`) blocks *edits* until it clears. But the guard
  only bites on a write — a read-only turn could pass the one-time off-digest without
  presenting the pile. So while the marker is armed (`tq_review_pending` + a parked `❓`
  still exists), this prepends a **leading** instruction to present the `❓` pile via a
  blocking AskUserQuestion FIRST, on every prompt until the pile empties. Conditional on
  the armed marker → **zero steady-state per-prompt cost**. Self-heals a stale marker
  (armed but no `❓` left → clears it). Honors the guard's `CLAUDE_TQ_REVIEW_GATE=0`
  escape. `⏳ [blocked]` owner-action items never arm or hold this — they're relayed,
  not gated.
- **Intent of record (side effect):** on any non-paused prompt it also stashes the
  prompt text to `tq_intent_file($session_id)` (in the state dir) for the Stop gate
  below. Best-effort; gated off by `CLAUDE_TQ_INTENT_GATE=0`.
- **Output contract:** same shape, with `"hookEventName": "UserPromptSubmit"`.
- **If it changes:** the loop instruction silently stops; capture still relies on
  the SessionStart policy.

### 4b. `Stop` hook payload (stdin) — the intent→outcome gate

- **Script:** `bin/tq-verify.sh`. **Fields read:** `cwd` (resolved to the repo
  root) and `session_id` (keys the stashed intent).
- **Behavior:** the close of the owner loop. On the first **dirty** Stop after a
  substantive ask was captured (§4), it replays the **intent of record** + a
  `git diff --stat` of what changed and blocks **once** (`decision: block`) so the
  model verifies the OUTCOME matches the ask and recaps in plain language —
  surfacing "wrong thing / only part / something extra" to the non-technical owner
  before "done". The intent is **consumed on fire**, so it can never loop; it's the
  outcome-time complement to §4's intent-time review.
- **Silent when:** no intent was captured (trivial/conversational turn), the tree is
  clean (work not done → intent kept for a later Stop), outside a git repo, or
  `CLAUDE_TQ_INTENT_GATE=0`. Best-effort — any internal error degrades to "allow the
  stop" (it re-asserts `set +e` after sourcing `lib/tasks.sh`, which enables `-e`).
- **If it changes:** the gate silently stops; the rest of the plugin is unaffected.

### 5. Hook wiring & env

- `hooks/hooks.json` wires all entrypoints; Claude Code expands
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
- **Schema-drift canary:** `tq_schema_status` (in `lib/tasks.sh`) samples real
  task files and confirms they still carry the `id`/`status` fields we read; its
  result is surfaced at SessionStart. This is the live-environment check that the
  fakes can't provide — heed it first when something stops working.
- **Manual end-to-end:** after `claude plugin update task-queue`, start a fresh
  session, leave a task open, end the session, and start a new session in the same
  repo — confirm the cross-session resume note re-surfaces the unfinished task.
  Run this whenever you bump the "observed against" version above.

## Where the plugin writes (never the task store)

A few small files, all outside `~/.claude/tasks`:

- **Root cache** — `${CLAUDE_PLUGIN_DATA}/root-cache.tsv` (session→repo mapping;
  in plugin data so it survives updates).
- **Intent of record** — `<state-dir>/intent-<session_id>` (the latest substantive
  prompt, written by `tq-capture.sh`, read+consumed by `tq-verify.sh`). Both hooks
  run with `CLAUDE_TQ_STATE_DIR=${CLAUDE_PLUGIN_DATA}`, so they share the path; not
  the task store.
- **Autopilot (away) flags** — `~/.claude/state/task-queue/away/<encoded-repo-root>`
  (overridable via `CLAUDE_TQ_AWAY_DIR`). One file per repo running autonomously
  (stamped with the on-time); its presence drives the auto-continue, ask-block, and
  park behaviour. Written by `bin/tq-away.sh`; read by the capture/verify/ask-guard
  hooks. The old separate *pause* flag was folded into this — there is no `tq-pause.sh`.
- **Agent-mode flags** — `~/.claude/state/task-queue/agent/<encoded-repo-root>`
  (overridable via `CLAUDE_TQ_AGENT_DIR`). Same scheme: an empty file
  per repo where agent-mode is explicitly enabled. `bin/tq-agent.sh` writes it; the
  SessionStart hook reads it to decide whether to permit subagent fan-out.
  **Global default:** `CLAUDE_TQ_AGENT_MODE=on|1` (e.g. in settings.json `env`)
  turns agent-mode on everywhere without a per-repo flag — for users who prefer
  speed over token-thrift. Per-repo flag OR the env enables it; off otherwise.

If a dependency here drifts, prefer making the plugin **degrade quietly** (no
output) over guessing — a missing nudge is invisible; a wrong one is noise.
