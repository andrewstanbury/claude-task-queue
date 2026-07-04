# Claude Code companion plugins

Four self-contained [Claude Code](https://claude.com/claude-code) plugins that let you
**vibe-code a whole project** while Claude keeps it clean, low-debt, and token-efficient
— **automatically, through hooks** — with the native task list as the one place you
steer. Built for an owner who reads no code and *need never run a command* — though a
few optional `/task-queue:` commands give deterministic control when you want it.

## The flow

```
 ▐▌ always on   native permissions (auto · deny/ask) · hud status line (●health ✓tests ❓open-Qs ctx%)

 ● SessionStart   charter: gate on docs+decisions+scar-tissue · task-queue: queue policy+resume · tidy: standard

 ◆ you type a prompt
      ├─ trivial ───────────────────────► runs straight through (auto)
      ▼ substantive / visual / consequential
 ┏━ task-queue · review loop ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
 ┃  interpret → present (AskUserQuestion) → approve → queue      ┃
 ┃  visual change? → wireframe DESIGN PREVIEW you pick from       ┃
 ┃  unanswered ❓ questions re-surfaced so they don't get buried  ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      ▼
 ⚙ Claude works the queue   (each edit → tidy: format·lint·blast-radius·size)
      ▼
 ┏━ Stop · the floors (each bounded, each opt-out) ━━━━━━━━━━━━━━┓
 ┃  tidy     quality gates → tests block-until-green → regression┃
 ┃  charter  alignment floor — don't silently reverse a decision ┃
 ┃  task-q   intent → outcome — did we build what you asked?      ┃
 ┃  tidy     import cycles + subtractive prune (after green)      ┃
 ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
      ▼
 ✓ done   hud flips to ✓ · plain-language recap (you verify by seeing)
```

> Run `./flow.sh` (or `make flow`) for the **live, colored** version — derived from the
> repo, so it can't drift.

## The four plugins

| Plugin | Ver | Role | Highlights |
|---|---|---|---|
| **task-queue** | 0.32.0 | Orchestrate | review loop on every prompt (steelman→challenge critique) · wireframe design preview · intent→outcome gate · open-questions tracker · cross-session resume + mid-task breadcrumb · **solo mode** (enforced autonomy — auto-continues the queue, blocks asking, parks decisions) · crash-checkpoint (working-tree snapshots) · one optional control command (`/tq` — solo · checkpoint · agent · undo · status) |
| **tidy** | 0.39.0 | Change safely | secret floor (block credentials pre-write) · format/lint on touch · blast-radius · verification floor · regression gate · quality floor · import-cycle check · auto-prune |
| **charter** | 0.20.1 | Know the project | doc & decisions gate · alignment floor · outcome-memory "scar tissue" · conventions · owner loop · MCP reachability probe |
| **hud** | 0.8.1 | Show | one read-only status line — health · tests · floors-off · open-Qs · solo · ckpt · context % · session-cost · branch (+unpushed) · model (`/hud:legend` decodes every symbol) |

Each plugin is independently installable · Bash + `jq` · zero build.

## Install

```
/plugin marketplace add andrewstanbury/claude-task-queue
/plugin install task-queue@andrewstanbury tidy@andrewstanbury charter@andrewstanbury hud@andrewstanbury
```

Or run `/plugin` and pick them from the **Discover** tab.

## Design

**Hooks-first** (no MCP, no skills), **token-efficient by construction** — near-zero at
rest, cost proportional to the work. Design record:
[docs/ROADMAP.md](docs/ROADMAP.md) · file map: [docs/MAP.md](docs/MAP.md).
