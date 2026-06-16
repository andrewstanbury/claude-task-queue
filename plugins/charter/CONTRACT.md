# CONTRACT — what the charter plugin depends on

`charter` reads a SessionStart hook payload and inspects the project's files. It
is **read-only over your project** — it never writes your files. Action-time
consent for consequential/irreversible operations is handled **natively** by
Claude Code permissions (the user's `~/.claude/settings.json`), not by a charter
hook; charter's SessionStart brief only carries the plain-language owner-loop
consent *posture* (intent → demo → consent). The Claude Code internals below are
observed behaviour, not documented APIs.

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

### 1b. Action-time consent is native (not a charter hook)

- charter has **no `PreToolUse` hook**; `hooks/hooks.json` wires only
  `SessionStart`. Consent for consequential/irreversible operations is enforced
  by Claude Code's own permissions: the user's `~/.claude/settings.json` sets
  `permissions.defaultMode="auto"` (auto-approve with background safety checks),
  plus a **deny** set (`rm -rf` of `/`, `~`) and an **ask** set (`git push
  --force`, `git reset --hard`).
- charter's SessionStart brief still carries the plain-language owner-loop consent
  *posture* (intent → demo → consent) so the model surfaces consequential work to
  a non-technical owner — but that is brief text, not an enforcement hook.

### 2. The project's own files (read-only)

- **Quality-attributes doc:** one of `QUALITY.md`, `docs/QUALITY.md`,
  `docs/quality-attributes.md`, `QUALITY.adoc`, or a *quality attribute* /
  *non-functional* / *NFR* mention in `CLAUDE.md` / `AGENTS.md` / `docs/CLAUDE.md`
  / `README.md`. Override via `CLAUDE_CHARTER_QA_FILE`. (ADRs are **not** counted
  here — they're decisions, a separate dimension below.)
- **Decisions record:** `DECISIONS.md`, `docs/DECISIONS.md`, or any file under
  `docs/adr/`, `docs/adrs/`, `docs/decisions/`. Override via
  `CLAUDE_CHARTER_DECISIONS_FILE`. Present → consult-before-reversing reminder;
  missing → a nudge to capture key decisions (so past choices aren't re-litigated).
- **Stack notes:** `STACK.md`, `docs/STACK.md`, or a `## Stack` / `## Tech stack`
  heading in `CLAUDE.md` / `AGENTS.md` / `README.md`. Override via
  `CLAUDE_CHARTER_STACK_FILE`. Present → consult; missing → capture
  languages/frameworks/versions (durable context for currency/modernization).
- **Established conventions** (`lib/conventions.sh`): inferred read-only from
  `package.json` deps + a few config files/dirs — UI/component library
  (`components.json` → shadcn, `@mui/material`, `@chakra-ui/react`, `antd`, …),
  styling (`tailwind.config.*`/`tailwindcss`, styled-components, …), state
  (Redux/Zustand/Jotai/…), a components dir (`src/components`/…), and test
  framework. Surfaced with a *reuse-before-create* framing until recorded (a
  `## Conventions` section in the map/manual/`DECISIONS.md`, or `CONVENTIONS.md`),
  then quiet. Silent when nothing is detected (non-web / not enough signal).
- **Policy marker:** the `claude-companion` token in `CLAUDE.md` / `AGENTS.md` /
  `docs/CLAUDE.md`. When present, charter drops its recurring *honor/consult*
  reminders (the manual is always loaded) and emits only the drift nudges for
  genuinely-missing docs — going fully silent when everything is present + marked.
- **Web-project detection:** a web framework dep in `package.json` (react/vue/
  svelte/preact/solid/astro/next/nuxt/gatsby/lit/vite/angular/remix), an
  `index.html`, or a known web config (`next.config.*`, `vite.config.*`, …).
  Force on/off via `CLAUDE_CHARTER_WEB=1|0`. When web + QA undocumented, the
  nudge seeds Lighthouse-aligned defaults (CWV, WCAG AA, print CSS, progressive
  enhancement, components-by-default) so best practices are designed-in rather
  than audited after.
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
- **Recent history (read-only):** when a roadmap is present, `git log --no-merges
  --format=%s -n 5` supplies recently-merged subjects next to the reconcile
  reminder. A repo with no commits (git log exits 128) degrades to silence.

### 3. The `/charter:align` command (user-invoked)

- **Files:** `commands/align.md` (auto-discovered, namespaced `/charter:align`)
  inlines the stdout of `bin/charter-align.sh` via the `!` prefix, then instructs
  the model to reconcile open/proposed work against the recorded direction.
- **`bin/charter-align.sh`** is **read-only**: it prints the alignment anchors —
  the decisions/ADR path, the roadmap/backlog path, and the recently-landed
  commits (`git log --no-merges -n 8`) — using the same `lib/charter.sh`
  detectors as the hook. It never writes and never hard-fails (a bare repo prints
  "no anchors to check against" and exits 0). The reconciliation/judgment is the
  model's; the script only supplies facts.
- **Depends on:** Claude Code's plugin slash-command mechanism (`commands/*.md`
  auto-discovery, the `!` command-output prefix, `${CLAUDE_PLUGIN_ROOT}`). If
  that changes, the command stops working but the hook is unaffected.

## Where the plugin writes

charter writes **nothing** — not to your project, not to Claude Code's state, not
to any log. It only reads files and emits SessionStart `additionalContext`.

## How this is verified

- `tests/charter.bats` fakes a project via a temp git repo and `CLAUDE_CHARTER_*`
  overrides — QA-, roadmap-, and map-status detection, the full/lean nudge by
  source, the owner-loop posture, and `/charter:align`'s anchor output
  (no-anchor, decisions, roadmap, and recent-commit cases).

## Status (see docs/ROADMAP.md)

Shipped: the quality-attributes gate, roadmap/backlog awareness, the project map,
recorded-decisions anchor, stack notes, the owner-loop consent posture, and
`/charter:align`. Action-time consent is now **native** (Claude Code permissions
in settings.json), not a charter hook. The subtractive/prune force lives in
**tidy** (its automatic prune + the size guard); hooks are already
**bootstrap-once + drift-detect** (they go quiet once the policy is recorded in
CLAUDE.md). Further work is demand-driven, not a planned phase.
