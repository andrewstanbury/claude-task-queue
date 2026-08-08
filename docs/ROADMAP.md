# ROADMAP — the companion

A living **design record**: direction, durable decisions, and what's next. Per-version
history is in `git`, not here. Read [AGENTS.md](../AGENTS.md) for conventions and
[docs/adr/PROVENANCE.md](./adr/PROVENANCE.md) for the status-tagged requirements ledger.

The goal: a Claude Code plugin that lets you **vibe-code a project** while Claude keeps it
clean, well-documented, and low-debt — proactively, with minimal input, through the CLI. The
one human-facing surface is a lean `README.md` for GitHub discoverability; everything else is
Claude-facing (the steering doc + the ledger).

*(2026-07-11 ground-up rebuild — ledger **R24**: the four-plugin, ~12,500-line
prompt-injection framework collapsed into one `companion` plugin = a single steering document
+ a tiny enforced core. **2026-08-08 — ledger R100**: that enforced core is itself retired, in
bounded passes, traded for portability to other MCP-capable clients. The sections below describe
the current (mid-rewrite) shape; git and [docs/adr/README.md](./adr/README.md) R100 have the arc.)*

## Prioritized criteria (in order)

Tuned for **existing, often legacy, under-tested projects that must stay clean as they grow.**
These are the *values* the steering doc encodes; they're not code.

- **0 · Keep the project self-describing** *(precondition)* — a map (file→responsibility), the
  requirements ledger, quality attributes, stack notes, a coined-vocabulary glossary (R37).
  Bootstrap if missing; gate substantive work on it.
- **1 · Contain blast radius** — know what a change ripples into (code + architectural) and
  cover it; one owner per concern. **YAGNI: the burden of proof is on *adding*.**
- **2 · Verify + stay aligned** — confirm intent in plain language; verify observably
  (types/build/run; tests opt-in); weigh work against the ledger (clean ≠ correct); honor the
  owner's *outcome*.
- **3 · Subtract as you add** — net surface flat or smaller; reuse before create.

**Token efficiency** is still a value — a well-mapped, small-filed project is cheap for Claude
to load — but it is **no longer an enforced NFR** (R3, reshaped by the rebuild). The old
per-hook character-budget apparatus was retired: it defended a cost the read-once-per-session
steering model doesn't incur, and it drove prose into cryptic anchors. Efficiency now means
"the steering doc stays lean," not a CI char-count.

## Architecture — steering, a portable core, and one hook (R100, supersedes R24)

- **Steering** (`plugins/companion/STEERING.md`) — all the prose: queue discipline, the
  brutal-honest recommendation posture against the ledger, clean-as-you-go, autopilot. Printed
  on demand by `/companion:resume` — nothing injects it automatically anymore (R100/Pass 2).
  Advisory by nature; it lives in one file, not scattered across hooks.
- **The portable core** (`plugins/companion/bin/` + `mcp-server/`) — `tq` (the companion owns its
  store — it does **not** use native tasks; R8/R10), also reachable via the `companion-tq` MCP
  server for any MCP-capable client (R100/Pass 1); `check-secrets.sh`, an advisory credential
  scanner (R100/Pass 3 — was the enforced secret gate); `resume.sh`, which absorbed cross-session
  resume + steering printing + LESSONS + version-lag warning + recent-changes + rework
  (R100/Pass 2 — was `session-start.sh`); `ship-checkpoint.sh`, ship-mode's commit logic, now
  manually invoked (R100/Pass 4 — was part of `stop-autopilot.sh`); `autopilot.sh`, a persisted
  preference flag, **not enforced** (R100/Pass 4); the status line (`statusline.sh`, untouched).
- **The one surviving hook** — `prompt-continue.sh` (UserPromptSubmit), because it's the one
  remaining case that needs session-boundary state a prompt can't see on its own. Everything that
  used to *block* (`secret-guard.sh`, `contract-guard.sh`) or *guarantee control-flow*
  (`ask-guard.sh`, `stop-autopilot.sh`) is retired outright — R100 traded that guarantee for
  portability, deliberately, after the cost was shown twice.

Bash + `jq` for the core, Node for the MCP server, zero build otherwise. The `file →
responsibility` index is [docs/MAP.md](./MAP.md).

## The loop — propose → queue → drain (R52)

The product is one loop, and every capability is a stage of it:

