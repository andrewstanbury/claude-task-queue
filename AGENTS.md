# AGENTS.md — maintainer guide

This repository is **maintained by AI agents**, not a hands-on human team: committed docs
over tribal knowledge, deterministic checks over conventions, hermetic tests over manual QA.
**Read this first.**

## What this is

One Claude Code plugin — **`plugins/companion/`** — undergoing a redesign in progress (ledger
**R100**): from "steering document + tiny enforced core" (R24) to "steering document + a
portable MCP core + one remaining hook," traded deliberately for portability to other
MCP-capable clients (Cursor, etc.) at the cost of the enforcement guarantees R24/R28 built.
R100 lands in bounded passes, tracked in `tq` itself — see
[docs/adr/README.md](./docs/adr/README.md) R100 for the full shape and the honest cost.

> **R24 (superseded by R100):** Steering is a document. Enforcement is code. Never confuse the two.
> **R100:** Steering is a document, always advisory. The core is portable data + tools (`tq`,
> the MCP server), always advisory. Only one hook is left, because only one thing left needs to
> *read state a session can't see* — nothing left needs to *block* or *guarantee control-flow*.

- **Steering** — `plugins/companion/STEERING.md`. All the prose that shapes how Claude works
  (queue discipline, the brutal-honest recommendation posture against the requirements
  ledger, clean-as-you-go, autopilot). Advisory by nature — the model reads it and follows it
  by judgment. **Injected automatically at session start again** (R100/Pass 6, docs/adr/README.md
  R105, reversing Pass 2's retirement of the SessionStart hook) — `/companion:resume` also still
  prints it on demand mid-session.
- **The portable core** — `plugins/companion/bin/` + `mcp-server/`:
  - `tq` — the task-queue CLI the companion owns (native tasks deliberately unused; R8/R10) —
    also reachable via the `companion-tq` MCP server (`mcp-server/index.js`) for any MCP-capable
    client, not just Claude Code (R100/Pass 1).
  - `check-secrets.sh` — the same credential-shape classification `secret-guard.sh` used to
    enforce, now advisory only: nothing calls it automatically, nothing it returns can block a
    write (R100/Pass 3). Also exposed as the MCP tool `check_for_secrets`.
  - `resume.sh` — the on-demand, triage-and-pull twin of `session-start.sh` (below): same content
    (via shared `lib/resume-report.sh`), plus it disarms autopilot as part of pulling context,
    which the automatic hook deliberately does not.
  - `ship-checkpoint.sh` — ship-mode's commit-to-`autopilot/*`-branch logic, byte-for-byte the
    same as the retired Stop hook's version, still manually invoked (not reinstated).
  - `autopilot.sh` — toggles a persisted per-repo preference flag. **"Don't stop to ask" is
    enforced again** (`ask-guard.sh`, R100/Pass 6) — **"keep going instead of stopping" is not**
    (`stop-autopilot.sh` stays retired, still the biggest R100 fidelity loss).
  - `statusline.sh` — the glance surface (a `statusLine` command, not a hook; untouched by R100).
- **Three hooks** — `prompt-continue.sh` (UserPromptSubmit, never retired): routes a bare
  "continue" to the parked-pile review first, when one exists. `session-start.sh` (SessionStart,
  **reinstated** R100/Pass 6): guarantees STEERING + carried tasks reach a session automatically —
  the owner's fix for a model ignoring context it never actually had. `ask-guard.sh`
  (PreToolUse[AskUserQuestion], **reinstated** R100/Pass 6): denies + auto-parks a question while
  autopilot is armed. See docs/adr/README.md R104 (why no Cursor equivalent exists for
  prompt-continue.sh) and R105 (why these two came back, and stop-autopilot.sh did not).

That's the whole system. (Replaced a four-plugin, ~12,500-line prompt-injection framework on
2026-07-11 — R24 — realigned to the execute-or-block rule as R28, refined through R29–R99, then
R100 (2026-08-08) retired the enforced core itself in favor of the shape above — see git history
and the ledger for the arc.)

## The rule that drives the architecture now

**Everything is advisory. The only question left is: does this need to read state a session
genuinely cannot see on its own?**

- **No** (almost everything) → it's a plain CLI in `bin/`, optionally also exposed as an MCP
  tool if a portable client would want it. No hook, no enforcement — STEERING states the rule,
  the model follows it by judgment.
- **Yes, and only session-boundary state** → `prompt-continue.sh` is the one example left
  (a bare "continue" needs to know if something's parked, which the prompt text alone can't say).

