# AGENTS.md — maintainer guide

This repository is **maintained by AI agents**, not a hands-on human team: committed docs
over tribal knowledge, deterministic checks over conventions, hermetic tests over manual QA.
**Read this first.**

## What this is

One Claude Code plugin — **`plugins/companion/`** — built on a single principle (ledger
**R24**):

> **Steering is a document. Enforcement is code. Never confuse the two.**

- **Steering** — `plugins/companion/STEERING.md`. All the prose that shapes how Claude works
  (queue discipline, the brutal-honest recommendation posture against the requirements
  ledger, clean-as-you-go, autopilot). It is *advisory by nature* — the model reads it and
  follows it by judgment. It lives in **one file**, put in context once per session by the
  SessionStart hook. It is **not** unit-testable, and pretending it was is the mistake the
  old four-plugin system made.
- **Enforced core** — `plugins/companion/bin/`. The only behavior that *must execute or
  block*, and therefore has to be code:
  - `secret-guard.sh` — PreToolUse[Write|Edit]: blocks a write that would commit a
    credential (`exit 2`). The one real content-gate.
  - `session-start.sh` — SessionStart: injects STEERING + re-surfaces this repo's open tasks
    from an earlier session (repo-scoped resume).
  - `tq` — task-queue fallback CLI for models with the native task tools gated off.

That's the whole system. (It replaced a four-plugin, ~12,500-line prompt-injection framework
on 2026-07-11 — see the git history and ledger R24.)

## The rule that drives the architecture

**When you want to change behavior, ask: does this need to *execute or block*?**

- **No** → it's steering. Edit `STEERING.md`. Do **not** add a hook that just injects prose —
  that's how the old system sprawled to 15 hooks and a token-budget NFR to police them.
- **Yes** → it's a small, testable script in `bin/`, wired in `hooks/hooks.json`, with a test
  in `tests/companion.bats` and an env kill-switch.

Be honest about which is which. A nudge dressed up as a guarantee (the old "solo paused
anyway" bug) is the failure mode this architecture exists to prevent.

## Source of truth

**Durable requirements/decisions live in [docs/REQUIREMENTS.md](./docs/REQUIREMENTS.md)** —
the ledger, with status (🔒 locked / 🔓 open / ⚰️ retired). CLAUDE.md and ROADMAP reference it
by R-ID. Reverse one *there*, as a visible trade-off, never silently.

## Layout

```
.claude-plugin/marketplace.json   # the one companion plugin (name, source, version)
.github/workflows/ci.yml          # runs ./check.sh on push
check.sh                          # single source of truth for "what we check"
CLAUDE.md  AGENTS.md  README.md    # this file = maintainer SSOT; README = discoverability
docs/REQUIREMENTS.md  docs/ROADMAP.md  docs/MAP.md
plugins/companion/
  .claude-plugin/plugin.json       # version == the marketplace entry
  hooks/hooks.json                 # SessionStart · PreToolUse[Write|Edit,AskUserQuestion] · PostToolUse · Stop
  STEERING.md                      # the steering layer (prose)
  bin/session-start.sh secret-guard.sh touch.sh statusline.sh tq
  bin/autopilot.sh ask-guard.sh stop-autopilot.sh   # enforced autopilot (R26)
  lib/autopilot.sh                 # shared autopilot-flag helpers (one plugin → a lib is fine)
  commands/{setup,audit,autopilot}.md
  tests/companion.bats             # tests the ENFORCED CORE only
```

(`touch.sh` is a legit hook, not "prose-only": it *executes* — formats the edited file — with
blast-radius/size as attached nudges. That's the line: it does something, so it's code.)

## Conventions

- **Bash + `jq`, zero build.** No compiled languages, nothing to install to run a hook.
- **Hooks are best-effort and must NEVER break the action that triggered them** (`set -uo
  pipefail`, swallow errors, exit 0 when silent).
- **Generic — no hardcoded language/framework allowlists** (R9). Delegate *recognition* to
  the model; detect *structure* generically. Wide-audience product (R1).
- **Files ≤ 300 lines** (CI guard); env-overridable locations (`CLAUDE_COMPANION_*`) so tests
  are hermetic.

## Verify

```bash
./check.sh    # JSON validity · claude plugin validate · shellcheck · gitleaks · size · bats
```

`check.sh` skips locally-missing tools (with a note) and is authoritative in CI.

## Workflow

Change → `./check.sh` → commit. `plugin.json` version and the marketplace entry must match;
bump only when meaningful.

## Don't

- **Don't add a hook that only injects prose.** If it doesn't execute or block, it belongs in
  `STEERING.md`.
- **Don't re-introduce the scattered-middleware pattern** the rebuild removed: per-hook token
  budgets, mirrored detectors, drift-guards, or a plugin that forces work it can't reliably
  own. Git history has the details; the ledger has the reasons (R24).
- **Don't decompose preemptively** — let the 300-line guard decide.
