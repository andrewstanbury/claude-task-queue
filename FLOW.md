# Companion workflow — current state

_Derived from the repo @ `42863c5` by `./flow.sh`. Manual refresh: `./flow.sh` (or `make flow`). No cron — pull, not push._

**Always-on** — native permissions `defaultMode=auto · deny(4) · ask(3) · agent-mode=off` · statusLine → `hud` 0.4.0

## The flow

```text
  ● SessionStart      → charter-standard · tq-resume · tidy-standard
  ◆ UserPromptSubmit  → tq-capture
      loop: INTERPRET → DECOMPOSE → JUDGE → PRESENT → TaskCreate
  ⚙ work the queue      (native task list)
  ├ each edit  →        tidy-touch
  └ on finish  →        tidy-verify   (tests block-until-green + throttled prune)
```

## What fires when

### ● SessionStart

| plugin | script | what it does |
|---|---|---|
| `charter` 0.17.0 | `charter-standard.sh` | gate substantive work on documented quality attributes. |
| `task-queue` 0.24.0 | `tq-resume.sh` | prime the session's task queue. The whole plugin. |
| `tidy` 0.33.0 | `tidy-standard.sh` | set the clean-as-you-go standard, once per session. |

### ◆ UserPromptSubmit

| plugin | script | what it does |
|---|---|---|
| `task-queue` 0.24.0 | `tq-capture.sh` | the interpret→present→approve loop. |

**The review loop:** INTERPRET → DECOMPOSE → JUDGE → PRESENT → TaskCreate

### ⚙ PostToolUse

| plugin | script | what it does |
|---|---|---|
| `tidy` 0.33.0 | `tidy-touch.sh` | tidy the file that was just edited. |

### ✓ Stop

| plugin | script | what it does |
|---|---|---|
| `tidy` 0.33.0 | `tidy-verify.sh` | the verification floor. When Claude finishes, if the working tree |

## On demand

- **commands** — `/charter:align`, `/hud:setup`
- **toggles** — `tq-agent`, `tq-pause`

---
_`task-queue` 0.24.0 · `tidy` 0.33.0 · `charter` 0.17.0 · `hud` 0.4.0_
