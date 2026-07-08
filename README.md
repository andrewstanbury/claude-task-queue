# Claude Code companion plugins

Four self-contained [Claude Code](https://claude.com/claude-code) plugins that keep a
vibe-coded project clean, low-debt, and token-efficient — automatically, through hooks.
Built for an owner who reads no code; the native task list is the one place you steer.

| Plugin | Ver | Role |
|---|---|---|
| **task-queue** | 0.42.0 | Orchestrate — native task list as a live queue: per-prompt review loop, enforced design-preview + parked-review gates, two deferral markers (❓ decisions / ⏳ owner-blocked), lean autopilot drain (park-rule sent once, not per continuation), queue-aware agent fan-out, one-command ship |
| **tidy** | 0.42.0 | Change safely — format/lint on touch, blast-radius, verification floor (runs your existing tests), opt-in regression gate, quality floor, auto-prune + on-demand `/tidy:audit` (tests are opt-in, never forced) |
| **charter** | 0.22.0 | Know the project — doc & decisions gate, alignment floor, scar-tissue memory, MCP reachability probe |
| **hud** | 0.19.0 | Show — one read-only status line (health, feature state, tests, ❓ decisions + ⏳ owner-blocked, tokens, branch) |

Each plugin is independently installable · Bash + `jq` · zero build.

## Install

```
/plugin marketplace add andrewstanbury/claude-task-queue
/plugin install task-queue@andrewstanbury tidy@andrewstanbury charter@andrewstanbury hud@andrewstanbury
```

Or run `/plugin` and pick them from the **Discover** tab.
