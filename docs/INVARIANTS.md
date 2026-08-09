# INVARIANTS — the safety/correctness net (R54 contract, pillar c)

The **invisible** contract: things the user never *sees* but that must hold. A ground-up
`advise` regen (R54) is only safe because these are captured as **executable checks** — the one
thing a regen literally cannot ignore (it fails the gate). Prose alone is droppable; a green check
is not. Everything here is enforced by `./check.sh` (bats + validators).

**Legend:** ✅ behavioral check · ⚠️ known-limit (guarded, but not by a full behavioral check —
regen MUST preserve it by contract/structure, not rely on the net).

Grouped by **risk area** (this doc's native axis). Each section notes the **UX spine** it protects
(`↳ protects:` → a flow / convention in `docs/flows/`) — same shared spine as the quality bar,
not the same buckets.

## Credential-shape scanner (R100/Pass 3: advisory, no longer a hard block)
`↳ protects:` *guardrails default-on* · flow: core-loop (the secret-gate step)

**R100/Pass 3: this is no longer an enforced invariant.** `secret-guard.sh`'s PreToolUse block is
retired; `check-secrets.sh` / the MCP `check_for_secrets` tool return the same classification, but
nothing calls them automatically and nothing they return can stop a write. The rows below describe
the SCANNER's classification behavior, not a guarantee about what gets written.

| Invariant (of the scanner's classification, not a write-time guarantee) | Check | Status |
|---|---|---|
| Anchored vendor keys (AWS/GH/Slack/Stripe/Google/PEM) classify as **BLOCK** (`exit 2`); placeholders + ordinary code pass clean; generic `name=value` only **WARN**s | `check-secrets: BLOCKs a real AWS key` · `…allows placeholder` · `…allows ordinary code` · `…generic … WARNS` | ✅ (classification only) |
| Tool-agnostic by construction — no tool_input dispatch left to bypass, whatever text it's handed is scanned the same way (R43) | `check-secrets: tool-agnostic by construction` | ✅ |
| Disable-able only by explicit opt-out; env `CLAUDE_COMPANION_SECSCAN=0` + per-repo `secret=off` flag; **isolated** per repo (no cross-repo bleed) | `…disabled via …SECSCAN=0` · `check-secrets: honors a per-repo secret=off flag — ALLOWS there but still BLOCKS elsewhere` | ✅ |
| **Fail-safe:** only an exact `^secret=off$` line disables — corruption / typo / read-error → still classifies as **BLOCK** (R50/R54) | `check-secrets FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS` | ✅ *(gap G1, closed 2026-07-17)* |
| **No fail-open dependency:** `check-secrets.sh` sources **no** lib — a broken dependency can't silently change the verdict (R50/R54) | `check-secrets is self-contained: sources no lib` | ✅ *(gap G2, closed 2026-07-17)* |

## Task store (crash-safety)
`↳ protects:` *queue-one-at-a-time* · the `tq` spine (flows: core-loop · carry-tasks-to-another-machine)

| Invariant | Check | Status |
|---|---|---|
| `tq` writes are **atomic** (temp file + `mv`), never in-place — a crash mid-write never leaves a half-file (R44) | `tq: writes go temp-file + mv, never in-place jq` | ⚠️ **textual** — the check greps the idiom's presence + the code structure is `>"$t" && mv "$t" "$f"`; a real crash-injection test is infeasible/fragile (R48). **Regen must preserve the temp+mv structure literally.** |
| Parked/blocked (`❓`/`⏳`) is a **prefix-view** over `pending`, never a `status` value — else resume classification breaks (R42) | `parked/blocked … is a prefix-view over pending, NOT a status value` | ✅ |
| `tq cancel` retracts without a false `done` or lingering `open` (file kept for audit) | `tq: cancel retracts a task` | ✅ |

## Autopilot / ship-mode (near-irreversible)
`↳ protects:` flow: hands-off-drain (autopilot → ship-mode)

| Invariant | Check | Status |
|---|---|---|
| Ship-mode **never commits to the default branch** — from HEAD-on-main *and* detached HEAD (R34/R45) | `ship-mode … NEVER main` · `ship-mode never commits to the default branch, even from detached HEAD` | ✅ |
| The **second** default-branch guard (after `checkout -b`) — last floor on never-commit-default (R45) | — | ⚠️ **unprovable** — fires only in a state `checkout -b` can't reproduce (its own failure); not unit-testable. **Preserve by its `# NEVER commit to default` comment.** |
| Ship-mode **refuses to commit a credential** (staged re-scan backstop, R34) | `ship-mode: refuses to auto-commit a hardcoded credential` | ✅ |
| Autopilot is **persisted**, and **"don't ask" is enforced again** (ask-guard.sh deny, R100/Pass 6) — but forced continuation and the no-progress/run-bound caps are NOT (stop-autopilot.sh stays retired, still R100's biggest loss) | `autopilot: toggle persists per repo, independent of other modes (R26)` · `ask-guard: autopilot ON denies AND auto-parks the question with its real options + a recommendation (R84)` | ✅ (persistence + deny) · ⚠️ (no-progress/run-bound: RETIRED, watch your own progress) |
| Ship-mode **off** → does not commit (manual now, not Stop-triggered) | `ship-checkpoint: off → does NOT commit (work stays uncommitted)` | ✅ |
| **Decisive mode (R59)** is opt-in + persisted, and while on the ask-guard **still denies** asking (it flips the *guidance* park→decide) — and is a no-op when autopilot is off | `ask-guard: DECISIVE mode swaps the guidance from park-every-decision to decide-if-reversible (R59)` | ✅ |

## Session / scope
`↳ protects:` flows: first-run (session start) · pick-up-where-you-left-off (resume)

| Invariant | Check | Status |
|---|---|---|
| Resume + tasks are **scoped to this repo** (by the store's `.root` stamp) — no cross-repo bleed | `resume: prints STEERING and resumes THIS repo's tasks only (scoped by .root) — R39` | ✅ |
| Steering **off** (per-repo flag) drops the injection but tasks/LESSONS still fire (R50) — true on BOTH the automatic (session-start.sh) and on-demand (resume.sh) paths | `steering off (per-repo flag): resume drops the working agreement (tasks/lessons unaffected, R50)` · `session-start: steering=off drops the working agreement, carried tasks unaffected (R50)` | ✅ |
| Resume (the manual, triage-handoff command) turns autopilot **off first** so a resurfaced decision isn't autopiloted (R39) — session-start.sh, the automatic path, deliberately does NOT | `manual resume: turns autopilot OFF first, announced when on and quiet when off (R39)` · `session-start: fresh start injects the FULL STEERING core + carried tasks, unlike resume it does NOT clear autopilot` | ✅ |
| Compaction re-anchors with a **short message, not the full STEERING core** (token cost, R30·d2), but the SAME cheap report tail (tasks/version-lag/LESSONS/R93/rework) as a fresh start | `session-start: post-compaction re-anchor is SHORT — queue + posture, not the full STEERING core` · `session-start: compact re-anchor carries the SAME version-lag + rework as a fresh start (R93 — a compaction IS a state clear)` | ✅ |

## Hooks / structure
`↳ protects:` cross-cutting (every path — best-effort reliability under any input)

| Invariant | Check | Status |
|---|---|---|
| Every stdin-reading hook is **best-effort** — survives empty / garbage / truncated / huge / multibyte input without breaking the triggering action (R7). Covers every remaining stdin-reading hook. | `fuzz: every stdin-reading hook survives …` · `fuzz: … multibyte / emoji` | ✅ |
| Manifests valid + versions in lockstep + shellcheck-clean + no leaked secret + files ≤300 lines | `check.sh`: JSON valid · version match · ShellCheck · gitleaks · size | ✅ |

---

## Known-limits (the net's honest edges)

Two invariants are **not** fully behaviorally checked. A ground-up regen must treat these as
**preserve-by-contract**, not "the tests will catch it":

- **G3 — `tq` atomicity** is guarded textually (idiom present) + by code structure, not by
  crash-injection. Regen must keep `jq … >"$t" && mv "$t" "$f"` — never `jq … > "$f"`.
- **G4 — R45's second default-branch guard** is unprovable (fires only on `checkout -b`'s own
  failure). Regen must keep the guard + its `# NEVER commit to default` comment.

When R54's regen mode lands (Phase 2), it must **refuse to proceed** if any ✅ check is
missing/red for the target, and must surface G3/G4 as manual-preserve items.
