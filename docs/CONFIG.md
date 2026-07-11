# Configuration reference

Every behavior has an off-switch or a tunable. Set these as environment variables
(e.g. in your shell profile or Claude Code settings env). Defaults are safe — you
only need this to change something.

Booleans are `1` = on / `0` = off unless noted. Directory knobs default under
`~/.claude/state/…` and rarely need changing. Anything marked *(unset)* is empty by
default and only takes effect when you set it.

## task-queue (`CLAUDE_TQ_*`)

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_TQ_TASKS_DIR` | `~/.claude/tasks` | Where the native task JSON store lives. |
| `CLAUDE_TQ_PROJECTS_DIR` | `~/.claude/projects` | Claude Code's per-project session store the plugin reads to scope tasks to this repo. |
| `CLAUDE_TQ_STATE_DIR` | `~/.claude/state/task-queue` | Root for the plugin's flag/marker state. |
| `CLAUDE_TQ_AGENT_DIR` | `~/.claude/state/task-queue/agent` | Per-repo agents-mode flag files. |
| `CLAUDE_TQ_AGENT_MODE` | *(unset → off)* | Global default for agents fan-out; set `on`/`1` to enable everywhere (a per-repo `off` still wins). |
| `CLAUDE_TQ_AWAY_DIR` | `~/.claude/state/task-queue/away` | Autopilot/away flags plus the owner-present and return-review markers. |
| `CLAUDE_TQ_PRESENT_WINDOW` | `1800` | Seconds a fresh prompt counts as "owner present" in autopilot (a prompt is presence). `0` = lights-out (even your prompts stay autonomous). |
| `CLAUDE_TQ_AWAY_ASK_GUARD` | `1` | Hard-block `AskUserQuestion` during the autonomous drain. |
| `CLAUDE_TQ_AWAY_CONTINUE` | `1` | Stop hook auto-continues the queue while autopilot is on and work remains. |
| `CLAUDE_TQ_AWAY_MAX_CONTINUE` | `15` | Cap on auto-continues per prompt, so a stuck model can't spin. |
| `CLAUDE_TQ_AWAY_STALE_HOURS` | `12` | Hours before an "autopilot still on" staleness nudge fires. |
| `CLAUDE_TQ_REVIEW_GATE` | `1` | Return-review gate: blocks edits until the parked `❓` decision pile is cleared. |
| `CLAUDE_TQ_DESIGN_GATE` | `1` | Design-preview guard: blocks edits on a **visual/design** change until a wireframe preview has been shown. |
| `CLAUDE_TQ_INTENT_GATE` | `1` | Intent-confirmation gate on prompt capture and verify. |
| `CLAUDE_TQ_OPEN_Q` | `1` | Surface open `❓` parked-decision reminders during capture. |
| `CLAUDE_TQ_CAPTURE_DISABLED` | *(unset → off)* | Set to any value to disable the per-prompt capture hook entirely. |
| `CLAUDE_TQ_RESUME_MAX` | `7` | Max prior sessions `/task-queue:resume` offers to reinstate. |
| `CLAUDE_TQ_RESUME_MAX_AGE_DAYS` | `14` | Max age (days) of a session `/task-queue:resume` will offer. |
| `CLAUDE_TQ_ROADMAP_FILE` | *(unset → auto-detect)* | Override the path to the roadmap doc used for alignment. |
| `CLAUDE_TQ_DECISIONS_FILE` | *(unset → auto-detect)* | Override the path to the recorded-decisions doc. |

## tidy (`CLAUDE_TIDY_*`)

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_TIDY_SECSCAN` | `1` | Pre-write secret scan (also covers notebook edits). |
| `CLAUDE_TIDY_CHECKS` | `1` | Enable the Stop hook (post-work debt/cycle surface + opt-in test gates); `0` disables it. Tests are run manually — there is no end-of-turn test run. |
| `CLAUDE_TIDY_VERIFY_MAX` | `3` | Max block re-loops for the opt-in coverage/regression gates. |
| `CLAUDE_TIDY_LINT_TIMEOUT` | `30` | Seconds before the lint/format step is abandoned. |
| `CLAUDE_TIDY_SIZE_BUDGET` | `300` | Per-file line budget; over-budget files are flagged. |
| `CLAUDE_TIDY_SIZE_CHECK` | `1` | File-size budget check. |
| `CLAUDE_TIDY_PRUNE_THRESHOLD` | `3` | Over-budget files that trigger the deliberate-prune routing. |
| `CLAUDE_TIDY_COVERAGE` | `0` | Coverage tracking (opt-in). |
| `CLAUDE_TIDY_COVERAGE_RATCHET` | `0` | Coverage-ratchet gate (opt-in). |
| `CLAUDE_TIDY_REGRESSION_GATE` | `0` | Regression gate (opt-in). |
| `CLAUDE_TIDY_CYCLE_CHECK` | `1` | Import-cycle check (via `madge` when present). |
| `CLAUDE_TIDY_CYCLE_TIMEOUT` | `60` | Seconds before the import-cycle (`madge`) scan is abandoned. |
| `CLAUDE_TIDY_BLAST` | `1` | Blast-radius surfacing on touched files. |
| `CLAUDE_TIDY_BLAST_GOLIST` | `1` | Use `go list` for Go blast-radius resolution. |
| `CLAUDE_TIDY_STATE_TTL_DAYS` | `7` | TTL (days) for tidy's throttle/state files. |
| `CLAUDE_TIDY_LOG_DIR` | `~/.claude/state/tidy` | tidy's state/log directory. |

