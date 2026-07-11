# REQUIREMENTS — the locked / challengeable ledger

The **single source of truth** for this project's durable requirements. The other
decision surfaces (CLAUDE.md invariants, charter's recorded decisions,
[docs/ROADMAP.md](./ROADMAP.md) durable-decisions, AGENTS.md, memory) reference
entries here **by ID** instead of restating them — this file is where a requirement's
*status* lives.

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
| **R1** | 🔒 | This is a **wide-audience product**, not a personal rig. Generic (language/framework-agnostic) rules, README discoverability, and **independent per-plugin installability** are load-bearing. | 2026-07-11. Resolves the long-standing "personal tool vs product" straddle in the owner's favour of *product*. Keeps the [generic-rules invariant](../CLAUDE.md). |
| **R2** | 🔒 | A **single Requirements Ledger** (this file) is the source of truth for durable requirements; every other decision surface references it by ID. | 2026-07-11. Fixes the five-surface scatter (CLAUDE.md / charter / ROADMAP / AGENTS.md / memory). Full migration of the existing surfaces is task-queued. |
| **R3** | 🔒 | **Token efficiency stays THE defining quality attribute.** `tests/token-budget.bats` stays strict; growing a budget is a deliberate ratchet. | 2026-07-11. Reaffirmed *because* R1 chose product: a wide audience runs Haiku/Sonnet/older models and smaller context windows, where the budget earns its keep (the "1M-context makes tokens cheap" objection applies only to the owner's own Opus). |
| **R4** | 🔒 | De-duplicate cross-plugin code via a **build/packaging step: one shared source → four independently-installable plugins.** Each *packaged* plugin stays self-contained (R1 install granularity preserved). | 2026-07-11. **Retires** the *"no build step"* and *"no shared lib"* clauses of CLAUDE.md hard-invariant #1, and makes `tests/drift-guard.bats` redundant. **Supersedes** the twice-recorded "Decided against consolidating the 4 plugins" (2026-05-31 / -06-16) — but via shared *source*, not a single install, so the product's install boundaries survive. Pending implementation (task-queued); CLAUDE.md invariant #1 is edited when the build step lands, not before. |
| **R5** | 🔒 | Recommendations default to **brutal honesty + multiple-choice**, and **must name the R-IDs / architecture a recommendation touches or would change.** | 2026-07-11. Promotes the 2026-07-01 "a requirement conflict is a surfaced trade-off, names the requirement it would retire" clause from a buried rule to the default interaction. Extends it from *decisions* to *this ledger*. |

## Durable requirements & decisions (migrated 2026-07-11, per R2)

The hard invariants (from CLAUDE.md) and durable design decisions (from ROADMAP) now live
here as the canonical status record. CLAUDE.md keeps the invariant *statements* (it's the
only auto-loaded doc — R3), tagged with these R-IDs; ROADMAP's decision sections became
pointers here. Blow-by-blow history stays in `git log`.

| ID | Status | Requirement | Rationale · Retires · Supersedes |
|---|---|---|---|
| **R6** | 🔒 | Each **installed** plugin is self-contained (Claude Code installs a plugin's subdir alone, so it can only use files under its own root). | The artifact-level half of old CLAUDE.md invariant #1. **R4** retired the *"no build step / no shared source"* half — shared source is now vendored into each plugin at package time, so the installed unit stays standalone. |
| **R7** | 🔒 | **Hooks are best-effort and must never break the action that triggered them** (`set -uo pipefail`, swallow errors, exit 0 when silent). | CLAUDE.md invariant #2. A companion that breaks the user's action is worse than one that stays silent. |
| **R8** | 🔒 | task-queue's **only** write to `~/.claude/tasks` is the `tq` fallback CLI (same native format/store every reader keys off); **tidy only auto-applies behavior-preserving fixes** (formatting), surfacing everything else. | CLAUDE.md invariant #3. The `tq` fallback covers models with the native task tools gated off (`tengu_vellum_ash`); it self-routes back to native when present. |
| **R9** | 🔒 | **Rules stay generic (wide audience)** — no hardcoded language/framework/ecosystem allowlists. Delegate *recognition* to the model; hardcode only *invocation* a hook can't avoid (prefer the project's own tool); detect *structure* generically. | CLAUDE.md invariant #5; the concrete mechanism behind **R1**. An allowlist rots and biases the suite to one audience. |
| **R10** | 🔒 | **Native-first** — where Claude Code does it natively (task list, permissions/`auto`, statusLine, AskUserQuestion, subagents), use that; hooks earn their keep only where they *execute* on an event or read state a session can't see. | ROADMAP durable decision. 2026-07-10 carve-out: the `tq` fallback (**R8**) covers gated-off native task tools, self-routing back when they return. |
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
| **R22** | ⚰️ | ~~Decided against consolidating the 4 plugins into 1~~ | Retired 2026-07-11 — **superseded by R4** (shared *source* + build step, keeping four installables), which gets consolidation's de-duplication without collapsing the install boundary. |
| **R23** | 🔒 | **Anti-rework floors** are each a bounded, disable-able, **detect-not-decide** Stop-time gate (the hook supplies facts; the model judges): the tidy regression gate, charter's alignment floor, and task-queue's intent→outcome gate. Cheap pre-filters keep them quiet; each bounds itself (per-tree/per-ask consume or a per-session cap) and writes cache-only state. | ROADMAP "anti-rework floors / prevention taxonomy". |

**Not migrated, by design:** AGENTS.md (maintainer-guide prose, not discrete decisions — it *references* R-IDs) and owner **memory** (personal, cross-session, some private — it lives outside the repo and points here where it overlaps). Neither is a "decision surface" R2 subsumes.
