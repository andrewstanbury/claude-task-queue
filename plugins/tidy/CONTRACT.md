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
  error or missing tool the hook exits 0 with no output. **One deliberate
  exception:** the PreToolUse secret floor (§5) blocks a write that carries a
  hardcoded credential. A leaked key is irreversible, so this is the sole place
  tidy hard-stops an edit; the match is prefix-anchored to keep false blocks
  near-zero, and any internal error still degrades to allow.

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
- **Lint dedup:** linter findings are **content-keyed deduped per file per
  session** (a `nudged/lint-*` mark holds a hash of the finding set) — re-editing a
  file with the *same* unfixed/legacy findings stays quiet, but a changed set (new
  issue, or some fixed) re-surfaces, and the mark is cleared when findings go to
  zero so a later reintroduction surfaces again. Avoids re-injecting identical
  "leave pre-existing issues alone" blocks on every edit of the same file.
- **If it changes:** the format/lint-on-touch silently stops.

**Size-check tunables** (both hooks): `CLAUDE_TIDY_SIZE_BUDGET` (lines/file,
default 400) and `CLAUDE_TIDY_SIZE_CHECK=0` to disable the size nudges entirely.

### 5. `PreToolUse` hook payload (stdin) — the secret floor

- **Matcher:** `Edit|Write|MultiEdit`. Script: `bin/tidy-presecret.sh`.
- **Fields read:** `tool_input.file_path` (to skip exempt paths), and the content
  about to be written — `tool_input.content` (Write) / `.new_string` (Edit) /
  `.edits[].new_string` (MultiEdit), joined.