## charter (`CLAUDE_CHARTER_*`)

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_CHARTER_ALIGN_GATE` | `1` | Alignment gate that reconciles work against recorded decisions. |
| `CLAUDE_CHARTER_ALIGN_MAX` | `2` | Max alignment reminders surfaced. |
| `CLAUDE_CHARTER_MCP_PROBE` | `1` | Probe configured MCP servers for reachability. |
| `CLAUDE_CHARTER_MCP_TIMEOUT` | `3` | Seconds per individual MCP-server probe. |
| `CLAUDE_CHARTER_MCP_MAX` | `25` | Max MCP servers probed in one pass. |
| `CLAUDE_MCP_HOME_CONFIG` | `~/.claude.json` | Path to the user-level MCP config the probe merges declared servers from. |
| `CLAUDE_CHARTER_WEB` | *(unset → auto-detect)* | Force the web-QA nudge on (`1`) or off (`0`); default detects a web app structurally. |
| `CLAUDE_CHARTER_LOG_DIR` | `~/.claude/state/charter` | charter's state/log directory. |

## hud (`CLAUDE_HUD_*`)

hud is read-only; these tell it where the other plugins' state lives so it can render
the status line. (hud also reads several `CLAUDE_TQ_*` / `CLAUDE_TIDY_*` /
`CLAUDE_CHARTER_*` toggles above to show which safety checks are off — set those on
their owning plugin, not here.)

| Variable | Default | What it does |
| --- | --- | --- |
| `CLAUDE_HUD_AGENT_DIR` | `~/.claude/state/task-queue/agent` | Where hud reads the agents-mode flag. |
| `CLAUDE_HUD_AWAY_DIR` | `~/.claude/state/task-queue/away` | Where hud reads the autopilot/away flags. |
| `CLAUDE_HUD_VERIFY_DIR` | `~/.claude/state/tidy/verify` | Where hud reads the latest verify result. |
| `CLAUDE_HUD_TASKS_DIR` | `~/.claude/tasks` | Task store hud reads (falls back to `CLAUDE_TQ_TASKS_DIR`). |

## Where state lives

The plugins keep a little on-disk state so modes and throttles survive across
prompts. None of it is secret, and **all of it is safe to delete** — removing a file
just resets that repo's mode or throttle state.

- **task-queue** — under `~/.claude/state/task-queue/`:
  - `away/` — autopilot/away flags, plus `present-<session>` (owner-present) and
    `review-<repo>` (return-review pending) markers.
  - `agent/` — per-repo agents-mode flags.
- **tidy** — under `~/.claude/state/tidy/` (verify results in `tidy/verify/`):
  throttle timestamps and the last verify fingerprint.
- **charter** — under `~/.claude/state/charter/`: alignment throttle state.

These are **per-repo**: the flag filename encodes the repository root (its absolute
path, with `/` rewritten to `-`), so one repo's autopilot/agents state can never leak
into another. The `present-<session>` markers are keyed by session id instead, so
they don't collide with the path-encoded flags. Delete any of them to reset just that
repo (or session).