1. **Propose** — from repo context, Claude surfaces the highest-value next action as a
   **recommendation-first nudge** (debt → a paydown task · wide blast radius → split · repetitive
   manual drain → autopilot · a finished chunk → ship-it). Nudges are the *funnel into the queue* —
   ephemeral model judgment, **not stored state** — delivered as STEERING. (Proactive plugin
   surfaces are now the status line and `AskUserQuestion` only — SessionStart injection is retired,
   R100/Pass 2; a plugin still **cannot** inject CLI autocomplete prompts, R51.)
2. **Queue** — the owner picks (or edits, declines, or just talks it through); the chosen work
   enters `tq`, the durable, crash-safe spine (**R44/R8**). The queue — not the nudge — is the
   backbone; nudges are the best *content* flowing into it (**R52**: the two are asymmetric —
   infrastructure vs behavior).
3. **Drain** — work the queue by hand, or under **autopilot** (keep-going, R26/R36 — advisory
   only since R100/Pass 4, not enforced), landing finished work via **`/companion:ship-it`** (R40).

The portable core maps onto the loop, but no longer enforces any stage of it: `/companion:resume`
seeds it (printed on demand, not injected), `tq` holds it, autopilot drains it (as a stated
preference, not a control-flow guarantee), `check-secrets.sh` advises on every write (never
blocks). Everything — the nudges, the recommendation contract, clean-as-you-go, and now autopilot
and the secret check too — is **STEERING** (R28's rule, extended by R100 to cover what R28 itself
used to carve out as enforced).

## Durable decisions → the ledger

Testable requirements live in [docs/requirements.yaml](./requirements.yaml); decisions and
rejected options live in [docs/adr/README.md](./adr/README.md) (the live ADR ledger, split out of
PROVENANCE.md 2026-08-02) as status-tagged entries (🔒 locked / 🔓 open / ⚰️ retired) — challenge or
reverse one *there*, never silently. [docs/adr/PROVENANCE.md](./adr/PROVENANCE.md) is frozen
history — a new decision goes in README.md, even one that supersedes a PROVENANCE row (R100 did
exactly this for R8/R9/R10/R24/R28/R51/R67). The arc: **R1–R23** carry the original design decisions (native-first,
run-in-auto, non-technical-owner posture, the critique/recommendation posture, the
decided-against set); **R24** records the ground-up rebuild; **R25–R26** pulled clean-as-you-touch
and autopilot back to *enforced*; **R27** briefly added edit-gates and **R28** retired them,
formalizing the execute-or-block rule; **R29** added `/companion:advise` (a self-critique ritual);
**R30–R31** refined the plugin for the agent (task `done-when`, compaction re-anchor, STEERING
checklists, activity beacon, CI fuzz, autopilot-conditional playtests); **R32** ran `advise` on
the plugin *itself* and walked back the same-day over-reach — retiring `pre-compact`, trimming the
compaction re-inject, folding `audit` into `advise`, and fixing a real status-line bug; **R33–R99**
built out the rest of the enforced-core era (sweep/decisive modes, ship-mode, burn-down, the
requirements/needs contract split, repo-state migration); **R100** (2026-08-08) retired that whole
era's enforcement in favor of an MCP server + portable skills, in bounded passes — the redesign
this file's Architecture section now describes.

## What's next

Demand-driven, same as always — but the near-term default flipped with R100: **don't rebuild
block or control-flow enforcement with a new hook.** That trade was made deliberately, twice, with
the cost shown both times. Extend the portable core (a new MCP tool, a new advisory CLI) when a
capability is genuinely missing; reach for a hook only for session-boundary state a prompt
genuinely can't see on its own (the bar `prompt-continue.sh` alone now clears).

**Parked exploration — `claude-only-redesign` (branch, not merged).** One commit (`aa17539`,
2026-07-20, forked pre-R63) prototypes a **repo-identity queue**: `bin/q` over an append-only
`.companion/queue.jsonl` *committed in the repo*, replayed to state on read — deleting the whole
R60 export/import + machine-local-store layer on the theory that **the repo is the identity and
git is the transport**, so cross-machine resume is a plain `git pull` with no re-stamping (the
commit claims a clone-to-a-different-path test). It is **not mergeable** — it predates R63 and
main has since built R63–R75 on top of the current model, including the `ship.sh` rail (R71) and
handoff (R72) that branch never had. Kept as a **design record only**: the live question it poses
is whether R60/R63's export/import + per-worktree identity is more machinery than
commit-the-queue would need. Pushed to origin so it survives this machine; delete the branch only
together with this pointer.

## Build history

The full dated build-log is `git log` (commit messages carry the detail); this file keeps
only the forward direction above.
