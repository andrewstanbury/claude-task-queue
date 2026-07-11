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
  requirements ledger, quality attributes, stack notes. Bootstrap if missing; gate substantive
  work on it.
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
- **Enforced core** (`plugins/companion/bin/`) — the only behavior that must execute or block:
  the secret gate (`secret-guard.sh`), cross-session resume + steering injection
  (`session-start.sh`), and the `tq` queue fallback for models with the native task tools
  gated off.

Bash + `jq`, zero build. The `file → responsibility` index is [docs/MAP.md](./MAP.md).

## Durable decisions → the ledger

Durable requirements and decisions live in [docs/REQUIREMENTS.md](./REQUIREMENTS.md) as
status-tagged entries (🔒 locked / 🔓 open / ⚰️ retired) — challenge or reverse one *there*,
never silently. **R1–R23** carry the design decisions (native-first, run-in-auto,
non-technical-owner posture, the critique/recommendation posture, the decided-against set);
**R24** records the rebuild and what it reshaped (R3, R4, R6, R22).

## What's next

Demand-driven only. Near-term: the enforced core is thin by design — extend it only when a
behavior genuinely needs to *execute or block* (everything else is a steering-doc edit). No
new layers planned.

## Build history

The full dated build-log is `git log` (commit messages carry the detail); this file keeps
only the forward direction above.
