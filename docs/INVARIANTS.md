# INVARIANTS — the safety/correctness net (R54 contract, pillar c)

The **invisible** contract: things the user never *sees* but that must hold. A ground-up
`advise` regen (R54) is only safe because these are captured as **executable checks** — the one
thing a regen literally cannot ignore (it fails the gate). Prose alone is droppable; a green check
is not. Everything here is enforced by `./check.sh` (bats + validators).

**Legend:** ✅ behavioral check · ⚠️ known-limit (guarded, but not by a full behavioral check —
regen MUST preserve it by contract/structure, not rely on the net).

Grouped by **risk area** (this doc's native axis). Each section notes the **UX spine** it protects
(`↳ protects:` → a happy path / design pattern in `docs/UX.md`) — same shared spine as `NFR.md`,
not the same buckets.

## Irreversible-harm gate (the one hard block)
`↳ protects:` *guardrails default-on* · UX Path 2 (the secret-gate step)

| Invariant | Check | Status |
|---|---|---|
| Anchored vendor keys (AWS/GH/Slack/Stripe/Google/PEM) are **blocked** (`exit 2`); placeholders + ordinary code pass; generic `name=value` only **warns** | `secret gate: blocks a real AWS key` · `…allows placeholder` · `…allows ordinary code` · `…generic … WARNS` | ✅ |
| Gate covers **every** content tool — Write/Edit **and** NotebookEdit (`.new_source`) — no bypass (R43) | `secret gate: covers NotebookEdit's new_source` | ✅ |
| Disable-able only by explicit opt-out; env `CLAUDE_COMPANION_SECSCAN=0` + per-repo `secret=off` flag; **isolated** per repo (no cross-repo bleed). *(The `/companion:features` CLI was removed 2026-07-18, R50; the flag mechanism + the gate's read of it are unchanged — settable by hand or a re-add.)* | `…disabled via …SECSCAN=0` · `secret gate: honors a per-repo secret=off flag — ALLOWS there but still BLOCKS elsewhere` | ✅ |
| **Fail-safe:** only an exact `^secret=off$` line disables — corruption / typo / read-error → gate stays **active** (R50/R54) | `secret gate FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS` | ✅ *(gap G1, closed 2026-07-17)* |
| **No fail-open dependency:** `secret-guard.sh` sources **no** lib — a broken dependency can't disable the gate (R50/R54) | `secret gate is self-contained: sources no lib` | ✅ *(gap G2, closed 2026-07-17)* |

## Task store (crash-safety)
`↳ protects:` *queue-one-at-a-time* · the `tq` spine (UX Path 2/4)

| Invariant | Check | Status |
|---|---|---|
| `tq` writes are **atomic** (temp file + `mv`), never in-place — a crash mid-write never leaves a half-file (R44) | `tq: writes go temp-file + mv, never in-place jq` | ⚠️ **textual** — the check greps the idiom's presence + the code structure is `>"$t" && mv "$t" "$f"`; a real crash-injection test is infeasible/fragile (R48). **Regen must preserve the temp+mv structure literally.** |
| Parked/blocked (`❓`/`⏳`) is a **prefix-view** over `pending`, never a `status` value — else resume classification breaks (R42) | `parked/blocked … is a prefix-view over pending, NOT a status value` | ✅ |
| `tq cancel` retracts without a false `done` or lingering `open` (file kept for audit) | `tq: cancel retracts a task` | ✅ |

## Autopilot / ship-mode (near-irreversible)
`↳ protects:` UX Path 3 (hands-off drain → ship-mode)

| Invariant | Check | Status |
|---|---|---|
| Ship-mode **never commits to the default branch** — from HEAD-on-main *and* detached HEAD (R34/R45) | `ship-mode … NEVER main` · `ship-mode never commits to the default branch, even from detached HEAD` | ✅ |
| The **second** default-branch guard (after `checkout -b`) — last floor on never-commit-default (R45) | — | ⚠️ **unprovable** — fires only in a state `checkout -b` can't reproduce (its own failure); not unit-testable. **Preserve by its `# NEVER commit to default` comment.** |
| Ship-mode **refuses to commit a credential** (staged re-scan backstop, R34) | `ship-mode: refuses to auto-commit a hardcoded credential` | ✅ |
| Autopilot is **enforced + persisted** (ask-guard deny + Stop auto-continue) and **can't spin forever** (no-progress cap, R26) | `autopilot: toggle persists, and is enforced` · `autopilot: Stop yields after the no-progress cap` | ✅ |
| Ship-mode **off** → Stop does not auto-commit | `ship-mode: off → Stop does NOT auto-commit` | ✅ |

## Session / scope
`↳ protects:` UX Path 1 (first run / session start) · Path 4 (resume)

| Invariant | Check | Status |
|---|---|---|
| Resume + tasks are **scoped to this repo** (by the store's `.root` stamp) — no cross-repo bleed | `session start: … resumes THIS repo's tasks only (scoped by .root)` | ✅ |
| Steering **off** (per-repo flag) drops the injection but resume/LESSONS still fire (R50) | `steering off (per-repo flag): SessionStart drops the working agreement (resume/lessons unaffected)` | ✅ |
| Resume turns autopilot **off first** so a resurfaced decision isn't autopiloted (R39) | `manual resume: turns autopilot OFF first` | ✅ |
| Compaction re-anchors with **queue+pointer, not full STEERING** (token cost, R30·d2/R32) | `session start: re-anchors on a compaction with queue+pointer, NOT the full STEERING` | ✅ |

## Hooks / structure
`↳ protects:` cross-cutting (every path — best-effort reliability under any input)

| Invariant | Check | Status |
|---|---|---|
| Every stdin-reading hook is **best-effort** — survives empty / garbage / truncated / huge / multibyte input without breaking the triggering action (R7) | `fuzz: every stdin-reading hook survives …` · `fuzz: … multibyte / emoji` | ✅ |
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
