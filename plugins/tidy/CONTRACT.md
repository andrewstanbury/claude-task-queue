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
  model turn. Emitted when the file was formatted, has findings, **or is over the
  size budget** (a language-agnostic decomposition nudge, deduped once per file
  per session, skipping binaries / lockfiles / generated files).
- **If it changes:** the format/lint-on-touch silently stops.

**Size-check tunables** (both hooks): `CLAUDE_TIDY_SIZE_BUDGET` (lines/file,
default 400) and `CLAUDE_TIDY_SIZE_CHECK=0` to disable the size nudges entirely.

### 2. `SessionStart` hook payload (stdin)

- Reads `source` (full standard on `startup`/`clear`/unknown, lean re-anchor on
  `compact`/`resume`) and `cwd` (to resolve the repo root). Emits
  `additionalContext` with `hookEventName: "SessionStart"`.
- **Light distill (auto, no manual trigger):** on a fresh context it lists files
  over the size budget (one read-only `wc -l` pass over `git ls-files`, fallback
  `find`) as decomposition candidates — quiet when nothing is over. This is state,
  so it appends even in quiet mode; omitted on `compact`/`resume`.
- **Quiet mode (bootstrap-once + drift-detect):** if the repo root's `CLAUDE.md`
  / `AGENTS.md` / `docs/CLAUDE.md` carries the `claude-companion` marker, the
  full standard is replaced by a one-line re-anchor (the manual is always
  loaded). When absent, the full standard carries a one-line tip to record it and
  add the marker. The token is shared by convention with the other companion
  plugins; detection is self-contained (install boundary — AGENTS.md).

### 3. The language toolchain (environment, optional)

- **Go:** `goimports` (preferred) / `gofumpt` / `gofmt` for formatting;
  `golangci-lint` for findings. All optional — absence → silent no-op.
- **Web:** `eslint` (incl. `eslint-plugin-jsx-a11y`) for JS/TS/JSX/TSX/Vue/Svelte,
  `stylelint` for CSS/SCSS/Less — **findings only, no `--fix`** (read-only;
  `--fix` can change behavior). Resolved project-local (`node_modules/.bin`,
  walking up from the file) before PATH. Linter exit 1 = problems surfaced; 0 =
  clean; 2+ = config/crash → no-op. This shifts much of Lighthouse's
  accessibility / best-practices audit to edit time.
- **Python:** `ruff check` for `.py` — findings only, resolved project-local
  (`.venv`/`venv/bin`, walking up) before PATH. **Shell:** `shellcheck -x` for
  `.sh`/`.bash`. Same exit-code contract as web (1 = findings, 0 = clean, 2+ =
  no-op). These are the **fast, file-scoped** linters; slow whole-project tools
  (clippy, project-wide mypy) are intentionally left to the verification floor
  (§4) — the fastest loop that can catch a problem owns it. Disable a stack by
  not having its tool installed; `CLAUDE_TIDY_LINT_TIMEOUT` bounds each run.
- The plugin **does not install tools**; it detects them and honors the project's
  own config (e.g. `.golangci.yml`, `eslint.config.js`, `.stylelintrc`,
  `ruff.toml`/`pyproject.toml`, `.shellcheckrc`).
- **Currency/modernization:** on touch it walks up from the file to the nearest
  manifest (`package.json`, `go.mod`, `Cargo.toml`, `pyproject.toml`,
  `requirements.txt`, `Gemfile`, `composer.json`, `pom.xml`, `build.gradle[.kts]`)
  and surfaces its **pinned versions** once per manifest per session, with a
  nudge to flag deprecated/behind-latest tech. Judgment is the model's (world
  knowledge); the hook never upgrades. Disable with `CLAUDE_TIDY_CURRENCY=0`.
