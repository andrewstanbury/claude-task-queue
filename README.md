# Claude Code companion

One [Claude Code](https://claude.com/claude-code) plugin that makes Claude a disciplined
pair: it turns your requests into a live task queue, decides with **brutally honest,
multiple-choice recommendations** that name what each option would change, keeps code clean
as it changes it, and keeps working on its own without stopping — backed by a portable core (its
own task queue, a ship rail, a credential-shape scanner) reachable from Claude Code or, via MCP,
other agentic clients.

It's built around one idea: **steering is a document, and almost everything here is steering.**
The companion's judgment — the queue discipline, the recommendation posture, the clean-as-you-go
habit — is one document Claude reads on request, not code enforcing it. What's left as code is
the mechanical part that has to reproduce byte-for-byte: the task-queue store, the ship rail, a
credential-shape scanner — exposed both as CLIs and, for portability to other MCP-capable clients,
as an MCP server. Nothing here blocks a write or forces a session to keep going anymore; that
enforcement was traded, deliberately, for working the same way on more than one host.

| Part | What it is |
|---|---|
| **Steering** ([STEERING.md](plugins/companion/STEERING.md)) | The working agreement: how Claude queues work, challenges the ask, recommends against a **requirements ledger** (🔒 locked / 🔓 open), keeps changes clean, and runs autonomously without stopping. Printed on request by `/companion:resume` (or the MCP `resume` tool) — nothing injects it automatically. |
| **Credential scanner** | On request, classifies a file as containing a credential shape (`check-secrets.sh` / the MCP `check_for_secrets` tool). Advisory — it can warn or flag, it cannot block a write. |
| **Resume / Review** | `/companion:resume [branch]` re-surfaces this repo's unfinished tasks (session pickup, on request — nothing runs it automatically). `/companion:review` walks the backlog waiting on you — parked ❓ decisions + blocked ⏳ actions — one at a time, and runs when you turn autopilot off. |
| **Ship** | `/companion:ship-it [pr] [--gate <cmd>]` — verify your gate, commit, push, and merge (or `pr` to open a pull request instead). |
| **`tq`** | The task queue — self-owned, so it works everywhere (including the newest models where Claude's built-in task tracking is switched off) and doesn't depend on Claude Code internals. It reprints the queue on every change, so the CLI always shows what's in progress and next. Also reachable via the MCP server, for any MCP-capable client. |
| **Autopilot** | `/companion:autopilot on` — Claude keeps working the queue **without stopping**, parking decisions it shouldn't make alone. It's "keep going," *not* "you're away": keep it on and keep queuing tasks while you watch. Advisory (a persisted preference the model follows, not a guarantee), persists across restarts. `ship on` also commits work to an `autopilot/*` branch on request (no longer automatic); `decisive on` auto-picks the recommended option for reversible decisions (recording each) and parks only the irreversible; `sweep on` goes further and works the **already-parked** pile too. |
| **Status line** | One glance line, grouped with `:` dividers: ⠋ beacon · `v<x.y.z>` · `:` active features `:` (each shown only when relevant — `🛡️✗` only if the gate is off, ✈️ autopilot, 📦 ship-mode; omitted entirely when none) · `:` 📋 ❓ ⏳ `:` (the queue) · `:` ↻2h ▰▰▱▱▱ 23% ↻6d ▰▰▰▱▱ 41%▴ `:` (account rate limits — the label is the reset countdown, falling back to the 5h/7d window name when there isn't one; `▴`/`▾` on the 7d says whether you are on pace to spend the window before it resets) · model · ⇡⇣ tokens · project · ⎇ branch · ↑↓ ahead/behind. Wire it once with `/companion:setup` (legend below). |

Bash + `jq`, zero build, one install.

## Commands

- **`/companion:setup`** — wire the status line into your settings (one-time).
- **`/companion:advise [target] [-- goal: X]`** — an independent, brutally-honest **critique** of a
  target (default: the whole project), optionally against a goal you name, presented as
  recommendation-first choices, then queued. Doubles
  as a cleanliness sweep (size · debt · blast-radius · perf). Critique only — never edits.
- **`/companion:redesign [module]`** *(experimental)* — a contract-preserving rebuild of the whole app from
  your logged UX + quality-attribute contract, as bounded, check-gated passes. It runs
  **`/companion:docs` first** to log the contract, applies on a branch, stays gated on your
  safety checks, auto-reverts on red, and confirms each step. **Name a module** and it runs exactly
  one such pass on that target (this absorbed the former `/companion:regen`).
- **`/companion:docs [scope]`** — excavates the decisions your repo **depends on but never wrote
  down** and records each at the strongest tier it can reach: an executable check, a 🔒 locked
  requirement, or a 🔓 open one. It asks *you* for the "why" rather than inventing one — an
  assumption you never picked never becomes a 🔒. This is what stops `/companion:advise` from
  proposing to delete something load-bearing that simply wasn't communicated.
- **`/companion:cover [scope]`** — ranks your critical flows by **criticality × coverage gap**, then
  recommends the ideal test for each and writes the ones you pick, in your project's own test
  runner. It's licensed to conclude "these paths are already covered — write nothing," and it says
  plainly which critical flows you left unguarded by choice.
- **`/companion:autopilot [on|off|status]`** — keep working the queue without stopping — keep it on and keep queuing tasks.
  Add **`autopilot ship on`** to auto-commit completed work to an `autopilot/*` branch (reversible,
  never main, no push) for you to review + ship on return. Add **`autopilot decisive on`** to have it
  **pick the recommended option** for reversible decisions (design/wording included) and record each,
  parking only what's irreversible — shown as `✈️⚡`; review the auto-picks any time with `/companion:review`.
  Add **`autopilot sweep on`** to also work parks that were **marked reversible** when they were
  set aside (`❓ [parked] rev: …` — a taste or wording call), applying each one's recorded
  recommendation. Shown as `🧹`. A park with no `rev:` marker counts as irreversible and is never
  swept; neither are `⏳` blocked items. Worth knowing what you're trading: those parks stop being
  a list of things waiting for you and become a log of decisions already made on your behalf.
- **`/companion:resume [branch]`** — **re-surfaces this repo's unfinished tasks** from an earlier session
  (turning autopilot off first, preserving each task's ❓/⏳/📋 class). Session pickup only; it hands
  off to `/companion:review` for anything waiting on your input. Name the branch a
  `/companion:handoff` pushed to pick that up on this machine; without one it auto-detects.
- **`/companion:handoff`** — switching machines **mid-task**: commits your working tree *and* the
  task queue to a pushed branch, so the other machine picks up exactly where you stopped with
  `/companion:resume <branch>`. It's a checkpoint, not a ship — your gate deliberately doesn't run
  (a red tree mid-work is normal) and nothing lands on your main branch.
- **`/companion:review`** — walks the backlog that needs *you* — parked ❓ decisions + blocked ⏳
  owner-actions — one at a time, recommendation-first, recording each pick before new work.
  **Runs automatically when you turn autopilot off** — so decisions deferred while it ran get your
  input before it moves on. A clean no-op when nothing's parked.
- **`/companion:ship-it [pr] [--gate <cmd>]`** — verify → state the case → commit → push → **merge to
  main → prune the merged branches** (local + remote; shared repos are confirmed first). `pr` opens a
  pull request instead of merging — which also means no gate re-run, no staged-credential refusal, no
  ff-only merge and no enforced CI watch. `--gate` names your test command when it isn't a `check.sh`.

## Status line legend

Three plugin sections then generic — `⠋` beacon `-` **active features** `-` **the queue** `-` model · git:
`⠋` health beacon (spins while working) · `v<x.y.z>` the installed plugin version · `🛡️✗` credential
scanner **off** (shown only when disabled — no icon when it's on) · `✈️` autopilot on (`✈️⚡` decisive) · `📦` ship-mode armed · `📋` open · `❓` parked ·
`⏳` blocked tasks · **account** rate-limit usage bars (labelled `↻`<time-to-reset>, or `5h`/`7d` when there is none; `▴`/`▾` on the 7d = on/behind pace to spend it) · `⇡`/`⇣` input/output tokens · project · `⎇` branch · `*N` uncommitted · `↑`/`↓`
commits ahead/behind upstream. *(`⇡⇣` are tokens; `↑↓` are git — two arrow pairs, different meanings.)*

**The `5h`/`7d` bars** show how much of your Claude.ai subscription's **rolling** rate-limit windows
you've burned — account-wide, not just this repo. Green under 60%, yellow 60–84%, red at 85% and above, and a
`↻` countdown to the window reset, used as each bar's label. It's free: Claude Code already hands the status
line this data, so there's no API call and no token cost. Note these are **rolling 5-hour and 7-day
windows, not a monthly billing cycle** — there is no monthly figure to show. The bars appear only for
Pro/Max plans after the session's first response; on an API key you won't see them at all.

## Documentation

The full design lives under [`docs/`](docs/) — the contract a rebuild must preserve, plus the map
and ledger. `/companion:ship-it` keeps this index current (R57).

- **[docs/needs.yaml](docs/needs.yaml)** — **level 0**: what "useful" means, in the owner's words. The one level an agent never authors, because a system that writes its own definition of useful has no falsifiable standard left.
- **[docs/requirements.yaml](docs/requirements.yaml)** — **level 1, and the contract**: one observable behaviour per entry, each satisfying a real need and naming the tests that verify it. `dev/trace.sh` gates both directions, so a requirement with no test and a test with no requirement are equally loud.
- **[docs/flows/](docs/flows/)** — the user-experience contract: one dense spec per user flow (`when · why · steps · quality · tests · changes` — machine shape, R66), with shared [conventions](docs/flows/_patterns.md) and a global [quality bar](docs/flows/_quality-bar.md).
- **[docs/INVARIANTS.md](docs/INVARIANTS.md)** — the safety/correctness net: the must-holds, each tied to an executable check.
- **[docs/adr/README.md](docs/adr/README.md)** — decisions, architecture choices and **rejected options**: why it is this way and what was turned down.
- **[docs/adr/PROVENANCE.md](docs/adr/PROVENANCE.md)** — the *frozen* evidence behind the older requirements (🔒 locked / 🔓 open / ⚰️ retired). History, never edited — the live contract is `requirements.yaml`.
- **[docs/MAP.md](docs/MAP.md)** — the code map: every file and what it does.
- **[docs/ROADMAP.md](docs/ROADMAP.md)** — where it's heading.
- **[docs/GLOSSARY.md](docs/GLOSSARY.md)** — the coined vocabulary.
- **[docs/CONFIG.md](docs/CONFIG.md)** — the configuration reference (there is deliberately very little of it).
- **[docs/LESSONS.md](docs/LESSONS.md)** — repo-specific gotchas, injected each session so they aren't re-discovered.

## Requirements

- **`jq`** and **Bash** (macOS's built-in 3.2 works). Without `jq`, the hooks degrade to a
  silent no-op rather than breaking your session.
- **`git`** — for cross-session resume and repo-aware behavior. Non-git folders are fine.

## Install

```
/plugin marketplace add andrewstanbury/claude-task-queue
/plugin install companion@andrewstanbury
```

Or run `/plugin` and pick it from the **Discover** tab.

> **Two things to turn on:** the plugin installs inert — run **`/companion:resume`** once to bring
> the working agreement and any carried-over tasks into context, and **`/companion:setup`** once to
> wire the *status line* (nothing prompts you for either otherwise).

## What installing does

Almost nothing, until you ask for it — R100's trade for working the same way on more than one
MCP-capable client. Nothing blocks a write and nothing runs automatically at session start
anymore.

- **`/companion:resume`** (or the MCP `resume` tool) puts the working agreement (STEERING.md) in
  context and surfaces any unfinished tasks from an earlier session in this repo.
- **On request**, a file can be checked for a hardcoded-credential shape (`/companion:review`'s
  workflow calls it where relevant, or call `check-secrets.sh` / the MCP `check_for_secrets` tool
  directly) — advisory only, disable with `CLAUDE_COMPANION_SECSCAN=0` if you don't want it at all.
- **Everything else** — the queue discipline, the recommendation posture, clean-as-you-go — is
  Claude following the steering document, not a hook forcing anything.

The **autonomous** behavior (keep working the queue without stopping, parking decisions for you)
only runs when you turn it on — `/companion:autopilot on` (or just "keep going"). It means *keep
going*, not *you're gone* — you can stay and keep queuing tasks. Nothing hazardous arms on install.

## Turning it off

- **Remove it:** `/plugin uninstall companion@andrewstanbury`.
- **Silence the credential scanner but keep the plugin:** `CLAUDE_COMPANION_SECSCAN=0`.
