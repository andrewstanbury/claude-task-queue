# Claude Code companion plugins

Four self-contained [Claude Code](https://claude.com/claude-code) plugins that let you
**vibe-code a whole project** while Claude keeps it clean, low-debt, and token-efficient
— **automatically, through hooks** — with the native task list as the one place you
steer. Built for an owner who reads no code and runs no commands.

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
| **task-queue** | 0.27.1 | Orchestrate | review loop · wireframe design preview · intent→outcome gate · open-questions tracker · cross-session resume |
| **tidy** | 0.38.1 | Change safely | format/lint on touch · blast-radius · verification floor · regression gate · quality floor · import-cycle check · auto-prune |
| **charter** | 0.19.0 | Know the project | doc & decisions gate · alignment floor · outcome-memory "scar tissue" · conventions · owner loop |
| **hud** | 0.6.0 | Show | one read-only status line — health · tests · open-Qs · context % · branch · model |

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
