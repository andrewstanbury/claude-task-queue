# ROADMAP — the companion

A living **design record**: direction, durable decisions, and what's next. Per-version
history is in `git`, not here. Read [AGENTS.md](../AGENTS.md) for conventions and
[docs/REQUIREMENTS.md](./REQUIREMENTS.md) for the status-tagged requirements ledger.

The goal: a Claude Code plugin that lets you **vibe-code a project** while Claude keeps it
clean, well-documented, and low-debt — proactively, with minimal input, through the CLI. The
one human-facing surface is a lean `README.md` for GitHub discoverability; everything else is
Claude-facing (the steering doc + the ledger).

*(2026-07-11 ground-up rebuild — ledger **R24**: the four-plugin, ~12,500-line
prompt-injection framework collapsed into one `companion` plugin = a single steering document
+ a tiny enforced core. The sections below describe the current shape; git has the arc.)*

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

## Architecture — one plugin, two kinds of thing (R24)

- **Steering** (`plugins/companion/STEERING.md`) — all the prose: queue discipline, the
  brutal-honest recommendation posture against the ledger, clean-as-you-go, autopilot. Read
  once per session. Advisory by nature; it lives in one file, not scattered across hooks.
- **Enforced core** (`plugins/companion/bin/`) — the behavior that must **block, inject, or
  guarantee control-flow** (the dividing rule is **R28**, sharpened by **R51** — there is no longer
  an *execute* member): the secret gate (`secret-guard.sh`), cross-session resume + steering
  injection + the post-compaction re-anchor (`session-start.sh`), persisted + enforced autopilot
  (`autopilot.sh` · `ask-guard.sh` · `stop-autopilot.sh`; R26), the `tq` queue (the companion owns
  its store — it does **not** use native tasks; R8/R10), and the status line (`statusline.sh`).

Bash + `jq`, zero build. The `file → responsibility` index is [docs/MAP.md](./MAP.md).

## The loop — propose → queue → drain (R52)

The product is one loop, and every capability is a stage of it:

1. **Propose** — from repo context, Claude surfaces the highest-value next action as a
   **recommendation-first nudge** (debt → a paydown task · wide blast radius → split · repetitive
   manual drain → autopilot · a finished chunk → ship-it). Nudges are the *funnel into the queue* —
   ephemeral model judgment, **not stored state** — delivered as STEERING. (The only proactive
   plugin surfaces are SessionStart injection, the status line, and `AskUserQuestion`; a plugin
   **cannot** inject CLI autocomplete prompts — verified, R51.)
2. **Queue** — the owner picks (or edits, declines, or just talks it through); the chosen work
   enters `tq`, the durable, crash-safe spine (**R44/R8**). The queue — not the nudge — is the
   backbone; nudges are the best *content* flowing into it (**R52**: the two are asymmetric —
   infrastructure vs behavior).
3. **Drain** — work the queue by hand, or under **autopilot** (keep-going, R26/R36), landing
   finished work via **`/companion:ship-it`** (R40).

The enforced core maps cleanly onto the loop: `session-start` seeds it (inject), `tq` holds it,
autopilot drains it (control-flow), the secret gate guards every write (block). Everything
advisory — the nudges, the recommendation contract, clean-as-you-go — is **STEERING** (R28).

## Durable decisions → the ledger

Durable requirements and decisions live in [docs/REQUIREMENTS.md](./REQUIREMENTS.md) as
status-tagged entries (🔒 locked / 🔓 open / ⚰️ retired) — challenge or reverse one *there*,
never silently. The arc: **R1–R23** carry the original design decisions (native-first,
run-in-auto, non-technical-owner posture, the critique/recommendation posture, the
decided-against set); **R24** records the ground-up rebuild; **R25–R26** pulled clean-as-you-touch
and autopilot back to *enforced*; **R27** briefly added edit-gates and **R28** retired them,
formalizing the execute-or-block rule; **R29** added `/companion:advise` (a self-critique ritual);
**R30–R31** refined the plugin for the agent (task `done-when`, compaction re-anchor, STEERING
checklists, activity beacon, CI fuzz, autopilot-conditional playtests); **R32** ran `advise` on
the plugin *itself* and walked back the same-day over-reach — retiring `pre-compact`, trimming the
compaction re-inject, folding `audit` into `advise`, and fixing a real status-line bug.

## What's next

Demand-driven only. Near-term: the enforced core is thin by design — extend it only when a
behavior genuinely needs to *execute or block* (everything else is a steering-doc edit). No
new layers planned.

## Build history

The full dated build-log is `git log` (commit messages carry the detail); this file keeps
only the forward direction above.