There is no more "block" or "guarantee control-flow" category — R100 retired both, knowingly,
after being shown the cost twice. Don't try to rebuild either with a new hook; that would
re-litigate a decision the owner already made deliberately (see R100's note in
[docs/adr/README.md](./docs/adr/README.md) for exactly what was traded and why).

## Source of truth

**Durable requirements/decisions live in [docs/adr/README.md](./docs/adr/README.md)** (the live
ADR ledger) and **[docs/adr/PROVENANCE.md](./docs/adr/PROVENANCE.md)** (frozen history, never
edited — a new decision goes in README.md instead, even one that reopens or supersedes a
PROVENANCE row). Status tags: 🔒 locked / 🔓 open / ⚰️ retired. CLAUDE.md and ROADMAP reference
both by R-ID. Reverse one *there*, as a visible trade-off, never silently.

## Layout

```
.claude-plugin/marketplace.json   # the one companion plugin (name, source, version)
.github/workflows/ci.yml          # runs ./check.sh on push; installs mcp-server/'s npm deps
check.sh                          # single source of truth for "what we check"
CLAUDE.md  AGENTS.md  README.md    # this file = maintainer SSOT; README = discoverability
docs/adr/README.md  docs/adr/PROVENANCE.md  docs/ROADMAP.md  docs/MAP.md
plugins/companion/
  .claude-plugin/plugin.json       # version == the marketplace entry; declares mcpServers
  hooks/hooks.json                 # SessionStart, PreToolUse[AskUserQuestion], UserPromptSubmit
  STEERING.md                      # the steering layer (prose, advisory — but injected by a hook)
  mcp-server/                      # companion-tq MCP server (Node, stdio) — tq_* + check_for_secrets + rest
  bin/tq check-secrets.sh statusline.sh resume.sh ship-checkpoint.sh
  bin/prompt-continue.sh session-start.sh ask-guard.sh   # the three hooks
  bin/autopilot.sh                 # "don't ask" enforced (R100/Pass 6); "keep going" is not
  lib/companion.sh lib/resume-report.sh   # shared helpers; the latter feeds resume.sh + session-start.sh
  commands/{setup,autopilot,ship-it,resume,review,advise,redesign,docs,cover,board,burn-down,handoff}.md
  tests/companion-{core,hud,fuzz,ship}.bats   # the portable core + the three hooks
```

## Conventions

- **Bash + `jq` for the core; Node for the MCP server.** No compiled languages.
- **Hooks are best-effort and must NEVER break the action that triggered them** (`set -uo
  pipefail`, swallow errors, exit 0 when silent). Applies to all three.
- **Generic — no hardcoded language/framework allowlists** (R9). Delegate *recognition* to
  the model; detect *structure* generically. Wide-audience product (R1).
- **Files ≤ 300 lines** (CI guard); env-overridable locations (`CLAUDE_COMPANION_*`) so tests
  are hermetic.

## Verify

```bash
./check.sh          # JSON validity · claude plugin validate · shellcheck · gitleaks · size · bats
                    # · strict command-frontmatter parse · ledger measurements cite evidence (R78)
./check.sh --mutate # every declared mutation MUST turn the suite red; one that stays green is a
                    # hole — a test that cannot fail (R78). Full set is CI-only (minutes);
                    # ./check.sh --mutate <file>... runs just that file's mutations, which is what
                    # `ship.sh land` does for the paths a ship touches (R79)
# The two document checks live in dev/doc-lint.sh so bats can exercise them —
# anything inline in check.sh is untestable, since check.sh is what runs bats.
```

`check.sh` skips locally-missing tools (with a note) and is authoritative in CI.

## Workflow

Change → `./check.sh` → commit. `plugin.json` version and the marketplace entry must match;
bump only when meaningful.

## Don't

- **Don't rebuild block or control-flow enforcement with a new hook.** R100 retired both
  categories deliberately, after the cost was shown twice. That's a decision to respect, not a
  gap to quietly close.
- **Don't add a hook that only injects prose.** If it doesn't need session-boundary state a
  prompt can't see on its own, it belongs in `STEERING.md`.
- **Don't re-introduce the scattered-middleware pattern** the 2026-07-11 rebuild removed:
  per-hook token budgets, mirrored detectors, drift-guards, or a plugin that forces work it
  can't reliably own. Git history has the details; the ledger has the reasons (R24, R100).
- **Don't decompose preemptively** — let the 300-line guard decide.
