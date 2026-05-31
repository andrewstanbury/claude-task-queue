# AGENTS.md — maintainer guide

This repository is **maintained by AI agents**, not a hands-on human team. It's
deliberately optimized for that: committed docs over tribal knowledge,
deterministic checks over conventions, hermetic tests over manual QA. **Read
this file first** — it's the single source of truth for how the repo is built.

## What this is

A small **marketplace of self-contained Claude Code companion plugins**:

- **`plugins/task-queue/`** — makes Claude Code's native task list a live work
  queue: a SessionStart policy + cross-session resume bridge + auto-advance to
  the next unblocked task + a per-repo pause + a *conditional* (silent-unless-
  needed) UserPromptSubmit capture nudge. **Read-only** over `~/.claude/tasks`.
- **`plugins/tidy/`** — *tidy-as-you-touch*: formats and lint-checks the file you
  just edited (fixing only what's safe) so a project converges toward clean code
  over time, scoped to the touched file.
- **`plugins/charter/`** — *know the project*: gates substantive work on
  documented quality attributes (nudges to capture them if missing) and keeps the
  project's Claude manual in view. Read-only over the project.

Each plugin has its own `README.md` (what/why) and `CONTRACT.md` (the
**undocumented Claude Code internals it depends on** — read it before changing
any hook input/output). The system's direction (the 3-plugin vision and phased
plan) lives in [docs/ROADMAP.md](./docs/ROADMAP.md).

## The one rule that drives the architecture: the install boundary

**Claude Code installs each plugin independently — at runtime only that plugin's
own subdirectory exists** (reachable via `${CLAUDE_PLUGIN_ROOT}`). Therefore:

- **Every plugin must be fully self-contained.** It may only reference files
  inside its own `plugins/<name>/`.
- **Do NOT extract a cross-plugin shared library, and do NOT add a build step**
  to de-duplicate. The small repeated bits (the symlink-resolve preamble in each
  `bin/` script, the `*_log` helper, the `hookSpecificOutput` JSON emission) are
  duplicated **on purpose** — that's the price of independent installability.
  Trying to DRY them across plugins would break standalone installs.

## Layout

```
.claude-plugin/marketplace.json   # lists every plugin (name, source, version)
.github/workflows/ci.yml          # provisions tools, then runs ./check.sh
check.sh                          # single source of truth for "what we check"
.editorconfig
AGENTS.md  CLAUDE.md  LICENSE  README.md
plugins/<name>/
  .claude-plugin/plugin.json      # version MUST equal the marketplace entry
  hooks/hooks.json                # wires the hooks
  bin/*.sh                        # thin entrypoints: parse stdin, emit JSON
  lib/*.sh                        # the logic
  tests/*.bats                    # hermetic; fake state via CLAUDE_*_DIR overrides
  README.md  CONTRACT.md  CHANGELOG.md
```

## Conventions (mirror these in any new plugin)

- **Bash + `jq`, zero build.** No compiled languages, nothing to install to run
  a hook. (This is why the plugins are Bash, not Go — a compiled hook needs
  per-platform binaries or a toolchain, which breaks "runs everywhere, no build".)
- **Hooks are best-effort and must NEVER break the action that triggered them.**
  `set -uo pipefail`, swallow tool errors, exit 0 when there's nothing to say.
- **Invariants, per plugin:** task-queue is **read-only** over `~/.claude/tasks`
  (it reads, or nudges the model — it never writes the task store); tidy
  **only auto-applies behavior-preserving fixes** (formatting) and surfaces
  everything else.
- **Locations are env-overridable** (`CLAUDE_TQ_*`, `CLAUDE_TIDY_*`) so tests are
  hermetic — temp dirs, no mocking framework.
- **Prefer locality over decomposition.** A file an agent can load whole beats
  many fragments it must chase. Keep files cohesive; the CI **300-line guard** is
  the trigger to split — split only when it actually fires.
- **Zero per-prompt cost.** Work happens on events (SessionStart / Task* /
  PostToolUse), never on every prompt.

## Verify

```bash
./check.sh    # JSON validity, shellcheck, gitleaks, size guard, every bats suite
```

`check.sh` skips tools you don't have locally (with a note) and is **authoritative
in CI**: `.github/workflows/ci.yml` installs every tool and runs the same script,
so green locally means green in CI (modulo locally-skipped tools).

## Add a plugin

1. Copy an existing plugin's structure into `plugins/<name>/`.
2. Mirror the conventions above; include `README.md`, `CONTRACT.md`, and tests.
3. Add an entry to `.claude-plugin/marketplace.json` (`"source": "./plugins/<name>"`).
4. Keep `plugin.json` version **equal to** the marketplace entry (a packaging
   test enforces it).
5. `./check.sh` must pass.

## Release a plugin

Bump `plugins/<name>/.claude-plugin/plugin.json` **and** its marketplace entry
(they must match — enforced), update that plugin's `CHANGELOG.md`, then tag.

## Don't

- Don't add a cross-plugin shared lib or a build step (install boundary).
- Don't add anything that runs per prompt.
- Don't re-introduce the heavyweight features the project deliberately dropped
  (a bespoke task store, Haiku auto-decompose, autopilot, a destructive-action
  gate, a CLI, a status bar). The project's whole arc was *removing* these — see
  `plugins/task-queue/CHANGELOG.md` for the why.
- Don't decompose preemptively; let the 300-line guard decide.
