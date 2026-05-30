# CONTRACT — what the tidy plugin depends on

This plugin reacts to Claude Code hook payloads and **writes to your working
tree** (formatting). None of the Claude Code internals below are documented,
stable APIs — they're observed behaviour. This file records them so a future
break is easy to trace.

> **Observed against:** Claude Code 2.x · last verified **2026-05-30**.

## The invariant

This plugin is deliberately conservative because it *mutates files*:

- **Only behavior-preserving fixes are auto-applied** (formatters). Linter
  findings are *surfaced as context*, never silently rewritten.
- **Scoped to the single file** named in the hook payload — never repo-wide.
- **Never breaks the triggering edit** — every step is best-effort; on any
  error or missing tool the hook exits 0 with no output.

## Dependencies

### 1. `PostToolUse` hook payload (stdin)

- **Matcher:** `Edit|Write`.
- **Field read:** `tool_input.file_path` — the edited file. (Also `tool_name`,
  unused beyond the matcher.)
- **Timing:** PostToolUse fires *after* the tool writes, so the file is present
  on disk when the hook runs.
- **Output contract:** `{ "hookSpecificOutput": { "hookEventName":
  "PostToolUse", "additionalContext": "<text>" } }` — injected before the next
  model turn. Emitted only when the file was formatted or has findings.
- **If it changes:** the format/lint-on-touch silently stops.

### 2. `SessionStart` hook payload (stdin)

- Reads only `source`: the full standard on `startup`/`clear`/unknown, a lean
  re-anchor on `compact`/`resume`. Emits `additionalContext` with
  `hookEventName: "SessionStart"`.

### 3. The language toolchain (environment, optional)

- **Go:** `goimports` (preferred) / `gofumpt` / `gofmt` for formatting;
  `golangci-lint` for findings. All optional — absence → silent no-op.
- The plugin **does not install tools**; it detects them with `command -v` and
  honors the project's own config (e.g. `.golangci.yml`).

## Where the plugin writes

- **Your source files** — formatter output, in place, for the touched file only.
- **Activity log** — `~/.claude/state/tidy/activity.log` (override
  `CLAUDE_TIDY_LOG_DIR`, disable `CLAUDE_TIDY_LOG_DISABLED`). Best-effort,
  append-only; never blocks a hook.
- **TDD-nudge markers** — empty files under `~/.claude/state/tidy/nudged/`
  (one per session+file) so the test nudge fires at most once per file per
  session. Same fixed home as the log; safe to delete anytime.

It writes **nothing** to Claude Code's own state.

## How this is verified

- **`tests/tidy.bats`** fakes the Go toolchain via stub executables on `PATH`, so
  the dispatch (format-applied, findings-scoped, generated-file skip, graceful
  no-op, payload-drift canary) is verified without installing
  `goimports`/`golangci-lint`.
- **`bin/tidy-doctor.sh`** is the on-demand check: it validates the dependencies
  above against the *live* environment (jq, a Go formatter, golangci-lint) and
  prints the activity-log tail. Run it first when tidy seems to do nothing.
- The real toolchain boundary is exercised by using the plugin on an actual Go
  project.
