# AGENTS.md — maintainer guide

This repository is **maintained by AI agents**, not a hands-on human team. It's
deliberately optimized for that: committed docs over tribal knowledge,
deterministic checks over conventions, hermetic tests over manual QA. **Read
this file first** — it's the single source of truth for how the repo is built.

## What this is

A small **marketplace of self-contained Claude Code companion plugins**:

- **`plugins/task-queue/`** — makes Claude Code's native task list a live work
  queue: a SessionStart policy + cross-session resume bridge + a per-repo **solo
  mode** + a UserPromptSubmit review loop that **splits the loop from the interrupt**
  (fires on every prompt: interpret → decompose → `TaskCreate` → work in auto by
  default, with sign-off via AskUserQuestion delegated to the model and surfaced only
  on real signal; the heavy present-and-approve + critique fires only on the
  deterministic consequential/design signal). The full procedure rides the SessionStart
  policy. **Solo mode** (owner stepped away — merges the old away + pause) runs fully
  autonomous: the Stop hook auto-continues the queue, a PreToolUse guard blocks
  AskUserQuestion, the review loop is suppressed, and anything needing the owner is
  parked as `❓`. **Read-only** over `~/.claude/tasks` (except its own state flags).
- **`plugins/tidy/`** — *tidy-as-you-touch*: formats and lint-checks the file you
  just edited (fixing only what's safe) so a project converges toward clean code
  over time, scoped to the touched file.
- **`plugins/charter/`** — *know the project*: gates substantive work on
  documented quality attributes (nudges to capture them if missing) and keeps the
  project's Claude manual in view. Read-only over the project.
- **`plugins/hud/`** — *show what's happening*: a consolidated `statusLine`
  renderer (no hooks) that reads the other plugins' on-disk state read-only and
  prints one line. Wired via the user's `statusLine` config.

Each plugin has a `CONTRACT.md` (the **undocumented Claude Code internals it
depends on** — read it before changing any hook input/output); its `plugin.json`
`description` says what it does. The system's direction lives in
[docs/ROADMAP.md](./docs/ROADMAP.md); **git history is the changelog** (no
per-plugin READMEs or CHANGELOGs, no human-facing docs). These Claude-facing docs
(this file, each CONTRACT, the ROADMAP, the MAP) are the manual.

## Enforcement map — what's guaranteed vs nudged

The system makes behavioral promises two ways, and the difference is load-bearing
(the "solo paused anyway" bug was an *advisory* promise that read like a guarantee).
Be honest about which is which:

- **ENFORCED** — a hook mechanically makes it happen, or refuses to let the turn
  end. The model can't skip it. Each has an env kill-switch, and hud's `🛡✗N` marker
  surfaces any enforced *floor* currently switched off (the beacon can read green
  while a guard is disabled — this is what keeps the status line honest).
- **NUDGED** — injected instruction the model follows by judgment. Best-effort by
  nature: a long context, a contrary prompt, or a lapse can bypass it. Treat these
  as intent, not contract.

| Behavior | Kind | Mechanism · kill-switch |
|---|---|---|
| Intent→outcome gate (change matches the ask) | ENFORCED | tq-verify Stop-block · `CLAUDE_TQ_INTENT_GATE=0` |
| Solo auto-continues the queue | ENFORCED | tq-verify Stop-block · `CLAUDE_TQ_AWAY_CONTINUE=0` |
| Solo blocks AskUserQuestion | ENFORCED | tq-ask-guard PreToolUse-deny · `CLAUDE_TQ_AWAY_ASK_GUARD=0` |
| Solo suppresses the approval loop | ENFORCED | tq-capture (deterministic) |
| Verification floor (tests green before done) | ENFORCED | tidy-verify Stop-block · `CLAUDE_TIDY_CHECKS=0` |
| Secret pre-write scan | ENFORCED | tidy-presecret PreToolUse-block · `CLAUDE_TIDY_SECSCAN=0` |
| Alignment gate (vs recorded decisions) | ENFORCED | charter-align-gate Stop-block · `CLAUDE_CHARTER_ALIGN_GATE=0` |
| Crash-checkpoint snapshots | ENFORCED | tq-checkpoint PostToolUse (opt-in) |
| Token budgets | ENFORCED | CI (`tests/token-budget.bats`) |
| Interpret→decompose→queue, work in order | NUDGED | SessionStart/capture injection |
| Steelman-then-challenge critique posture | NUDGED | injection |
| Run-in-auto, advance without draining | NUDGED | injection |
| Design-preview (wireframe before build) | NUDGED | capture injection |
| Park-as-`❓` under solo | NUDGED (but cornered) | injection — the enforced ask-block + auto-continue leave parking as the only exit |

**On markers:** hud's `🛡✗` already covers the one honest runtime signal — an ENFORCED
floor that's been disabled. NUDGED behaviors have no on/off to surface, so a "was this
followed?" badge would itself be dishonest. The fix for a nudge that matters is to
*promote it to ENFORCED* (as `solo` was — advisory → Stop-block + PreToolUse-deny),
not to badge it. So this audit added no hud marker on purpose.

## The one rule that drives the architecture: the install boundary

**Claude Code installs each plugin independently — at runtime only that plugin's
own subdirectory exists** (reachable via `${CLAUDE_PLUGIN_ROOT}`). Therefore:

- **Every plugin must be fully self-contained.** It may only reference files
  inside its own `plugins/<name>/`.
- **Do NOT extract a cross-plugin shared library, and do NOT add a build step**
  to de-duplicate. The small repeated bits are duplicated **on purpose** — that's
  the price of independent installability; DRYing them would break standalone
  installs. What's duplicated, and what stops each copy drifting, is the ledger
  below.
- **Mirrored detection is drift-guarded, not shared.** Where a plugin must
  re-implement charter's logic to stay standalone (the copies once silently
  drifted — `hud_qa` missed `QUALITY.adoc`), **`tests/drift-guard.bats`** asserts
  they agree instead of sharing code. A runtime inventory file was *Decided
  against* (docs/ROADMAP.md); the test is the enforcer.