- **Blast-radius:** for a touched *source* file, surface what depends on it so the
  affected surface gets test coverage (deduped per file per session). **Go** uses
  the toolchain's own import graph — `go list -e -f '{{.ImportPath}} {{.Imports}}…'
  ./...` resolves the exact packages that import the touched file's package
  (caught regardless of comments/aliases) and reports `~N package(s) import X`.
  The module scan is **bounded** (`timeout`, `CLAUDE_TIDY_BLAST_GOLIST_TIMEOUT`,
  default 8s) and **cached per module per session** (run at most once; a failure
  is remembered so it isn't retried). When `go` is absent, disabled
  (`CLAUDE_TIDY_BLAST_GOLIST=0`), or the scan fails, it **falls back** to the grep
  heuristic. **Other languages** use `git grep` for import-context references to
  the basename (`~N files reference X`) — a heuristic, not static analysis,
  guarded (min name length, generic-name skip, capped sample). Disable all with
  `CLAUDE_TIDY_BLAST=0`.

### 4. `Stop` hook payload (stdin) — the verification floor

- **Fields read:** `cwd` (→ repo root) and `session_id` (keys the bounded
  attempt counter). `stop_hook_active` is the loop signal; our own per-session
  counter (capped at `CLAUDE_TIDY_VERIFY_MAX`, default 3) is the hard bound.
- **Behaviour:** if the working tree is dirty *and* a test command is
  discoverable (`tidy_test_command`: explicit `CLAUDE_TIDY_TEST_CMD`, else
  `package.json` test script / `go test` / `cargo test` / `pytest` / `make test`, or a conventional root script (`check.sh` / `test.sh` / `scripts/test`)
  — only when the runner is installed), run it. On failure → emit
  `{ "decision": "block", "reason": "<failure>" }` (fed to the model, not the
  user) up to the cap, then allow the stop with a `systemMessage`. On pass / no
  command / clean tree / `CLAUDE_TIDY_CHECKS=0` → allow silently.
- **If it changes:** the verification floor silently stops; everything else is
  unaffected.
- **Coverage ratchet (opt-in, same Stop hook):** with
  `CLAUDE_TIDY_COVERAGE_RATCHET=1`, before the test run it lists changed source
  files lacking a test (`tidy_untested_changed`) and, if any, blocks with a
  `decision: block` asking to characterize them. Runs even when no test command
  exists (legacy projects). Off by default — the touch-time nudge is the always-on
  version.

#### Coverage ratchet (how test-detection works, and its limits)

`lib/coverage.sh` decides "does this source file have a test?" by **filename
convention only** — sibling names (`x_test.go`, `x.test.ts`, `x.spec.ts`,
`__tests__/x.*`, `test_x.py`, `x.bats`) plus a `tests/`/`test/` dir found by
walking up to 4 levels. It is a heuristic: a project with **consolidated test
files** (one `suite.bats` covering many libs) will get false "no test" nudges for
the libs not named in a sibling test. That's acceptable — the touch nudge is soft,
deduped per file per session, and disable-able (`CLAUDE_TIDY_COVERAGE=0`); it's
tuned for the target case (legacy app code with per-file or absent tests). Don't
make the opt-in **gate** the default without weighing this.

### 5. The `/tidy:distill` and `/tidy:audit` commands (user-invoked)

- **Files:** `commands/distill.md` (auto-discovered, namespaced `/tidy:distill`)
  inlines the stdout of `bin/tidy-distill.sh` via the `!` prefix, then instructs
  the model to run the subtractive pass (dead code, duplication, doc↔code drift).
- **`bin/tidy-distill.sh`** is **read-only** and language-agnostic: it enumerates
  files with `git ls-files --cached --others --exclude-standard` (fallback
  `find`) and reports file/line counts, the heaviest + over-budget files, cruft
  markers, and junk artefacts. Tunables: `CLAUDE_TIDY_SIZE_BUDGET` (default 400),
  `CLAUDE_TIDY_DISTILL_TOP` (default 10). It never writes and never hard-fails.
  The *judgment* (what to actually delete) is the model's, gated on confirmation.
- **`/tidy:audit`** (`commands/audit.md`) reuses the same weight report, then drives
  a read-only, proportional whole-project audit — running the project's own
  tests/linters, flagging dead code/duplication, checking doc proportionality and
  currency, and reporting in plain language. Read-only; offers to fix afterward.

## Where the plugin writes

- **Your source files** — formatter output, in place, for the touched file only.
- **Activity log** — `~/.claude/state/tidy/activity.log` (override
  `CLAUDE_TIDY_LOG_DIR`, disable `CLAUDE_TIDY_LOG_DISABLED`). Best-effort,
  append-only; never blocks a hook.
- **TDD-nudge markers** — empty files under `~/.claude/state/tidy/nudged/`
  (one per session+file) so the test nudge fires at most once per file per
  session. Same fixed home as the log; safe to delete anytime.
- **`go list` cache** — the per-module-per-session import graph under
  `~/.claude/state/tidy/golist/` so the blast-radius scan runs at most once per
  module. All of `nudged/`, `verify/`, `golist/` are pruned after
  `CLAUDE_TIDY_STATE_TTL_DAYS` (default 7); safe to delete anytime.

It writes **nothing** to Claude Code's own state.

## How this is verified

- **`tests/tidy.bats`** fakes every toolchain via stub executables on `PATH`, so
  the dispatch (format-applied, findings-scoped, generated-file skip, graceful
  no-op, payload-drift canary, Python `ruff`/shell `shellcheck` findings, and the
  `go list` exact-importer path vs. its grep fallback) is verified without
  installing `goimports`/`golangci-lint`/`ruff`/`shellcheck`/`go`.
- **`bin/tidy-doctor.sh`** is the on-demand check: it validates the dependencies
  above against the *live* environment (jq, a Go formatter, golangci-lint) and
  prints the activity-log tail. Run it first when tidy seems to do nothing.
- The real toolchain boundary is exercised by using the plugin on an actual Go
  project.
