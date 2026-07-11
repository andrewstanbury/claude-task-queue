# REQUIREMENTS — the locked / challengeable ledger

The **single source of truth** for this project's durable requirements. CLAUDE.md
invariants and [docs/ROADMAP.md](./ROADMAP.md) reference entries here **by ID** instead
of restating them — this file is where a requirement's *status* lives. *(The 2026-07-11
ground-up rebuild collapsed the four plugins into one `companion`; entries touched by it
are annotated below — see **R24**.)*

**Status vocabulary**

- 🔒 **locked** — challenge only with explicit owner sign-off; the recommendation loop
  treats these as constraints.
- 🔓 **open** — up for challenge; the loop may propose changing these on its own signal.
- ⚰️ **retired** — no longer in force; kept for history with a pointer to what replaced it.

**The rule (R5):** every recommendation and every task-conversion **cites the R-IDs it
touches and names any it would change** — a requirement is never retired silently, in
either direction.

| ID | Status | Requirement | Rationale · Retires · Supersedes |
|---|---|---|---|
| **R1** | 🔒 | This is a **wide-audience product**, not a personal rig. Generic (language/framework-agnostic) rules and README discoverability are load-bearing. | 2026-07-11. Resolves the "personal tool vs product" straddle in favour of *product*. *(Rebuild R24: "independent **per-plugin** installability" is now moot — one `companion` plugin. Product + generic rules stand.)* |
| **R2** | 🔒 | A **single Requirements Ledger** (this file) is the source of truth for durable requirements; CLAUDE.md and ROADMAP reference it by ID. | 2026-07-11. Fixes the old five-surface scatter (achieved: charter's decisions surface was deleted in the rebuild; CLAUDE.md + ROADMAP now point here). |
| **R3** | 🔓 | Token efficiency is a **core value**, but is no longer enforced as a per-hook character-budget NFR. | 2026-07-11, **reshaped by the rebuild (R24)**: `tests/token-budget.bats` and the per-hook ratchets were **retired** — that apparatus defended a cost the steering-doc-read-once-per-session model doesn't incur, and it drove prose into cryptic, unmaintainable anchors. Efficiency now means "the steering doc stays lean," not a CI char-count. Downgraded 🔒→🔓 (was THE quality attribute; now one value among several). |
| **R4** | ⚰️ | ~~De-duplicate cross-plugin code via a build step → four installable plugins~~ | Retired 2026-07-11 by the rebuild (**R24**): there are no longer *four* plugins to de-duplicate across — one `companion` plugin means no cross-plugin duplication and **no build step**. The problem R4 solved was dissolved, not solved. |
| **R5** | 🔒 | Recommendations default to **brutal honesty + multiple-choice**, and **must name the R-IDs / architecture a recommendation touches or would change.** | 2026-07-11. Promotes the 2026-07-01 "a requirement conflict is a surfaced trade-off, names the requirement it would retire" clause from a buried rule to the default interaction. Extends it from *decisions* to *this ledger*. |

## Durable requirements & decisions (migrated 2026-07-11, per R2)

The hard invariants (from CLAUDE.md) and durable design decisions (from ROADMAP) now live
here as the canonical status record. CLAUDE.md keeps the invariant *statements* (it's the
only auto-loaded doc — R3), tagged with these R-IDs; ROADMAP's decision sections became
pointers here. Blow-by-blow history stays in `git log`.

| ID | Status | Requirement | Rationale · Retires · Supersedes |
|---|---|---|---|
| **R6** | 🔒 | The plugin is self-contained (Claude Code installs a plugin's subdir alone, so it can only use files under its own root). | Old CLAUDE.md invariant #1. *(Rebuild R24: trivially satisfied now — there is **one** plugin, so there was never cross-plugin sharing to forbid, no build step, and the `drift-guard` that policed the duplication is gone.)* |
| **R7** | 🔒 | **Hooks are best-effort and must never break the action that triggered them** (`set -uo pipefail`, swallow errors, exit 0 when silent). | CLAUDE.md invariant #2. A companion that breaks the user's action is worse than one that stays silent. |
| **R8** | 🔒 | **`tq` is THE task queue** — the companion owns its own task store (`~/.claude/companion/tasks`, not `~/.claude/tasks`) and does **not** use Claude Code's native task tools. `tq add/doing/note/done/list/report` is the whole queue; the report fires on every state change; each session dir is root-stamped so resume scopes to a repo with no native transcript. | 2026-07-11 (owner directive: *actively avoid native tasks*). Was a *fallback* for gated models; now the sole mechanism. Reverses the task-queue half of **R10** — see there. |
| **R9** | 🔒 | **Rules stay generic (wide audience)** — no hardcoded language/framework/ecosystem allowlists. Delegate *recognition* to the model; hardcode only *invocation* a hook can't avoid (prefer the project's own tool); detect *structure* generically. | CLAUDE.md invariant #5; the concrete mechanism behind **R1**. An allowlist rots and biases the suite to one audience. |
| **R10** | 🔒 | **Native-first for hooks, statusLine, AskUserQuestion, and permissions/`auto`** — use Claude Code's native mechanism there; hooks earn their keep only where they *execute* on an event or read state a session can't see. **Exception: NOT the task queue** — the companion owns its queue (**R8**). | ROADMAP durable decision. 2026-07-11: the "native task list" clause was **retired** at owner directive (actively avoid native tasks — they're gated off on the newest models and the queue should be self-owned and stable). Native-first still holds everywhere else. |
| **R11** | 🔒 | **Run in auto** — `permissions.defaultMode: "auto"` (auto-approve with background safety checks) + a hard `deny` set (`rm -rf /`, `~`) + an `ask` set (force-push, `reset --hard`). | ROADMAP durable decision — the safe-autonomy posture the owner asked for. |
| **R12** | 🔒 | **Proportionality over maximalism** — every practice scaled to the change's complexity/risk. | ROADMAP durable decision. |
| **R13** | 🔒 | **Verification + simplicity over methodology labels** — encode the essence (SOLID/DDD/YAGNI, boring & reversible) as concrete generation-time rules (no-seam + deletion-test; unit-cohesion + complexity-altitude), **not** as methodology checkers (a "SOLID checker" isn't mechanically viable). | ROADMAP durable decision. |
| **R14** | 🔒 | **Non-technical-owner posture** — autonomy on the reversible, plain-language consent on the consequential (the line is reversibility + cost + data-safety); verification must be **observable** (demo it working, not read code). | ROADMAP durable decision. |
| **R15** | 🔒 | **Subtractive force + quiet hooks** — bootstrap-once (policy in CLAUDE.md, `claude-companion` marker) then re-anchor in one line; *state* (carry-over, drift) is never suppressed, only policy prose. | ROADMAP durable decision; the mechanism behind **R3**'s per-prompt leanness. |
| **R16** | 🔒 | **Clean ≠ correct** — weigh new work against the recorded direction (this ledger + decisions + roadmap) before it lands, at both intent-time and outcome-time. | ROADMAP durable decision. |
| **R17** | 🔒 | **Critique posture: selective, substantive-gated, bidirectional, self-challengeable** — EVALUATE before executing; challenge both recorded constraints *and* the owner's own accumulated bias when they force a poor design; object only on real signal. The mandate itself stays challengeable. | ROADMAP durable decision (2026-06-19); underpins **R5**. |
| **R18** | 🔒 | **Decided against a charter doc-inventory state file** — the install boundary forces a fallback detector anyway, so a state file is net-additive; chose the CI drift-guard instead. | ROADMAP "decided against" (2026-06-01). *(May be revisited under R4's build step, which removes the duplication drift-guard polices.)* |
| **R19** | 🔒 | **Decided against a hard plugin-owned destructive-action gate** — gating is **native** (`permissions.deny`/`ask` + `auto`). Narrow exception: tidy's PreToolUse **secret floor** blocks a write, because native permissions scan commands/style but nothing scans file *content* for committed credentials, and a leaked key is irreversible. | ROADMAP "decided against" (2026-06-16; secret-floor exception 2026-06-21). |
| **R20** | 🔒 | **Decided against native plan mode** for the present-before-work step — the task-queue's interpret→present→approve loop is used instead (plan mode is read-only + all-or-nothing per session; the owner wants to run in auto and review only the queue interpretation). | ROADMAP "decided against" (2026-06-16). |
| **R21** | 🔒 | **Decided against one single CLAUDE.md as the only doc** — would fight charter's separate-file detection (it would nag "missing map/roadmap"). Use a few lean Claude-context files (CLAUDE.md + map + decisions/ledger + per-plugin CONTRACTs). | ROADMAP "decided against" (2026-06-16). |
| **R22** | ⚰️ | ~~Decided against consolidating the 4 plugins into 1~~ | Fully reversed 2026-07-11 by the rebuild (**R24**): consolidation to **one** plugin actually happened — going further than R4's "shared source, four installables." The 2026-05-31/-06-16 "delete first, then judge; revisit only if it bites" *did* bite. |
| **R23** | 🔒 | **Anti-rework floors** are bounded, disable-able, **detect-not-decide** gates that supply facts for the model to judge. | ROADMAP "prevention taxonomy". *(Rebuild R24: the only floor kept as **enforced code** is the PreToolUse **secret gate** — it blocks. The others (alignment, intent→outcome, regression) were **advisory** Stop-hook prose that the model could skip; they now live as guidance in `STEERING.md`, not as hooks — the honest home for un-enforceable steering.)* |
| **R24** | 🔒 | **Architecture: one steering document + a tiny enforced core.** All steering (queue discipline, critique/recommendation posture, clean-code standards, autopilot) lives in **one** file (`plugins/companion/STEERING.md`), put in context once per session. Only behavior that must **execute or block** is code: the secret gate, cross-session resume, and the `tq` queue fallback. | 2026-07-11 ground-up rebuild (owner-committed). The old system was prompt-injection middleware whose ~95% advisory prose was scattered across ~15 hooks and four plugins, defended by a token-budget NFR and a drift-guard that policed self-imposed duplication — none of it verifiable. Collapsed ~12,500 lines → a few hundred. Separates the reliable (enforced) from the ignorable (steering) so each is honest about what it is. Supersedes/reshapes **R1, R3, R4, R6, R22, R23**. |

| **R25** | 🔒 | **Clean-as-you-touch is a real hook, not just steering.** A PostToolUse[Write\|Edit] pass (`bin/touch.sh`) formats the edited file with the project's own formatter (behavior-preserving), surfaces its blast radius (dependents), and flags over-budget size. Plus an on-demand `/companion:audit` for a whole-project sweep. | 2026-07-11 (owner directive, after the rebuild). A **conscious partial-reversal of R24's austerity**: the owner values the *mechanical* clean-up (format is genuine execution; blast/size are nudges) over pure advisory steering. Kept lean + disable-able (`CLAUDE_COMPANION_TOUCH=0`). |

**Not in the ledger, by design:** AGENTS.md (maintainer-guide prose) and owner **memory** (personal, cross-session, lives outside the repo).