### Intentional-duplication ledger

Duplication across plugins is deliberate. A copy is kept from drifting one of two
ways: a **guard** (a test reddens when copies disagree) or **mirror-by-copy** (a
convention — copy a sibling, keep it identical by hand). This table is a reading
aid, **not** the enforcer: for guarded rows the test is the source of truth (a
runtime inventory was Decided against — don't promote the bottom rows into one).

| Duplicated across plugins | Source of truth | Kept honest by |
|---|---|---|
| Project-doc detection (QA / map / roadmap / decisions) | charter `lib/charter.sh` | **guard** — `drift-guard.bats` (task-queue `tq_*_path` mirror) |
| Scar-tissue / hotspot detection | charter `tidy_hotspots` | **guard** — `drift-guard.bats` (tidy regression-gate mirror) |
| Plugin version | `plugins/<n>/plugin.json` | **guard** — packaging test + drift-guard (`marketplace.json` + README table) |
| `bin/` symlink-resolve + `set -uo pipefail` preamble | any sibling `bin/*.sh` | mirror-by-copy (the "Add a plugin" step) |
| `hookSpecificOutput` JSON emission shape | any sibling that emits it | mirror-by-copy (+ `token-budget.bats` caps size) |
| Hook-stdin field reads via `jq` (`tool_input` / `tool_name` / `prompt`) | any sibling hook | mirror-by-copy |

Changing a **guard** row → update the mirror in the same change (it stays red
until they agree). Changing a **mirror-by-copy** idiom → nothing enforces it, so
`grep` the siblings and apply it everywhere.

## Layout

```
.claude-plugin/marketplace.json   # lists every plugin (name, source, version)
.github/workflows/ci.yml          # runs ./check.sh on push (the backstop)
check.sh                          # single source of truth for "what we check"
.editorconfig
AGENTS.md  CLAUDE.md  LICENSE   # AGENTS.md = the maintainer SSOT (Claude-context only; no human-facing docs)
docs/ROADMAP.md  docs/MAP.md
plugins/<name>/
  .claude-plugin/plugin.json      # version MUST equal the marketplace entry
  hooks/hooks.json                # wires the hooks (absent for hud — it's a statusLine)
  bin/*.sh                        # thin entrypoints: parse stdin, emit JSON
  lib/*.sh                        # the logic
  tests/*.bats                    # hermetic; fake state via CLAUDE_*_DIR overrides
  CONTRACT.md
```

## Conventions (mirror these in any new plugin)

- **The priority order — the 0–4 list, its rationale, and the token-efficiency
  payoff live in [docs/ROADMAP.md](./docs/ROADMAP.md) (§Prioritized criteria);
  CLAUDE.md carries the one-line-each summary the companion hooks re-anchor to.**
  Tuned for *existing, under-tested, under-documented projects that must stay clean
  as they grow*. The per-principle "how" is the bullets below.
- **Contain blast radius — per change *and* as a system trend (principle #1).** The
  master lever for keeping a project efficient and correct as features are added is
  to **minimize and understand the blast radius of every change**: both *code* blast
  radius (what a touched file ripples into → surface dependents) and *architectural*
  blast radius (how far a change ripples → one owner per concern, contracts not
  copies). At scale, also watch that **total coupling isn't climbing** — compounding
  debt is a blast-radius-*at-scale* problem. Its legacy corollaries: **characterize
  before you change** (no tests → pin the affected surface's current behavior with a
  test first; blast radius says what to pin — so the project accrues a spec over
  time), and **clean as you touch, bounded by blast radius** (improve the touched
  area, but *ratchet, never sweep* — refactoring code whose ripple you can't see is
  itself a top cause of rework). Ask "how far does this ripple, and how do I contain
  it?" before every change.
- **Subtract as you add (principle #3) — the anti-entropy rule.** A new requirement
  must leave net surface **flat or smaller**: reuse before create, delete what the
  change makes redundant. Without it, even individually-clean changes grow the
  project monotonically into debt. What touch-time bounding skips (cross-module,
  rarely-touched debt) is caught by tidy's **automatic** deliberate prune (at
  SessionStart, over a debt threshold it injects the weight report + a run-a-prune
  instruction), not incremental nibbling.
- **Non-technical-owner posture (the target projects' owners can't read code).**
  *Autonomy on the reversible, consent on the consequential* — resolve safe/reversible
  findings yourself, but the dividing line is **reversibility + cost + data-safety,
  not technical-vs-product**: get a plain-language yes before a paid dependency, an
  irreversible data migration/deletion, or vendor lock-in. **Boring & reversible by
  default** (architecture gets no human review here). **Verification must be
  observable** — demonstrate user-visible changes in plain language, since the owner
  verifies by seeing it work, not by reading tests. Keep a thin plain-language owner
  doc layer (#0) so they aren't locked to one Claude session. **Honor the owner's
  outcome, not their proposed implementation** — push back on over-engineering
  (including the owner's own): unwarranted complexity drives a growing blast radius,
  so **YAGNI** (CLAUDE.md working standards #1) applies hardest to owner-proposed scope.
- **Bash + `jq`, zero build.** No compiled languages, nothing to install to run
  a hook. (This is why the plugins are Bash, not Go — a compiled hook needs
  per-platform binaries or a toolchain, which breaks "runs everywhere, no build".)
- **Hooks are best-effort and must NEVER break the action that triggered them.**
  `set -uo pipefail`, swallow tool errors, exit 0 when there's nothing to say.
- **Invariants, per plugin:** task-queue is **read-only** over `~/.claude/tasks`
  (it reads, or nudges the model — it never writes the task store); tidy
  **only auto-applies behavior-preserving fixes** (formatting) and surfaces
  everything else.
- **Locations are env-overridable** (`CLAUDE_TQ_*`, `CLAUDE_TIDY_*`, e.g.
  `CLAUDE_TIDY_LOG_DIR` for tidy's state dir) so tests are hermetic — temp dirs,
  no mocking framework.
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

## Workflow (personal, Claude-run — no human ceremony)

- **Change → `./check.sh` → commit to `main`.** No branches, no PRs, no
  per-change tags or changelogs: a human won't review, and git history is the
  record. CI re-runs `check.sh` on push as the backstop.
- **`./check.sh` is the gate** — it's the only error-catcher, since no human
  reviews. It can't run `shellcheck`/`gitleaks` locally (not installed), so for
  shell-heavy changes CI may catch what local can't; if CI reddens, **fix
  forward** with another commit (brief red `main` is fine — no other consumers).
- **Versions** in `plugin.json` + the marketplace entry **+ the README's plugin
  table** must match (a packaging test + `tests/drift-guard.bats` enforce both); bump
  only when it's meaningful, not every change.

## Add a plugin

1. Copy an existing plugin's structure into `plugins/<name>/`.
2. Mirror the conventions above; include a `CONTRACT.md` and tests.
3. Add an entry to `.claude-plugin/marketplace.json` (`"source": "./plugins/<name>"`)
   with a version equal to the plugin's `plugin.json`.
4. `./check.sh` must pass, then commit to `main`.

## Don't

- Don't add a cross-plugin shared lib or a build step (install boundary).
- Don't add anything that runs per prompt.
- Don't re-introduce the heavyweight features the project deliberately dropped
  (a bespoke task store, Haiku auto-decompose, autopilot, a plugin-side
  destructive-action gate, human-facing docs). The project's whole arc was
  *removing* these because they cost tokens, duplicated native Claude Code
  behavior, or couldn't be owned reliably by a plugin (git history has the
  details). The dropped destructive-action gate is now covered **natively**
  (settings.json `auto` mode + `deny`/`ask` sets); charter keeps only the
  plain-language consent *posture*, no hook — see docs/ROADMAP.md ("Run in auto"
  + "Decided against") for the specifics.
- Don't decompose preemptively; let the 300-line guard decide.