- **Timing:** PreToolUse fires *before* the tool writes, so a hit stops the secret
  from ever reaching disk (this is why it's a Pre, not Post, hook).
- **Output contract:** on a confirmed hit it writes a plain-language reason to
  **stderr and exits 2** (Claude Code's block convention — the reason is fed to the
  model, the write is cancelled). On clean content, disable, exempt path, or any
  error → **exit 0, silent** (the write proceeds). It emits nothing on stdout.
- **What it catches** (`lib/secscan.sh`, pure regex, no external tool so it works in
  a project without gitleaks): prefix-anchored credential shapes — AWS `AKIA…`,
  GitHub `ghp_/gho_/…`/`github_pat_`, Slack `xox…`, Stripe `sk_live_/rk_live_`,
  Google `AIza…`, PEM `BEGIN … PRIVATE KEY` blocks — plus a generic
  long-quoted-literal-after-a-secret-keyword pattern that skips obvious placeholders
  (`your_…`, `example`, `${…}`, `os.environ`, `<…>`, etc.). Secrets only; TLS-off /
  eval / SQL patterns from the source governance spec are intentionally out (fuzzier → would block real
  edits). The reason is **redacted** — it reports the line + kind, never the literal.
- **Exempt paths** (`tidy_secscan_excluded`): `*.md`, and `tests/`/`fixtures/`/
  `testdata/`/`*_test.*`/`*.spec.*`/`*.bats` — docs and fixtures legitimately carry
  secret-shaped strings.
- **Disable:** `CLAUDE_TIDY_SECSCAN=0`. **If the payload shape changes:** the floor
  silently stops blocking (fail-open, like every other tidy step).

### 2. `SessionStart` hook payload (stdin)

- Reads `source` (full standard on `startup`/`clear`/unknown, lean re-anchor on
  `compact`/`resume`) and `cwd` (to resolve the repo root). Emits
  `additionalContext` with `hookEventName: "SessionStart"`.
- **No whole-project debt surfacing here.** SessionStart carries only the
  clean-as-you-go standard; the deliberate prune fires post-turn from the Stop hook
  (§4), and reactive size is covered by the per-touch size nudge (§1).
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
- **Python:** `ruff format` (preferred) / `black` formats `.py` in place
  (behavior-preserving, like gofmt) + `ruff check` surfaces findings — resolved
  project-local (`.venv`/`venv/bin`, walking up) before PATH. **Shell:** `shellcheck -x` for
  `.sh`/`.bash`. Same exit-code contract as web (1 = findings, 0 = clean, 2+ =
  no-op).
- **GDScript (Godot):** `gdformat` formats `.gd` in place (behavior-preserving),
  `gdlint` surfaces findings — both from the `gdtoolkit` pip package, detect-and-run
  (absent → silent). Same exit-code contract for the lint pass. These are the **fast, file-scoped** linters; slow whole-project tools
  (clippy, project-wide mypy) are intentionally left to the verification floor
  (§4) — the fastest loop that can catch a problem owns it. Disable a stack by
  not having its tool installed; `CLAUDE_TIDY_LINT_TIMEOUT` bounds each run.
- The plugin **does not install tools**; it detects them and honors the project's
  own config (e.g. `.golangci.yml`, `eslint.config.js`, `.stylelintrc`,
  `ruff.toml`/`pyproject.toml`, `.shellcheckrc`).
- **Blast-radius:** for a touched *source* file, surface what depends on it so the
  affected surface gets test coverage (deduped per file per session). **Go** uses
  the toolchain's own import graph — `go list -e -f '{{.ImportPath}} {{.Imports}}…'
  ./...` resolves the exact packages that import the touched file's package
  (caught regardless of comments/aliases) and reports `~N package(s) import X`.
  The module scan is **bounded** (`timeout`, default 8s) and **cached per module
  per session** (run at most once; a failure
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
  `decision: block` asking to characterize them. **Bounded** like the test path:
  after `CLAUDE_TIDY_VERIFY_MAX` (default 3) blocks it gives up with a
  `systemMessage` and allows the stop — it can never loop forever. Runs even when
  no test command exists (legacy projects). Off by default — the touch-time nudge
  is the always-on version. Note: it scopes to the **whole dirty tree** (changed
  vs HEAD), not just files touched this session, so pre-existing uncommitted
  untested files also trip it — another reason it's opt-in.

- **Quality floor (always-on, same Stop hook):** before the test run, it enforces
  the project's OWN declared quality gates beyond its test command — `tidy_quality_commands`
  discovers package.json scripts named `typecheck`/`type-check`/`tsc`, `a11y`/`lighthouse`/
  `lhci`, `depcruise`/`dependency-cruiser`/`arch`/`boundaries` (run via the lockfile's
  package manager) — and blocks until each passes, **bounded** like the test floor
  (`$qfile` counter → give-up `systemMessage` after `CLAUDE_TIDY_VERIFY_MAX`; timeouts
  don't loop). Detect-and-run only: it installs/invents nothing and runs nothing the
  project didn't wire up; heavy Lighthouse/CWV audits stay in CI. `CLAUDE_TIDY_QUALITY_CMD`
  overrides with a single synthetic gate; `CLAUDE_TIDY_QUALITY_FLOOR=0` disables. It
  runs after the throttle, so a stored green hash means quality **and** tests passed.
- **Regression gate (OPT-IN, same Stop hook):** when enabled, before the test run it
  blocks when a changed file is BOTH a **scar-tissue hotspot** (repeatedly fixed — by the
  git rework ratio) AND **untested** (`tidy_untested_hotspots` = `tidy_untested_changed`
  ∩ `tidy_hotspots`). This is the coverage ratchet *scoped to the files that have earned
  it*. **OFF by default — tests are the owner's call (support TDD, don't force it);** opt
  in with `CLAUDE_TIDY_REGRESSION_GATE=1` for the safety net on proven debt-magnets, and
  it goes quiet the moment a test lands. **Reads git history:** `git log -n 300 --no-merges --pretty=format:':C:%s'
  --name-only`, classifying a commit as rework when its subject word-matches
  `fix|bugfix|hotfix|bug|revert|undo|rollback|regression|rework` and flagging a file
  at rework-ratio ≥ 0.34 with ≥ 2 reworks (existing files only). **Bounded** like the
  test path (`CLAUDE_TIDY_VERIFY_MAX` blocks → `systemMessage`, never loops). Disable
  Enable with `CLAUDE_TIDY_REGRESSION_GATE=1`; stands down when the broad ratchet is forcing.
  **Limit:** existence-based like the ratchet — a hotspot that already has *any* test
  passes, even if the test doesn't cover the new change.
- **Drift guard for the hotspot mirror:** `tidy_hotspots` is a hand copy of
  `charter_hotspots` (the install boundary forbids a shared lib). `tests/drift-guard.bats`
  asserts the two produce **byte-identical** output, so CI fails if charter's
  detector changes and tidy's mirror doesn't. If `charter_hotspots` changes,
  update `tidy_hotspots` in lockstep.

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

#### The deliberate prune (automatic Stop hook + on-demand `/tidy:audit`)

The deliberate prune fires **automatically** from `bin/tidy-verify.sh` (Stop),
**after** the turn's work, gated on a debt threshold. It runs only when the tree is
dirty *and* the verification floor passed clean, so it never derails the user's
intent (the old SessionStart trigger fired before intent was known and re-injected a
big report every session):

- It checks how many files are over the size budget. **At/above**
  `CLAUDE_TIDY_PRUNE_THRESHOLD` (default 3) it runs `bin/tidy-distill.sh` and emits
  the full weight report plus an instruction to **run a subtractive prune NOW**
  (dead code, duplication, doc↔code drift) as a **non-blocking `systemMessage`** —
  no command to invoke. The cuts are routed through the task-queue
  interpret→present→approve loop. (There is no sub-threshold "light distill" list;
  the per-touch size nudge in §1 covers reactive size.)
- **Throttled once per debt episode:** a flag file under the state dir suppresses
  re-firing while debt persists; it re-fires only after the over-budget count drops
  below the threshold and later re-crosses it. So it won't nag turn after turn.
- **`bin/tidy-distill.sh`** is the **read-only**, language-agnostic report
  generator: it enumerates files with `git ls-files --cached --others
  --exclude-standard` (fallback `find`) and reports file/line counts, the heaviest
  + over-budget files, cruft markers, and junk artefacts. Tunables:
  `CLAUDE_TIDY_SIZE_BUDGET` (default 400); lists the 10 heaviest files.
  It never writes and never hard-fails. The *judgment* (what to actually delete)
  is the model's, gated on confirmation.
- **On-demand: `commands/audit.md` (`/tidy:audit`)** runs the same
  `bin/tidy-distill.sh` report for the case the automatic firing can't reach — a
  deliberate whole-project audit on a clean tree or below threshold. Because the owner
  invoked it explicitly, it **auto-queues** every finding as a `TaskCreate` cleanup task
  (smallest blast-radius first) instead of routing through the per-item approve loop; the
  only exception is a finding with an obvious risk (uncertain-dead-code deletion,
  high-blast-radius restructure, irreversible/ambiguous), which is PARKED as `❓` for the
  owner. This is why the prune is no longer "no command to invoke" — the auto path stays
  default, the command is the discoverable on-demand trigger (see docs/ROADMAP.md,
  2026-07-07).

## Where the plugin writes

- **Your source files** — formatter output, in place, for the touched file only.
- **State dir** — `~/.claude/state/tidy/` (override `CLAUDE_TIDY_LOG_DIR` — the
  env name is historical; `tidy_log_dir()` returns this functional **state** dir).
  No activity log is written; the dir only holds the dedup/verify state below.
- **TDD-nudge markers** — empty files under `~/.claude/state/tidy/nudged/`
  (one per session+file) so the test nudge fires at most once per file per
  session. The same dir also holds `lint-*` marks (a hash of the last-surfaced
  finding set per file+session, for the lint dedup above). Safe to delete anytime.
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
- **`tests/verify.bats`** drives the Stop hook over temp git repos — the test
  floor (block-until-green, timeout, throttle, attempt cap), the debt/prune surface,
  and the **regression gate** (blocks an untested scar-tissue hotspot, silent on a
  non-hotspot, quiet once a test lands, bounded, disable switch, and standing down
  under the broad ratchet).
- **`tests/secscan.bats`** drives the PreToolUse secret floor — blocks
  (exit 2) on runtime-assembled AWS-key/PEM/generic-credential shapes, stays silent
  (exit 0) on ordinary code / placeholders / env-var refs / exempt paths, honors the
  disable switch, scans MultiEdit, and never echoes the raw secret back.
- **`tests/drift-guard.bats`** asserts `tidy_hotspots` is byte-identical to
  `charter_hotspots` (the cross-plugin mirror guard).
- The real toolchain boundary is exercised by using the plugin on an actual Go
  project.
