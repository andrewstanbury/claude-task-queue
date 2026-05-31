# CONTRACT — what the charter plugin depends on

`charter` reads a SessionStart hook payload and inspects the project's files.
It is **read-only over your project** — it never writes your files. The Claude
Code internals below are observed behaviour, not documented APIs.

> **Observed against:** Claude Code 2.x · last verified **2026-05-31**.

## Dependencies

### 1. `SessionStart` hook payload (stdin)

- **Fields read:** `cwd` (resolved to the repo root) and `source` (selects the
  full quality-attributes nudge on `startup`/`clear`/unknown vs. a lean
  re-anchor on `compact`/`resume`).
- **Output contract:** `{ "hookSpecificOutput": { "hookEventName":
  "SessionStart", "additionalContext": "<text>" } }`. Emitted when there's
  something to say; silent when QA is documented and the source is compact/resume.
- **If it changes:** the quality-attributes gate silently stops.

### 2. The project's own files (read-only)

- **Quality-attributes doc:** one of `QUALITY.md`, `docs/QUALITY.md`,
  `docs/quality-attributes.md`, `QUALITY.adoc`, an ADR under `docs/adr/` or
  `docs/adrs/`, or a *quality attribute* / *non-functional* / *NFR* mention in
  `CLAUDE.md` / `AGENTS.md` / `docs/CLAUDE.md` / `README.md`. Override via
  `CLAUDE_CHARTER_QA_FILE`.
- **Roadmap/backlog file:** one of `docs/ROADMAP.md`, `ROADMAP.md`,
  `docs/BACKLOG.md`, `BACKLOG.md`. Override via `CLAUDE_CHARTER_ROADMAP_FILE`.
  This is the committed, Claude-facing record of what's-next — the coordination
  point across sessions and across engineers on separate machines (git history
  of the file is the shared audit trail). **Detect, not author:** when it's
  missing the hook *instructs the model to generate it* from git history + the
  codebase; the hook itself still writes nothing to your project.
- **Project map:** one of `docs/MAP.md`, `MAP.md`, `docs/ARCHITECTURE.md`,
  `ARCHITECTURE.md` (recognises the common `ARCHITECTURE.md` convention so an
  existing map isn't re-nagged). Override via `CLAUDE_CHARTER_MAP_FILE`. A
  compact `file → responsibility` index + entry points so a session orients from
  the map instead of re-scanning the tree. Same **detect-not-author** boundary:
  missing → the hook instructs the model to generate it from the codebase. The
  orientation nudge points at this map (it replaces the old generic "record
  learnings in CLAUDE.md" line, keeping SessionStart from growing).
- **Repo root:** resolved with `git rev-parse --show-toplevel`, falling back to
  walking for `.git`, then the cwd. (Self-contained — charter does not depend on
  any other plugin; see AGENTS.md on the install boundary.)

## Where the plugin writes

- **Activity log** — `~/.claude/state/charter/activity.log` (override
  `CLAUDE_CHARTER_LOG_DIR`, disable `CLAUDE_CHARTER_LOG_DISABLED`). Best-effort,
  append-only; never blocks a hook. A fixed home so `charter-doctor`, run by
  hand, reads the same file the hook writes.

It writes **nothing** to your project and nothing to Claude Code's state.

## How this is verified

- `tests/charter.bats` fakes a project via a temp git repo and `CLAUDE_CHARTER_*`
  overrides — QA-, roadmap-, and map-status detection, the full/lean nudge by
  source, and the doctor.
- `bin/charter-doctor.sh` checks the same against a live project on demand.

## Not yet (see docs/ROADMAP.md)

A **subtractive/prune force** (dead-code, duplication, size-vs-complexity) and
shifting hooks from per-session re-injection toward *bootstrap-once +
drift-detect* are the next direction. Shipped so far: the quality-attributes
gate, the roadmap/backlog awareness, and the project map (orientation).
