# CONTRACT — what the charter plugin depends on

`charter` reads `SessionStart` and `Stop` hook payloads and inspects the project's
files. It is **read-only over your project** — it never writes your files (its one
write is cache-only throttle state outside the project; see *Where the plugin
writes*). Action-time
consent for consequential/irreversible operations is handled **natively** by
Claude Code permissions (the user's `~/.claude/settings.json`), not by a charter
hook; charter's SessionStart brief only carries the plain-language owner-loop
consent *posture* (intent → demo → consent). The Claude Code internals below are
observed behaviour, not documented APIs.

> **Observed against:** Claude Code 2.x · last verified **2026-06-16**.

## Dependencies

### 1. `SessionStart` hook payload (stdin)

- **Fields read:** `cwd` (resolved to the repo root) and `source` (selects the
  full quality-attributes nudge on `startup`/`clear`/unknown vs. a lean
  re-anchor on `compact`/`resume`).
- **Output contract:** `{ "hookSpecificOutput": { "hookEventName":
  "SessionStart", "additionalContext": "<text>" } }`. Emitted when there's
  something to say; silent when QA is documented and the source is compact/resume.
- **If it changes:** the quality-attributes gate silently stops.

### 1c. `SessionStart` hook — the MCP reachability probe

- **Script:** `bin/charter-mcp-probe.sh` (+ `lib/mcp-probe.sh`), wired as a second
  `SessionStart` hook alongside the brief. **Fields read:** `cwd` (resolved to the
  repo root) and `source` (probes only on `startup`/`clear`/unknown — **never** on
  `compact`/`resume`, since it spawns processes).
- **What it reads (read-only):** the MCP servers DECLARED for this repo, merged from
  `~/.claude.json` (top-level `.mcpServers` **and** `.projects[<root>].mcpServers`;
  override the path with `CLAUDE_MCP_HOME_CONFIG`), `<root>/.mcp.json`, and
  `<root>/.claude/settings.json` + `settings.local.json` — each file's `.mcpServers`
  object. Server-config shapes understood: stdio (`command` + `args` + `env`) and
  remote (`type: http|sse|streamable-http|ws` + `url` + `headers`).
- **How it probes (bounded):** each server in parallel, hard-capped at
  `CLAUDE_CHARTER_MCP_TIMEOUT` seconds each (default 3) and `CLAUDE_CHARTER_MCP_MAX`
  servers (default 25). stdio → spawn under `timeout` and send the MCP `initialize`
  handshake (a JSON-RPC `result`/`error` reply = reachable); skipped silently when
  `timeout` is unavailable. http/sse → POST `initialize` via `curl --max-time` (any
  HTTP status, **incl. 401/403**, = reachable; only a connection failure is "down");
  skipped silently when `curl` is absent.
- **Output contract:** `{ "hookSpecificOutput": { "hookEventName": "SessionStart",
  "additionalContext": "<plain-language warning naming the dead servers>" } }` when
  one or more declared servers don't respond; **silent (exit 0)** when all respond,
  none are declared, the source is compact/resume, or the probe is disabled. Never
  blocks; any internal error degrades to silence. Disable with
  `CLAUDE_CHARTER_MCP_PROBE=0`.
- **Why:** silent tool-unavailability (a mis-installed/unreachable server whose tools
  just never appear) is invisible to a non-technical owner — the probe surfaces it.
- **If it changes** (the config locations or server-config shape): the probe silently
  stops (best-effort; it never breaks session start).

### 1a. `Stop` hook payload (stdin) — the alignment floor

- **Script:** `bin/charter-align-gate.sh`. **Fields read:** `cwd` (resolved to the
  repo root) and `session_id` (namespaces the throttle state).
- **Fires only when** the working tree is dirty (a real change landed), the project
  records decisions (`charter_decisions_path`), and the change plausibly bears on a
  decision per the cheap pre-filter (`charter_change_touches_decisions`: a
  decision-bearing surface — dependency manifest / lockfile / config / Dockerfile /
  `*.tf` / migrations / schema / `*.sql` — changed, **or** a backtick-fenced token
  from the decisions doc appears in the tracked diff or a new file). Otherwise silent.
- **Output contract:** `{ "decision": "block", "reason": "<recorded decisions + an
  instruction to honor-or-surface>" }` on the first qualifying change for a given
  working-tree fingerprint; a non-blocking `{ "systemMessage": … }` once the
  per-session attempt cap is reached; silent (exit 0) otherwise.
- **Bounding (cannot loop):** a tree-hash fingerprint (`charter_tree_hash`) so the
  same change is never re-blocked, plus at most `CLAUDE_CHARTER_ALIGN_MAX` (default
  2) blocks per session. Disable entirely with `CLAUDE_CHARTER_ALIGN_GATE=0`.
- **Semantic judgment is the model's**, never the hook's — the hook only guarantees
  the recorded decisions are in front of the model at the moment of "done".
- **If it changes:** the alignment floor silently stops (best-effort: any internal
  error degrades to "allow the stop", so it never breaks the turn).

### 1b. Action-time consent is native (not a charter hook)

- charter has **no `PreToolUse` hook**; `hooks/hooks.json` wires `SessionStart`
  (the brief) and `Stop` (the alignment floor). Consent for consequential/
  irreversible operations is enforced
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
  languages/frameworks/versions (durable context for the model's own judgment).
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
- **Outcome memory / scar tissue** (`charter_hotspots`): `git log -n 300 --no-merges
  --pretty=format:':C:%s' --name-only` over the repo root. A commit counts as
  *rework* when its subject word-matches `fix|bugfix|hotfix|bug|revert|undo|rollback|
  regression|rework`; a file is flagged when its rework ratio (rework ÷ total commits
  touching it) is ≥ 0.34 with ≥ 2 reworks, and the file still exists on disk. Prints
  `<fixes>\t<changes>\t<path>`, most-reworked first, bounded to 5 by default. Read-only;
  silent outside a git repo, on a bare repo, or with no rework signal. **If the commit
  format / `--name-only` output changes,** the scar-tissue surfacing silently stops.

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

charter writes **nothing to your project**. Its only write is **cache-only throttle
state** for the alignment floor — the working-tree fingerprint and the per-session
block counter — under `$HOME/.claude/state/charter` (override with
`CLAUDE_CHARTER_LOG_DIR`), the same cache footprint tidy already has. This dir must
live **outside** any project repo (the default does); if it were placed inside a
repo, the gate's own writes would dirty that repo's tree. The MCP probe's only write
is a **transient `mktemp -d` scratch dir** (per-server probe output, removed before
the hook returns) under the system temp dir — never the project. Everything else is
reads + `SessionStart` `additionalContext` and `Stop` decisions.

## How this is verified

- `tests/charter.bats` fakes a project via a temp git repo and `CLAUDE_CHARTER_*`
  overrides — QA-, roadmap-, and map-status detection, the full/lean nudge by
  source, the owner-loop posture, `/charter:align`'s anchor output (no-anchor,
  decisions, roadmap, and recent-commit cases), outcome memory (rework vs.
  healthy churn, the word-boundary guard, silence on no-rework / non-git, and the
  SessionStart scar-tissue surfacing), and the alignment floor (blocks on a
  decision-bearing change, silent on routine edits / no-decisions / clean tree,
  fenced-token overlap on new files, the per-tree throttle, the disable switch,
  and the attempt cap).
- `tests/mcp-probe.bats` fakes MCP servers with stub commands on `PATH` and a
  controlled config — silence when none declared, a healthy stdio server not
  flagged, the three down-states (command missing, starts-but-mute, http endpoint
  unreachable), an HTTP auth challenge counted as reachable, discovery from the
  `~/.claude.json` project-scoped block, the compact/resume skip, and the disable
  switch. The token budget for the probe (silent at rest, bounded when warning)
  is enforced in `tests/token-budget.bats`.

## Status (see docs/ROADMAP.md)

Shipped: the quality-attributes gate, roadmap/backlog awareness, the project map,
recorded-decisions anchor, stack notes, the owner-loop consent posture, outcome
memory (the git rework-ratio scar-tissue surfacing), the Stop-time alignment floor
(decision-reversal gate), `/charter:align`, and the SessionStart MCP reachability
probe. Action-time consent is now **native** (Claude Code permissions
in settings.json), not a charter hook. The subtractive/prune force lives in
**tidy** (its automatic prune + the size guard); hooks are already
**bootstrap-once + drift-detect** (they go quiet once the policy is recorded in
CLAUDE.md). Further work is demand-driven, not a planned phase.
