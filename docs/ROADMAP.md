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

**Token efficiency** is a value AND, for the injected core specifically, an enforced number
again. The old PER-HOOK character-budget apparatus stayed retired — it defended a cost the
read-once-per-session model doesn't incur, and it drove prose into cryptic anchors. What replaced
it is narrower and honest: `check.sh` caps the bytes actually INJECTED each session (`core_cap`),
because those are paid in every session in every installed repo. That cap rose eight times
(6144→8730, +42%) until the 2026-08-16 audit found it at five bytes of headroom; it now
RATCHETS DOWN only — 8500 — so an addition must be funded by a deletion (docs/adr R115).

## Architecture — steering, a portable core, and six hooks (R100/R105/R114/R116, supersedes R24)

- **Steering** (`plugins/companion/STEERING.md`) — all the prose: queue discipline, the
  brutal-honest recommendation posture against the ledger, clean-as-you-go, autopilot. Injected
  automatically at session start again (R100/Pass 6, docs/adr/README.md R105), and still printed
  on demand by `/companion:resume` mid-session. Advisory by nature; it lives in one file, not
  scattered across hooks.
- **The portable core** (`plugins/companion/bin/` + `mcp-server/`) — `tq` (the companion owns its
  store — it does **not** use native tasks; R8/R10), also reachable via the `companion-tq` MCP
  server for any MCP-capable client (R100/Pass 1, expanded Pass 5a to the rest of `bin/`);
  `check-secrets.sh`, an advisory credential scanner (R100/Pass 3 — was the enforced secret gate);
  `resume.sh`, the on-demand triage-and-pull twin of `session-start.sh` (same content, shared via
  `lib/resume-report.sh`, plus it disarms autopilot as part of pulling context); `ship-checkpoint.sh`,
  ship-mode's commit logic, still manually invoked (not reinstated); `autopilot.sh`, a persisted
  preference flag — **"don't ask" enforced again** (R100/Pass 6), **"keep going" still not**;
  the status line (`statusline.sh`, untouched).
- **Six hooks** — `prompt-continue.sh` (UserPromptSubmit, never retired): the case that needs
  session-boundary state a prompt can't see on its own. `session-start.sh` (SessionStart,
  **reinstated** R100/Pass 6): guarantees STEERING + carried tasks reach a session — the owner's
  fix for a model ignoring context it never had. `ask-guard.sh` (PreToolUse[AskUserQuestion],
  **reinstated** R100/Pass 6): denies + auto-parks a question while autopilot is armed.
  `stop-autopilot.sh` (Stop) came BACK 2026-08-12 — forced continuation, bounded by every
  terminator that makes it safe — and since 2026-08-15 also fires the burn-down hand-off on a dry
  queue (R114). Only `secret-guard.sh`/`contract-guard.sh` (block-on-write) stay retired
  (docs/adr/README.md R104/R105/R111/R114).

Bash + `jq` for the core, Node for the MCP server, zero build otherwise. The `file →
responsibility` index is [docs/MAP.md](./MAP.md).

## The loop — propose → queue → drain (R52)

The product is one loop, and every capability is a stage of it:

1. **Propose** — from repo context, Claude surfaces the highest-value next action as a
   **recommendation-first nudge** (debt → a paydown task · wide blast radius → split · repetitive
   manual drain → autopilot · a finished chunk → ship-it). Nudges are the *funnel into the queue* —
   ephemeral model judgment, **not stored state** — delivered as STEERING. (Proactive plugin
   surfaces: the status line, `AskUserQuestion` — now enforced under autopilot again, R100/Pass 6
   — and SessionStart injection, also reinstated R100/Pass 6; a plugin still **cannot** inject
   CLI autocomplete prompts, R51.)
2. **Queue** — the owner picks (or edits, declines, or just talks it through); the chosen work
   enters `tq`, the durable, crash-safe spine (**R44/R8**). The queue — not the nudge — is the
   backbone; nudges are the best *content* flowing into it (**R52**: the two are asymmetric —
   infrastructure vs behavior).
3. **Drain** — work the queue by hand, or under **autopilot** (keep-going, R26/R36 — "don't ask"
   enforced again since R100/Pass 6, "keep going instead of stopping" still not), landing finished
   work via **`/companion:ship-it`** (R40).

The portable core maps onto the loop, and enforces two of its edges again: `session-start.sh`
seeds it automatically (as well as on-demand via `/companion:resume`), `tq` holds it, autopilot
drains it and `ask-guard.sh` blocks a premature question while it's armed (forced continuation
itself is still a stated preference, not a guarantee), `check-secrets.sh` advises on every write
(never blocks). The nudges, the recommendation contract, and clean-as-you-go stay **STEERING**
(R28) — but "don't ask" and "guaranteed context" moved back to enforced code (R100/Pass 6,
docs/adr/README.md R105), a narrower reopening of R28's own rule than R100 first drew it.

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
