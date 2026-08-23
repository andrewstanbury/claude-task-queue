# ADR — decisions, architecture choices, and rejected options

Moved out of `docs/adr/PROVENANCE.md` on 2026-08-02. These are **history, not requirements**:
there is nothing here to verify, only something to remember. Keeping them in the ledger is
what made "which tests verify R__?" an archaeology problem — half the table had no answer
because half the table was never a requirement.

Ordering and IDs are unchanged, so every existing reference in code comments, commit messages
and command prose still resolves.

## R4 — RETIRED ⚰️

~~De-duplicate cross-plugin code via a build step → four installable plugins~~ | Retired 2026-07-11 by the rebuild (**R24**): there are no longer *four* plugins to de-duplicate across — one `companion` plugin means no cross-plugin duplication and **no build step**. The problem R4 solved was dissolved, not solved.

## R18 — RETIRED ⚰️

~~**Decided against a charter doc-inventory state file** — chose the CI drift-guard instead.~~ | ROADMAP "decided against" (2026-06-01). **Retired 2026-07-17:** obsolete on every axis — "charter" was deleted by **R24**, the **CI drift-guard it endorsed was also deleted by R24** ("the drift-guard that policed self-imposed duplication — none of it verifiable"), and its forward-pointer was to **R4** (itself ⚰️). A 🔒 entry endorsing a deleted mechanism for a deleted subsystem cannot be in force. The underlying question, if it ever returns, belongs to R24/R52.

## R19 — DECISION 🔒

**Decided against a hard plugin-owned destructive-action gate** — gating is **native** (`permissions.deny`/`ask` + `auto`). Narrow exception: the PreToolUse **secret floor** (`secret-guard.sh`) blocks a write, because native permissions scan commands/style but nothing scans file *content* for committed credentials, and a leaked key is irreversible. | ROADMAP "decided against" (2026-06-16; secret-floor exception 2026-06-21). **Reworded 2026-07-17:** dropped the dead 4-plugin name "tidy" → `secret-guard.sh`. The live surface of this exception is now carried by **R43** (all content tools), **R50** (feature flag), **R32·6** (generic-warn vs anchored-block); R19 remains the origin anchor.

## R20 — DECISION 🔒

**Decided against native plan mode** for the present-before-work step — the task-queue's interpret→present→approve loop is used instead (plan mode is read-only + all-or-nothing per session; the owner wants to run in auto and review only the queue interpretation). | ROADMAP "decided against" (2026-06-16).

## R21 — DECISION 🔒

**Decided against one single CLAUDE.md as the only doc** — use a few lean Claude-context files (CLAUDE.md + map + this ledger + LESSONS/GLOSSARY on demand). | ROADMAP "decided against" (2026-06-16). **Reworded 2026-07-17:** the recorded *rationale* was dead — "charter's separate-file detection" no longer exists (R24 deleted charter) and "per-plugin CONTRACTs" was 4-plugin-era (one plugin, one STEERING.md now). The *decision* still holds for a **current** reason: CLAUDE.md is the only auto-loaded doc (**R3**), so keep it lean and split the rest by responsibility (**R24**), loaded on demand.

## R22 — RETIRED ⚰️

~~Decided against consolidating the 4 plugins into 1~~ | Fully reversed 2026-07-11 by the rebuild (**R24**): consolidation to **one** plugin actually happened — going further than R4's "shared source, four installables." The 2026-05-31/-06-16 "delete first, then judge; revisit only if it bites" *did* bite.

## R24 — DECISION 🔒

**Architecture: one steering document + a tiny enforced core.** All steering (queue discipline, critique/recommendation posture, clean-code standards, autopilot) lives in **one** file (`plugins/companion/STEERING.md`), put in context once per session. Only behavior that must **block, inject, or guarantee control-flow** is code: the secret gate (block), session-start injection + cross-session resume (inject — session-boundary I/O the model can't self-perform), autopilot (control-flow), and the `tq` queue. | 2026-07-11 ground-up rebuild (owner-committed). The old system was prompt-injection middleware whose ~95% advisory prose was scattered across ~15 hooks and four plugins, defended by a token-budget NFR and a drift-guard that policed self-imposed duplication — none of it verifiable. Collapsed ~12,500 lines → a few hundred. Separates the reliable (enforced) from the ignorable (steering) so each is honest about what it is. Supersedes/reshapes **R1, R3, R4, R6, R22, R23**. **Amended 2026-07-17 by R52:** the *binding* content of R24 is the **discipline** — tiny enforced core, one steering doc, reliable-vs-ignorable kept separate, no seam-sprawl. The **single-plugin *packaging*** is **no longer a requirement** (downgraded to current-state fact): a deliberate future extraction (e.g. shipping `tq` standalone) is a fair, un-blocked option and does **not** reverse R24 — provided it honors the anti-sprawl principle. What R24 forbids is *unmotivated* fragmentation, not packaging per se.

## R25 — RETIRED ⚰️

~~**Clean-as-you-touch is a real hook — format-only** (reshaped by **R28**). A PostToolUse[Write\|Edit] pass (`bin/touch.sh`) formats the edited file with the project's own formatter — the one genuine *execution* worth a hook.~~ | 2026-07-11 (owner directive, after the rebuild); **reshaped 2026-07-12 by R28**; **retired 2026-07-17 by R51.** Originally the hook also *surfaced blast radius and flagged over-budget size*; R28 moved those nudges to STEERING and left `touch.sh` doing only the format. **R51 then retired `touch.sh` entirely** (owner directive to move away from advisory hooks): formatting is a low-stakes, reversible convenience — a *nudge*, not an irreversible guarantee — so it belongs in STEERING like every other judgment call, leaving the enforced core with **no *execute* hook at all** (only block / inject / control-flow). Whole-project cleanliness sweeps remain in `/companion:advise`.

## R27 — RETIRED ⚰️

~~Two enforced work-gates (design-preview + return-review) + one advisory intent→outcome reminder, as PreToolUse/PostToolUse/UserPromptSubmit hooks.~~ | Retired 2026-07-12 by **R28** (owner directive), one day after it landed. The gates enforce *workflow judgment* and the reminder is a *nudge* — both belong in STEERING under the R28 principle, not in hooks. Deleted `work-guard.sh`, `prompt.sh`, `intent-note.sh`; stripped the gate helpers (`has_parked`, `*_flag`, `looks_visual`, `decisions_path`) from `lib/companion.sh`; removed the 🎨/🔒 status-line icons; reverted `ask-guard.sh` to autopilot-only. The three clauses live on in STEERING as prose (they always did — the gates were redundant enforcement). A worked example of the thrash R28 exists to stop.

## R28 — DECISION 🔒

**The hook/steering boundary is decided by a component's *nature*, not case-by-case.** Enforced **code** ONLY for what must **block** (the secret gate's `exit 2`), **guarantee control-flow** (autopilot), or perform **session-boundary I/O the model can't do itself** (session-start injection + resume). Everything that is **judgment** (wireframe-first, weigh-against-recorded-direction, present-parked-first) or an **advisory nudge** (blast-radius, size, outcome-recap, formatting) is **STEERING** — prose the model reads once per session and applies. The deciding rule: *block / control-flow / session-boundary-I/O → hook; judgment or nudge → steering.* | 2026-07-12 (owner directive). Re-affirms the **R24** line after the R25/R27 drift bolted hooks onto nudges and workflow-judgment (and after a session of thrash — one gate flipped block→advisory→steering in an afternoon). **Retires R27** (design/return gates + intent reminder → STEERING), **reshapes R25** (touch is format-only; blast/size → STEERING), and **vindicates R23** (intent→outcome was always un-enforceable steering). **R26 autopilot stays enforced** — a control-flow guarantee against the model's own helpfulness bias is neither a nudge nor mere judgment. The rule exists to end the re-litigation, not to be re-argued per feature. **Reworded 2026-07-17 (R51/R52 sweep):** the old text named "**execute** (the formatter pass)" as a category — but **R51 deleted the formatter pass**, leaving *execute* with no members, so the stale example was actively misleading a reader of THE dividing rule. Recast as **block / control-flow / session-boundary-I/O**: "inject" is **not enforcement** (it delivers the *ignorable* steering layer) — its honest justification is session-boundary I/O the model can't self-perform, not that it "guarantees" anything. The **principle is unchanged and stays locked**; only the category scheme + dead example were fixed.

## R30 — DECISION 🔓

**Claude-first refinements — 9 owner-decided deltas (all built, 1.7.0–1.9.0).** A ground-up-redesign pass (goal: "designed primarily for the agent that runs it, similar UX + code quality") produced 9 selected changes: **(1)** `tq` tasks gain a `done-when` acceptance field; **(2)** re-inject the queue on context compaction (`PreCompact` + `SessionStart[compact]`); **(3)** STEERING → hybrid *checklist-header + prose*; **(4)** formatter = detect the project's own command (pre-commit / package.json / Make), fall back to the per-ext table; **(5)** `/companion:audit` → multi-agent workflow; **(6)** challenge posture → a required *risk / what-changes / R-IDs* slot in `ship-it` **plus** a devil's-advocate sub-agent for consequential changes; **(7)** a curated, model-maintained `LESSONS.md` injected at SessionStart; **(8)** a strict CI lane (bash-3.2 · `set -u` · no formatters · no git identity) + a hook-fuzz test; **(9)** the status-line beacon animates *on activity only* (static, no timer, when idle). | 2026-07-12 (owner directive, decided via a one-at-a-time recommendation menu). Recorded per **R5**; **build pending and sequenced in batches** — several touch hooks/schema/CI, so not one mega-change. Deltas 3/6/7 sharpen **R5/R17/R28**; 4 sharpens **R9**; 8 is the CI-robustness lesson from the 1.4.x macOS/jq bugs. Each delta ships with its own tests + docs; this entry tracks the set until built, then splits into per-delta entries or updates in place. 🔓 while unbuilt — fair to re-sequence or drop a delta. *(**All 9 built + shipped** across 1.7.0–1.9.0: Batch 1 — d7 `LESSONS.md` · d9 activity-only beacon · d4 formatter-detect; Batch 2 — d1 `done-when` · d3 STEERING checklists · d8 CI fuzz + strict lane; Batch 3 — d2 compaction re-anchor · d6 challenge slot + devil's-advocate · d5 audit sub-agent panel. Now shipped.)* **Demoted to 🔓 as a build-tracker (2026-07-17):** R30 promised to "split into per-delta entries" once built and never did — it is a 9-item **changelog frozen at 🔒**, and several sub-deltas were since reversed/refined elsewhere (d2's PreCompact half + d4 + d5 + d9 by **R32**; d1's render half by **R47**). Its live survivors (d3 STEERING format, d6 challenge slot, d7 LESSONS, d8 CI lane) are folded into STEERING/R48 — treat those as authoritative, not this bundle. Kept 🔓 for history, non-binding.

## R32 — DECISION 🔓

**`advise` self-critique bundle — 9 owner-picked fixes, all shipped in 2.0.0.** d1 statusline `IFS=$'\t'` (confirmed bug → R46) · d2 `touch.sh` per-ext only · d3 compaction re-inject = queue+LESSONS+pointer, not full STEERING · d4 delete `pre-compact.sh` · d5 refreshInterval 1→3 · d6 secret-guard generic rule → warn, anchored keys still block (→ R43/R50) · d7 `tq cancel` · d8 audit merged into advise · d9 README polish. | 2026-07-12, via `advise` dogfooding itself. Demoted 🔓 2026-07-17: a shipped changelog, not a constraint — durable survivors promoted (R46, R43/R50); d2 voided by R51 (`touch.sh` deleted). History, non-binding; R46/R43/R50/R51 are authoritative.

## R45 — RETIRED ⚰️

~~**`stop-autopilot.sh`'s second default-branch check (after `checkout -b`) is deliberate defense-in-depth, not dead code.**~~ The re-read + re-check of the current branch before ship-mode commits must stay. | 2026-07-13 — surfaced by `/companion:document` (R41), provenance `inferred` (owner-confirmed). **Why:** it is the last floor on **R34**'s absolute "never commit to the default branch." If any edge case (a failed `checkout -b`, detached HEAD, empty `rev-parse`) left HEAD on the default, ship-mode would `git commit` straight onto `main`. Cheap insurance on a near-irreversible invariant. The "never commit to default" outcome is exercised from both entry paths (HEAD-on-`main`, pre-existing; and detached-HEAD → the checkpoint lands off-default with `main` untouched). The **second** guard specifically only fires in a state `checkout -b` can't reproduce (its own failure), so it isn't cleanly unit-testable — it's protected by its inline `# NEVER commit to default` comment + this entry. Don't delete it as "dead code." **Retired from the ledger 2026-07-17:** a "don't refactor this line" note about one defensive line is a code-comment/LESSONS concern, not a durable *decision* (a 🔒 per defensive line is unbounded growth). The line **stays** (its comment protects it); the durable requirement is **R34**, still exercised by the R45 bats test.

## R46 — RETIRED ⚰️

~~**Tab-delimited `read`s use `IFS=$'\t'` — repo-wide.**~~ Any `read` splitting a tab-joined jq line whose last field is free text (a subject) must set `IFS=$'\t'`. | 2026-07-13 — surfaced by `/companion:document` (R41). **Why:** the trailing subject can carry spaces; a default-IFS split corrupts it — the confirmed **R32·1** space-in-value bug the status line already hit. `stop-autopilot.sh`'s counts-parse silently relied on numeric leading fields; hardened to match the `statusline.sh` convention. **No dedicated test:** with the subject as the trailing `read` field the default-IFS split still works today, so a test would pass with *or* without the fix (non-discriminating). Protected by the `IFS` change + the inline code comment + this entry; the existing `stop-autopilot` tests cover regressions. **Retired from the ledger 2026-07-17 → moved to `LESSONS.md`:** a repo-wide coding-convention "watch this trap" is LESSONS content, not a decision, and it was triple-homed (code + comment + ledger). The `IFS` change + comments stay; one `LESSONS.md` line now carries the gotcha.

## R51 — DECISION 🔒

**No advisory hooks; recommendation-driven pick-from-CLI is the default interaction.** (1) `touch.sh` deleted (retires R25) — the enforced core has NO execute member: **block · inject · control-flow** only (sharpens R28). Accepted risk: formatting is now model-recall; the advise sweep is the fallback. (2) Reaffirms **R48** (spine kept; only touch.sh's tests removed). (3) Options-as-default-shape + context nudges (debt→task · blast→split · repetition→autopilot) + brutal-honest always — STEERING prose. Platform constraint: plugins cannot inject prompt chips — only SessionStart context, statusLine, `AskUserQuestion`. | 2026-07-17. "Remove all hooks" reconciled honestly: the nudge engine IS the injection hook. Composes R24 R28 R48 R49.

## R54 — DECISION 🔓

**Direction: contract-preserving regenerative `advise` — build the invariant tier FIRST.** The north star (owner-agreed) is that `/companion:advise`'s objective becomes *preserve the contract, treat everything else as disposable and fair to redesign from the ground up.* **The contract has THREE pillars, not two:** **(a) the UX record** (what the user sees/experiences), **(b) agreed NFRs / quality attributes** (only those the owner intentionally reviewed and agreed — R53 anti-laundering), and **(c) safety/correctness invariants as executable *checks*** — the things the user never sees but that must hold (secret gate fail-safe, `tq` atomic writes, autopilot-never-commits-default, cross-repo scope isolation). Pillar (c) is the one the naive "UX + NFRs only, ignore the rest" framing omits — and a ground-up regen that omits it *silently deletes* those invariants (a leaked key, a corrupted store). So "ignore everything else" is rejected in favour of "**unconstrained *except by the contract***": regen must reproduce the UX, meet the NFRs, and pass every invariant check. **Sequencing (owner-agreed, non-negotiable): checks first, THEN regen-by-default** — the invariant-check tier must exist and be proven before `advise` may default to regeneration; regen is a **confirmed, bounded, check-gated** operation, never a silent auto-rewrite. | 2026-07-17 (owner directive). **Why:** the principle is a clean generalization of **R53** (only intentionally-agreed → durable; everything else is disposable) and the R41 tiering (check › 🔒 › 🔓). But it only works if the *invisible* invariants are captured as checks — which is why this session's audit deliberately kept R44/R45/R50's fail-safes locked. **The safe-sequencing was reached after pushback:** the owner's first framing (UX+NFRs only, ignore the rest, regen by default *now*) was challenged as a footgun; the owner agreed to build the contract+invariant tier first. **Composes with R41** (`document` does the contract triage + tagging {UX-contract | agreed-NFR | safety-invariant | incidental}), **R48** (the test suite IS the invariant net), **R29** (advise), **R53** (anti-laundering). **Build-pending** (kept 🔓 per the R30/R32 lesson — no 🔒 build-bundle); the concrete pieces (UX record, invariant checks, advise reframe) earn their own entries when built.

## R56 — DECISION 🔓

**Complete the behavior net before trusting whole-app `redesign` — but the command prose has a hard ceiling.** `redesign`'s D0 gate correctly **stopped** a blind whole-app rebuild of this mature app: the net pins the *safety* invariants but not every *observable behavior* — proven by the statusline regen silently dropping the autopilot-beacon (a green rebuild that regressed the UX). Decision: **characterize the executable core** (`bin/`+`lib` — write behavior-pinning tests for the gaps, like the beacon test) **and structurally-guard the command prose** (each command prompt must retain its critical gate steps — a textual check like R44/G2). **The command layer is fundamentally NOT blind-regenerable** — a prompt's behavior is *Claude's judgment*, unverifiable by a check (R28: prose is ignorable-by-nature); the ceiling is structural guards + always bounded-regen-with-human-verify (R5). So whole-app `redesign` becomes safe for the **core**, never for the **commands**. | 2026-07-17 (owner directive, after trying `/companion:redesign` — D0 stopped it, owner chose "complete the net first"). Essentially the deferred **R48** test-authoring project, scoped by this ceiling. **Composes with R54/R55** (the net *is* the gate), **R48** (regression-gate — this backfills it), **R28** (prose = judgment = unverifiable). Build-pending, phased: **(1)** behavior-coverage audit of the core → gap list; **(2)** characterization tests for the gaps; **(3)** structural guards for the command prompts. **Phases 1–2 largely done (2026-07-23, via `/companion:cover`):** the audit found the core net **strong** (83 bats) — every `bin/` script's primary observable behavior guarded; only two candidate gaps surfaced, one a **false alarm** (LESSONS injection R30·d7 was already pinned by the session-start test's `GOTCHA_MARKER` assertion) and one **real+closed** (`ship.sh preflight` deepened to assert the R60 export wrote+carried the queue and the summary ran). Phase 3 (command-prose structural guard) shipped as the R56-P3 bats test. **Remaining:** whole-app `redesign` is still *unproven on a real run* — the gap now is exercising it, not missing core tests.

## R62 — RETIRED ⚰️

~~**The UX/quality contract is human-collaboration-first: one readable flow page per journey, not machine tables.**~~ *Reversed by **R66** (2026-07-22): `docs/flows/` stays the contract home with the same section semantics + R61 tests grammar, but the shape is dense machine spec (`when·why·steps·quality·tests·changes`). The change-interface-is-the-conversation idea survives; only the human-readability premise died.* What R62 did while live (2026-07-20): retired `UX.md` mega-tables + `NFR.md` ceremony → per-flow pages + `_patterns.md` (define-once) + `_quality-bar.md` (N1–N7 floor); `INVARIANTS.md` untouched. | 2026-07-20 owner directive (human-in-loop discussion surface); honest trade recorded then: weaker regen input than dense tables — the exact axis R66 later flipped. Amended 2026-07-22 (Why line): each flow carries a one-line rationale + R-IDs; a standalone `FEATURES.md` handbook was offered and REJECTED (fourth home, drift-prone, against R2/R24) — the handbook is `docs/flows/` itself. Amends-history: R54 R58 R55 R2; composes R61.

## R69·b — DECISION 🔓

**The STEERING cap moved 12288 → 6144 → 6656, and this is where that is recorded.** Cut to 6144 when the injected core went 11097B → 5919B; raised to 6656 when a devil's-advocate pass proved that 5919B core had silently DROPPED EIGHT BEHAVIOURAL RULES, so the cap had been calibrated against a defective measurement and defending it meant compressing real instructions to protect a bad number. Still a 44% cut from the original. **Two claims in R69 are hereby WITHDRAWN as false:** (i) "the two-tier split keeps every rule + its trigger in the core" — five instructions now live only below the marker (decision-tier provenance · the decompose-park MCP hint · blessing-in-the-subject · YAGNI-concretely · rework-ratio), deliberately, because they apply at a moment you can read for rather than on every reply; and (ii) that the 3.34.0 cut lost no rules — it lost eight, all since restored, and one ("just talk it through" as an always-open option) was dropped from the file entirely and is restored here. **Also unmeasured and now stated plainly:** the ~2.7KB autopilot block injected when the mode is armed is NOT covered by the cap, so real per-session injection is ~6.4KB unarmed and ~9.2KB armed. | 2026-08-02. A cap is a budget only while it tracks what the content genuinely needs; the moment it starts deciding what the content is allowed to SAY, it has become the thing it was meant to prevent. Recorded rather than adjusted silently (CLAUDE.md: reverse it *there*, as a visible trade-off).

## R73 — DECISION 🔓

**Command-review sweep (3-panel + DA) — one enforced outcome, the rest prose.** A ground-up review of all 10 command prompts by three independent lenses (cost · simplicity/coherence · UX) + a devil's-advocate on the ship diff. **Enforced (durable):** `check.sh` now byte-caps each command's `description:` frontmatter at **140B** — it's always-loaded per-session injection (the whole command list rides every session), the exact silently-growing class **R69** capped for STEERING/CLAUDE.md/LESSONS but had missed here; ceiling with working room over the 116B max (`handoff.md`), prevention > detection (N7). **Prose fixes (R28, freely amendable, not individually locked):** autopilot.md now documents the `decisive` arg (functional gap — script/MAP/flows referenced it, the command didn't); the handoff→resume **receiving end** is lit up (resume clears autopilot early, then checks for an un-checked-out waiting handoff branch — `wip/*` from a default-branch handoff *or* the relayed feature-branch name — and points at `/companion:handoff`, killing the pre-R72 manual-export prose; prose-only per R28, `resume.sh` still just clears+imports); docs.md preamble deduped (routing table stated once, honesty machinery kept verbatim — owner-picked moderate cut); advise gained the standard step-0 + a docs-prerequisite pointer; redesign negotiates its interruption budget up front (D2 run-mode pick + exit ramp); shared step-0s defer the R38 pile-review (mechanical-unblock ≠ off-ritual); history-asides stripped from runtime prose. **Set stays at 10** — every merge/split/delete candidate checked, none ripe. | 2026-07-23, three-panel review + DA, owner walked all 14 deltas recommendation-first (provenance `stated`). The DA also caught a real ship defect pre-merge (`land --gate` single-token vs `preflight` varargs) — fixed in 3.16.0 before it landed. Amends **R69** (adds the description cap to the enforced injection budget); composes R28 (prose = judgment, most fixes un-lockable), R41/R59/R72 (the gaps closed), R3 (density).

## HUD-1 — RETIRED ⚰️ (the companion-hud experiment, and the provider seam it proved)

**The status line was extracted to a standalone repo with its own V, then folded back.** Salvaged
here on 2026-08-02 because the repo held the only copy — it had **no remote**, so deleting it would
have destroyed the reasoning permanently, and the code it carried had already diverged 108 lines
from the plugin's own status line.

**What the experiment was for, and what it returned.** It proved the needs → requirements → design
→ tests trace matrix end to end on a small artifact, which is the approach then applied to this
whole repo (`docs/needs.yaml`, `docs/requirements.yaml`, `dev/trace.sh`). That was its value and it
was paid in full; the *artifact* had no further job.

**Why it was folded back (owner-decided, 2026-08-02, from a 3-option menu).** A status line is the
product's front door, and shipping it separately means users install two things for the feature they
see most. The alternative — keep both and sync them — is what **R4** was retired for. The owner's
stated rule, broader than this decision: *don't duplicate if you don't need to; drift should not be
something we have to manage.*

**The decision worth keeping (its ADR-0001).** *The optional segments come from a provider process,
not a library.* The extracted renderer had called eight library functions and read the plugin's
private task store directly — coupling that broke it three times in one day. Rejected: linking the
library (preserves the coupling with extra steps); inlining the state reading (coupled *and*
duplicated, breaks whenever the queue changes storage); a config file describing where state lives
(reintroduces the coupling as data, and makes the renderer parse formats it cannot verify). Chosen:
a provider process with a text protocol — the renderer cannot know what a task is, where a queue
lives, or which plugin is installed, so none of those can break it. The provider is **untrusted**:
output length-capped, line-capped and character-stripped, and any failure yields absent segments
rather than a broken line. Cost: one extra fork per repaint, the same order as the `git` call
already on that path. Consequence accepted deliberately: the renderer can never show a *correct*
task count on its own — it shows a count it was handed, or nothing.

**Still applicable here.** The plugin's `statusline.sh` reads companion state directly, which is
fine *because it ships with that state*. If the line is ever extracted again, this is the seam —
and the untrusted-provider rules are the load-bearing part, not the fork.

## R100 — DECISION 🔒

**companion's enforced core (secret-guard, ask-guard, contract-guard, stop-autopilot,
session-start) is retired in favor of an MCP server + portable skills, trading guaranteed
block/control-flow for cross-client portability.** Owner asked whether companion could become
agnostic of Claude Code — built on MCP, with Claude-Code skills as the consuming layer — for
eventual use with Cursor. Two facts were surfaced and accepted before this decision: **(1)** MCP
itself ships no interception primitive today (the "Interceptors" work, SEP-1763, is a
working-group draft, not spec) — this rewrite does not gain enforcement on Cursor either, since
Cursor's own blocking (`beforeShellExecution`/`beforeMCPExecution`) is a Cursor-hook mechanism, not
an MCP one, and building a Cursor-hook adapter is explicitly out of scope for this pass (owner
picked full MCP+skills over the per-host-adapter option, knowing it lands advisory-only on both
platforms). **(2)** Cursor's `stop` hook is observational-only (no block/deny) — even a
per-host-adapter design could not have restored autopilot's forced-continuation guarantee on
Cursor; that guarantee has no home outside Claude Code's own Stop hook, full stop. **Supersedes**
**R24**'s "tiny enforced core" (the core is no longer enforced code — it becomes an MCP server +
STEERING prose, consumed via skills); **retires R26**'s "autopilot stays enforced" ("a control-flow
guarantee against the model's own helpfulness bias... the rule exists to end the re-litigation" —
re-litigated and reversed here, explicitly, by owner decision, not case-by-case drift); **amends**
**R28/R51**'s block/control-flow/session-boundary-I/O-only line (the dividing rule itself is
retired, not just its examples — advisory-everywhere is now the deliberate default, the opposite of
R51's "no advisory hooks"); **reopens R8/R9/R10** (queue *ownership* is unchanged — `tq`'s data
model and CLI are reused verbatim as the MCP server's backend — only enforcement moves; the
native-vs-own-queue split these decisions record is untouched); **reopens R67** (companion now IS
machinery for domain-agnostic portability, the thing R67 previously declined to add — R67's
target, natively-configured *domain* MCPs, is a different concern and is not itself reversed).
| 2026-08-08, owner-decided after being shown the enforcement-loss cost twice
(`AskUserQuestion`, both times: cheap-portable-wins-only and per-host-adapters were offered first
and marked recommended; owner picked full-MCP both times, informed). Rolled out in bounded,
check-gated passes (companion's own `/companion:redesign` discipline) — each hook's retirement and
its requirements.yaml reversal happen together, in the same pass, never as a ledger-only or
code-only change. See the redesign plan for the full pass breakdown.

## R104 — DECISION 🔓

**`prompt-continue.sh` (the last surviving Claude Code hook, `UserPromptSubmit`) stays
Claude-Code-only — no Cursor-side equivalent is built.** Investigated as part of R100's Pass 5
portability audit: Cursor 1.7+ has a `beforeSubmitPrompt` hook, but its output contract is
block-only (`{continue, user_message}`) — it can allow or deny the prompt and show the *user* a
message, but it **cannot inject additional context the model reads**, unlike Claude Code's
`UserPromptSubmit` (`hookSpecificOutput.additionalContext`). `prompt-continue.sh`'s whole mechanism
— silently steering the agent to review the parked pile before continuing — has no faithful Cursor
counterpart; the closest equivalent would *hard-block the human's own prompt* instead, a materially
different UX, built and shipped unverified (no Cursor install available to test against). Owner
chose to accept the asymmetry rather than ship unverifiable Cursor-specific code: on Cursor, a bare
"continue" with a full parked pile just continues — the MCP `review`-equivalent flow
(`autopilot_toggle` pause/resume + `tq_list`) is still fully reachable there, just not
auto-triggered. **🔓, not 🔒** — revisit if the owner starts actually running the plugin against
Cursor and can report what its hook behavior looks like in practice (the third option offered and
declined this round).
| 2026-08-08, owner-decided (`AskUserQuestion`, three options offered — leave the asymmetry
(recommended), build an unverified Cursor hook, or defer until Cursor is in actual use — owner
picked the recommended option).

## R105 — DECISION 🔒

**Two of R100's five retired hooks are REINSTATED — `session-start.sh` (SessionStart) and
`ask-guard.sh` (PreToolUse[AskUserQuestion]) — Claude-Code-only, no Cursor equivalent attempted;
`secret-guard.sh`/`contract-guard.sh`/`stop-autopilot.sh` stay retired.** Raised by the owner
directly, independent of the Pass 5 portability audit: two principles they want at the CORE of
this product — "avoid rework, including asking questions rather than working against
requirements or repeating failed attempts" and "account for the limited context newer models can
absorb, which seems to ignore or subvert clear plugin instructions" — argue for MORE enforced,
blocking mechanism at the highest-leverage points, not less. R100 had traded nearly all of it
away for Cursor portability. The two are not fully reconcilable as stated, and this decision is
the resolution: a NARROW reopening of R100, not a reversal of it.

**Why these two, not all five.** Ranked by how directly each addresses the two principles above:
session-start.sh's automatic injection means an instruction is never merely *skipped* by the
model — it is *present*, closing the harder failure mode ("ignores context" vs. "context was
never there"); ask-guard.sh's deny-and-auto-park directly implements "don't let the model barrel
past an unanswered decision." `secret-guard.sh`/`contract-guard.sh` (pre-write blocking) were
offered as a third option and explicitly declined — this session's own discipline held without
them, and a DA-pass-before-ship catches drift after the fact, so the marginal safety their
reinstatement would buy did not clear the bar the other two did. `stop-autopilot.sh`'s forced
continuation was not asked back at all and remains R100's single biggest fidelity loss — nothing
in this decision touches it.

**The trade, named plainly, mirrors R104's own reasoning:** portability to Cursor is reduced for
exactly these two guarantees. Neither hook has a faithful Cursor equivalent — SessionStart is a
Claude-Code-specific lifecycle event with no confirmed Cursor analogue, and PreToolUse-blocking
has no MCP-portable form (the same finding R104 already made for `prompt-continue.sh`). This is
evidence the R100 architecture is not a single lever — some guarantees are worth being
host-specific for, and the owner is willing to name which ones on a case-by-case basis rather
than treating "fully portable" as a rule that can't be reopened.

**Implementation, for the record (not the decision itself):** `session-start.sh` and `resume.sh`
now share content generation via `lib/resume-report.sh` (split into `companion_resume_steering`
and `companion_resume_report`) rather than duplicating it — a compaction re-anchor gets the SAME
cheap tail (carried tasks, version-lag, LESSONS, R93 out-of-band changes, rework) a fresh start
does, differing only in whether the full STEERING core or a short message leads, matching the
pre-R100 hook's own shape. `session-start.sh` deliberately does NOT clear autopilot on fire
(unlike `resume.sh`) — an automatic hook silently disarming a persisted "keep draining" intent
mid-compaction would defeat the exact workflow autopilot exists for. `ask-guard.sh` is restored
close to verbatim from git history (proven correct twice in the same session it was reinstated,
having intercepted the very `AskUserQuestion` calls that led to this decision).

Reverses: R100/Pass 2's retirement of SessionStart (re-reverses R39/R69/R80/R93 back toward their
pre-R100 shape) and the ask-blocking half of R100/Pass 4's retirement of ask-guard.sh (re-reverses
R33/R59/R84; R26 splits — "don't ask" re-enforced, "keep going" stays advisory). Does NOT reverse:
R100/Pass 3 (secret-guard.sh/contract-guard.sh stay retired) or the forced-continuation half of
R100/Pass 4 (stop-autopilot.sh stays retired — R34/R77/R81/R82/R88 untouched).
| 2026-08-08, owner-decided (`AskUserQuestion`, multiSelect over four independent candidates —
session-start.sh reinstatement, ask-guard.sh reinstatement, secret/contract-guard reinstatement,
or none — owner picked the two recommended, declined the third).

## R106 — DECISION 🔓

**The pre-code design step is STEERING, not a command.** A structural change (new seam or
dependency, data-model or interface change) states its **interface delta + call-stack before code**,
then slices into tasks carrying that sketch as `--context`. The reflex rides the SessionStart
injection (**R105**), so it fires unasked.

**Origin:** the owner read humanlayer's *Why Software Factories Fail* and asked how this plugin
avoids that exact scenario. The audit found companion covered most of the chain — lights-off
(**R5/R49** menus, ask-guard parking), no-planning (`--done`/`--context`, decompose-park **R65**),
spec-rewriting-to-pass (**R86**), erosion detection (`advise`, the rework ledger), rewrite-from-
scratch (**R55** bounded passes) — with **one real hole**: the article's phases 2–3. STEERING
already named "architecturally significant" as a **pause** signal; on that signal companion asked a
question and produced **no design**. The trigger existed; the artifact did not.

**Four placements were offered; the owner rejected all four**, with the reason that decides this
entry: *"I want this to be more of a steering system than a system where I have to specifically run
commands, since I will forget to run these commands."* Rejected: **(a)** a `/companion:design`
command — recommended in the menu, and the recommendation was **wrong**: the owner's recorded
preference has been automatic-and-artifact-free since the redesign, and an opt-in step is precisely
what this failure mode eats. Recorded as `owner-supplied` rework. **(b)** a `docs/design/<change>.md`
doc class — a third Claude-facing doc class, and still opt-in. **(c)** a `tq --design` field — a
queue field is a weak home for a call-stack, and design spans tasks while the field is per-task.
**(d)** prose with the motivation stripped, to fit the byte cap — this is advisory text whose only
power is persuading the model to spend effort before it must; stripping the *why* strips the
mechanism.

**Cost, paid visibly.** The injected core had **8B** of headroom. The reflex plus the R107 nudge
needed 137B more than the cap allowed after **217B of duplication was cut to fund it** — the
advisory/`bin` split (already in `flows/_quality-bar.md` N4), the wireframe clause and Posture's
autonomy sentence (both already in `Run in auto`), the ripples-wide nudge (the new reflex owns
splitting), and a **stale header claiming STEERING is "never automatically" injected**, which R105
made false. Owner raised the cap **8384 → 8576** (~34 tokens/session), matching the 8192→8384 raise
of 2026-08-07 in shape and size. **This is the fourth raise and is recorded as a smell:** the cap
only works as a forcing function while it occasionally binds, and being *at* it is what surfaced
the 217B of duplication. A fifth should trigger a core rebuild (**R55**), not a fifth raise. The cap
was also hardcoded at three sites; it is now one variable, because a raise that missed a message
would print a number the gate no longer enforces — output that lies while staying green.

**Named limit.** This is prose the model can skip. `R106`'s test pins **delivery** (the reflex
reaches a session through the real hook, not merely exists in a file) — it cannot pin compliance,
and no shell check can. That is the same ceiling **R28** names, and the honest answer to the
article's central claim: for now the judge is still the owner.

**The level-0 gap this exposed — CLOSED the same day.** `needs.yaml` had **no maintainability
need**, so R106 shipped tracing to **UN-3** (review before commitment) because that was the closest
honest fit, not the right one. Authoring a need is never the agent's (`needs.yaml` header, R86), so
it was parked (`#46`) rather than written. **Owner authored `UN-8` on review, 2026-08-09** — *"I
want the codebase to still be workable in six months — not just passing its tests today"* — chosen
over widening UN-5 and over keeping the UN-3 trace. R106 and R107 now satisfy `[UN-8, …]`. UN-8 is
the **first need with no PRIN row behind it**, which is precisely why it was missing: nothing in the
old ledger ever asked for maintainability, so recovering needs *from* that ledger could never have
produced it. The park is the mechanism that made an absent need visible — worth noting, because a
trace gate can only check that every requirement names *a* need, never that it names the *right*
one. My park text also mis-stated the ceiling as seven; `needs.yaml` says ten, which materially
weakened the cost I had put on the decision, and the correction was given before the owner chose.

Composes **R105** (the injection that makes it proactive), **R65** (decompose-park, the interview
that precedes a sketch it cannot yet draw), **R99** (`--context`, what the sketch travels in),
**R58** (contract moves first), **R69** (the byte budget it spent).
| 2026-08-09, owner-decided: placement rejected via `AskUserQuestion` free-text, then the funding
choice picked from a 3-option menu (raise / strip the motivation / cut named prose elsewhere).

## R107 — DECISION 🔓

**Autopilot's quality checkpoint is a nudge, not a hook.** A run of tasks drained under autopilot
offers `/companion:advise` on what it touched — surfaced once, parked as a `❓` while armed.

Autopilot is the article's lights-off mode. It parks **decisions**, but structural erosion never
presents as a decision — it presents as a diff that passes, which is the article's whole thesis
(*"there is no penalty for eroding codebase maintainability"*). **Rejected: a Stop hook** that
forced a review pass every N drained tasks — the only option that could not be skipped, and the
only one that would have re-opened **R100/Pass 4**'s retirement of `stop-autopilot.sh`, offered to
the owner on 2026-08-08 (**R105**) and declined then. **Also rejected: doing nothing**, on the
argument that an unenforceable checkpoint is theatre — the owner took the nudge over the silence.

**Named limit, stated at the point of choosing:** a nudge is the class of thing the model can skip.
This raises the odds of a quality read mid-drain; it does not guarantee one.
| 2026-08-09, owner-picked from a 3-option menu (nudge / nothing / Stop hook).

## R108 — DECISION 🔓

**An autopilot pause marker is bound to the session that wrote it.** Stale, foreign or unstamped
markers are discarded and never arm autopilot.

**Found by running the product on itself.** `/companion:review` step 0 calls `autopilot pause`,
step 5 calls `resume`. On 2026-08-09 that sequence armed autopilot on the owner's machine when they
had never turned it on: a review on **2026-08-08 16:55** paused and never resumed, leaving the
marker behind; the next day's review found autopilot already OFF — so its own `pause` was a correct
no-op that wrote nothing — and `resume` honoured the day-old marker. **R83's pause/resume pair was
correct in isolation and wrong across sessions**, because the marker carried no identity. Same class
as the mode-state oscillation already flagged in queue item #19: transient state outliving its
session.

**Rejected: expire the marker on a timestamp** (`(b)` in the queued fix list) — it needs an
arbitrary constant, and a review's real duration is unbounded; a bound loose enough to be safe is
loose enough to miss the overnight case that actually fired. **Rejected: tie it to the paused
process** (`(c)`) — wrong unit, since `pause` and `resume` are separate invocations by design.

**Fails safe, deliberately.** An unverifiable marker leaves autopilot **OFF**. Failing to
auto-resume is visible and one `autopilot on` away; wrongly arming starts unattended work nobody is
watching. That asymmetry also settles the upgrade case: a pre-fix version still in the plugin cache
leaves an *unstamped* marker, which is refused rather than trusted.

**Process note, recorded against myself:** the requirement entry was written while autopilot was
armed, which **R86** makes the owner's call, not mine. It was kept only because the change is atomic
— fix, test and entry land together, and dropping the entry alone reddens `dev/trace.sh` on the
orphan-test direction — and the ratification is parked (`#49`) rather than assumed.
| 2026-08-09, defect reproduced live; fix chosen from three candidates recorded at queue time.

## R109 — DECISION 🔓

**Evidence at the completion boundary.** `tq done --seen "<what was exercised, in which running
thing>"`, refused by `seen-gate.sh` when it reports the agent's own layer, and rendered back by
`tq list`.

**Owner-reported, 2026-08-10, from four misses with one shape:** completion declared at the
boundary of what a shell can observe, when the owner's experience of the work lived one layer
further out. A media fix written, tested, committed and reported done — never **deployed**. A route
move proved by a typecheck that **cannot see string-typed router paths**. An approval gate whose
refuse path was proved and whose **accept path was declared untestable while `pty.openpty()` was
available the whole time**. A bundle server three days stale while code and API were inspected
instead. *Every check run was real. None was the check that mattered.*

The four are not equal, and the ranking drove the design. Two are **observation-layer** errors —
prose can plausibly move them. One is a **state** error (built ≠ deployed) that only a mechanism
catches. The fourth is the deep one: a **self-issued verdict of impossibility that never got tested
against the owner**. It is structurally a decision — it trades verification for delivery — but it
never enters the parked pile because it does not look like a choice, so it walks straight past
UN-2's "decisions reach the owner intact". That is the miss the steering half targets.

**Rejected: `B`, a `.companion/surfaces` manifest + freshness probe at ship** — the only option with
a real mechanism, and it was the runner-up. Two costs sank it: it fires only at the **ship**
boundary, and three of the four misses were declared done long before ship (it narrows the window,
it does not close it); and an unmaintained manifest **certifies staleness**, which is UN-5's own
named failure shape — a green tick that cannot fail is worse than no tick. **Rejected: `D`, do
nothing** on the R28 ceiling. The owner took `A+C` over both.

**Funding, and a recorded pre-commitment honoured.** `A`'s steering half is an in-place rewrite of
the existing `Verify observably` bullet — 376B → 531B — because that bullet **already covered this
territory and lost**, so replacing it beats stacking a fourth line beside it. It still needs 154B
the core does not have (8575 against a 8576 cap). `check.sh:132` records *"FOURTH raise… If a fifth
is proposed, rebuild the core instead (R55)"*, so **the cap was not raised**: the shortfall is
parked with its four options, and `A` is not shipped until the owner rules. Scanned for the
subtraction that funded the fourth raise and there is no honest 154B left — the core's
`wireframe` / `decompose-park` / `playtest` mentions are two-tier **pointers**, and cutting a
pointer breaks the reference.

**Named limit, stated where it is enforced.** `--seen` is **fabricable by design** and `A` is prose
the model can skip — and **two of the owner's four misses already had prose covering them**
(`Verify observably — exercise, don't assert`, `Human-observable surface → offer a playtest`) and
both lost. The whole bet is that naming the specific shapes beats stating the principle. That bet
is unproven, and it is the part of this decision most likely to be wrong.

Composes **R78** (the `--da` guard this mirrors, including its recorded non-ASCII bug), **R58·a**
(the retired capture hook — why the reader is pinned by its own assertion), **R28** (the ceiling),
**R9** (plain-English shape check, never an ecosystem table).
| 2026-08-10, owner-picked `A+C` from a 4-option review menu, then "do all of your recommendations".

### R109·b — a backstop that manufactured the thing it backs up

Shipping R109 surfaced a live defect in `ask-guard.sh`, found the only way it could be: **by the
product parking a real decision of its own.** The auto-park cut every option description to 80
chars and the whole payload to 900 bytes, **both silently**. On the 4-option park that funded this
very entry, every cost clause — the byte-budget raise, the per-project setup, the staleness risk —
landed mid-word, and what reached the queue read like a complete thought. The payload had to be
re-attached by hand with `tq note`.

STEERING's autopilot block says a thin park "makes the review a rubber-stamp". The **backstop was
manufacturing exactly that**, on the path taken when the model forgets to park for itself — so the
failure lands precisely when the discipline has already lapsed. Same class as **R108**: correct in
isolation, wrong at the seam.

Fixed by removing the per-description cut and raising the payload ceiling to 6000, but the real
change is that **a cut now says so** (`…[TRUNCATED — …]`). A truncation a reader cannot see is
worse than a truncation, because it reads as the end of the sentence. `tq list` is non-truncating
by design; the queue could always have held the whole thing.
| 2026-08-10, defect measured live while parking R109's own funding question.

### R109·c — the parity gap I shipped, then caught

`--seen` first landed on the CLI only. `tq_done`'s MCP wrapper still took `{id}`, so **every
MCP client — Cursor, or Claude Code with the server registered — could close a task with evidence
the CLI would have refused**, while `docs/MAP.md` claimed the server is "byte-identical to the CLI".
The mechanism was invisible on exactly the surface R100 built the server for.

Caught by reading the wrapper rather than by any gate: no test asserted parity for a parameter that
did not exist yet, which is the blind spot a **new** optional argument always has. The fix passes
`seen` straight through — the guard is never re-implemented in JS, so both surfaces refuse the same
strings — and the new parity test reddens if the parameter is dropped again.
| 2026-08-10, found while checking MAP.md's parity claim against the code.

## R110 — DECISION 🔓

**The gate could not fail on the file that matters most.** `check.sh` builds its lint set as
`scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)`. **`bin/tq` has no `.sh` extension** and
is the only extensionless file in `bin/`, so THE task queue — R8/R10, the file every command and
the MCP server route through — was outside **ShellCheck, portability-lint and the 300-line size
guard simultaneously**. It had grown 355 → 382 lines with nothing to say so.

Found by asking why the size gate stayed green while `tq` was visibly over the cap. Nobody decided
this; a glob did. That is the worst version of a hole, because it is indistinguishable from
coverage — which is exactly what **UN-5** says is worse than no check at all.

**Rejected: widening the glob to `bin/*`.** It closes today's hole and opens an unknowable one — the
set a gate iterates must stay something a reader can enumerate, and `bin/*` would silently absorb
any future non-script. Named the file instead.

**Rejected: decomposing `tq` in the same change.** Every command and the MCP server depend on it;
doing high-blast surgery inside the change that *discovered* the hole is how a fix becomes an
incident. Queued (tq #63) and exempted **out loud** instead: the exemption prints on every run,
names the task that closes it, and the gate goes **RED** once `tq` drops under 300 — so the skip
cannot outlive the debt it documents. An exemption nobody can see is a lie; one that survives its
own fix silently re-opens the hole.

**Provenance worth recording.** This surfaced while draining a task queued *because the owner asked
autopilot to keep going instead of stopping at the parked pile* — the tail of the queue, not the
head, which is the part that never gets reached when a run stops early.
| 2026-08-11, hole measured live; both guards mutation-verified.

## R111 — DECISION 🔓 (reverses R105's and R107's declines)

**Autopilot's "keep going" is a hook again.** While autopilot is armed and a **startable** task
remains, `stop-autopilot.sh` refuses the stop and hands over the next task.

**Why the third time was different: behaviour, not argument.** A Stop hook was offered on
2026-08-08 (**R105**) and declined, and again on 2026-08-09 (**R107**), where it is recorded as
*"the only option that could not be skipped"* and rejected anyway. What changed is evidence. In the
session that produced this, STEERING already said *"keep draining; don't stop to ask"* — and the
model stopped with a startable task in the queue and reported instead. That is the same shape as
the two misses in the owner's 2026-08-10 defect report that **already had prose covering them and
lost**. A nudge the model can skip is not a mode (**R36**).

The confirming detail arrived the same day: **R110** — a gate that could not fail on the most-called
file in the product — was found only while draining *past* the parked pile, into the tail of the
queue. That is exactly the region a run that stops early never reaches, and it is the concrete
argument the two earlier declines did not have.

**PARTIAL restore — 135 of the retired 183 lines**, and the omissions are the decision, not an
accident of the splice. Both dropped concerns acquired another owner while the file was gone:
**ship-mode auto-commit (R34)** now belongs to `bin/ship-checkpoint.sh`, invoked deliberately; the
**burn-down hand-off (R82)** is now something STEERING tells the model to call itself. Restoring
either would put two owners on one concern and silently re-automate a path the owner made manual on
purpose. What came back is the continuation guarantee plus **every terminator that bounds it** — the
no-progress stall cap, the R81 wall-clock and total-turn run bounds, the R77 sweep terminator, and
the `CLAUDE_COMPANION_AUTOPILOT_CONTINUE=0` kill switch. **Restoring the continuation without its
bounds would have been the one genuinely dangerous version of this change**, and each bound is
pinned by a test that reddens when it is disabled.

**Cost, stated where it was chosen.** This is Claude-Code-only: MCP clients (Cursor) get nothing
from it, and R100's portability thesis pays for it. The hook is also now in the **measured** R81
budget (`dev/hook-budget.sh`, 0.98x scaling at 8x store size) and in the fuzz set — restoring code
without restoring its measurement would have re-shipped the guarantee and dropped the guard on it.

**Named limit.** The hook was **verified inert in the running session**: the plugin cache serves
3.82.0, whose `hooks.json` declares no `Stop` entry, while the source is 3.83.0. It changes nothing
until the owner refreshes the plugin (tq #62). Saying so is the point — this repo's own hard
constraint is that the hooks which fire are not the ones you edit.
| 2026-08-12, owner-picked "partial restore" from a 4-option menu after a paused-autopilot review.

## R112 — DECISION 🔓

**The review opens with a multi-select accept sweep.** Tick the recommendations you already agree
with — arrow keys, enter — and only the rest get walked one at a time.

**What was actually missing.** The owner asked for arrow-key selectable recommendations, and that
already existed: `/companion:review` has always driven `AskUserQuestion`. Diagnosing the request as
"build the picker" would have rebuilt a working feature and fixed nothing. The real defect was that
**agreeing cost the same interaction as overruling** — every park was its own single-select menu, so
a twelve-item pile was three rounds of arrowing through options to say "yes, your pick". The tool
takes 2–4 options per question and 4 questions per call, so grouping into questions of four accepts
**16 parks per interaction** against 4.

**The safety property is the requirement.** A `multiSelect` payload returns only the PRESENCE of a
yes — there is no "no" in it. A review that read an unticked box as a rejection would **silently
invent decisions across the entire pile**, which is strictly worse than the drip-feed it replaces
and is precisely what **UN-2** forbids: *"I do not want anything else pretending to be [a
decision]"*. So unticked means **"ask me properly"**, and the item falls through to its own full
menu with its options intact.

**Excluded, each for its own reason:** `⏳` blocked items (an owner *action* is not a recommendation
to accept), `decompose:` parks (**R65** — they carry questions, not options, so there is nothing to
accept yet), and any park whose `rec:` is a thin guess. **Irreversible parks stay eligible** — the
owner is consciously ticking, unlike **R77** sweep mode where the agent applies `rev:` picks
unattended — but they are labelled `⚠ IRREVERSIBLE` so a batch tick cannot hide a one-way door.

**Named limit.** Prose: the ceiling is **R28**. A **R56·P3** structural guard pins that the sweep
and its absence-is-not-rejection rule were not deleted; nothing can pin that they are obeyed.

**Process note, against myself.** **R58** says a change to what the owner *does* moves the flow page
FIRST. I wrote the command and the guard before touching `docs/flows/`, and only caught it while
looking for the flow page to update — at which point I also found `hands-off-drain.md` still
asserting `stop-autopilot.sh` was retired, **R111 drift I had left behind a turn earlier**.
`contract-drift.sh` runs at the ship boundary by design (R58), so nothing was going to catch either
until much later.
| 2026-08-12, owner-asked; the picker already existed, the batch did not.

### R87·b — the dependency that never parsed

**Owner-reported 2026-08-12: "autopilot doesn't seem to be running through the backlog."** It had
two independent causes, and only one was the one being discussed.

**Cause 1, mechanism:** the restored Stop hook (**R111**) is inert — the plugin cache serves 3.82.0,
which declares no `Stop` entry. Nothing can force continuation until the owner refreshes (tq #62).

**Cause 2, and the one that mattered more:** `tq stopfields` reported **STARTABLE=4** while every
one of those tasks was in fact waiting on an unanswered park. **The dependencies existed only in
prose written to the owner.** Had the hook been live, it would have driven straight into a task
whose entire premise was a decision the owner had not made yet — *worse* than not running, because
it would have looked like progress.

**Root cause: `after #<id>` in the subject is the ONLY dependency syntax `stopfields()` reads, and
it was documented nowhere** — not in `tq --help`, not in `STEERING.md`. Writing `(after 1/2)`, which
is what had been written on the real task, parses as nothing and leaves the task looking perfectly
startable. **A dependency that silently fails to parse is worse than one that errors**: the queue
does not go quiet, it reports confident nonsense.

**Compounding it, `blocks`/`blockedBy` are vestigial** — initialised `[]` at `add`, never written by
any verb, never read by anything (grepped: zero readers, zero writers). They look exactly like the
dependency mechanism and are not, which cost two tool calls of misdiagnosis before the real parser
was found. That is **R58·a's "data nobody reads"** in schema form. Documented at the only line that
touches them rather than removed, so old task files stay shape-stable.

**Fixed:** the syntax is documented in `tq --help`; the live backlog was re-encoded with real
`after #<id>` dependencies (STARTABLE 4 → 0, which is the honest number); a test pins both the
parser's strictness and the documentation, each mutation-verified. The behaviour was never
wrong — only invisible, which is the same shape as **R110**.
| 2026-08-12, owner-reported; diagnosed by reading stopfields rather than trusting the field names.

### R110·b — the debt was paid, and the trap is what collected it

`bin/tq` is **285 lines**. The named size exemption is **deleted**, and it was not deleted because
anyone remembered — the staleness check written alongside it went **RED** the moment `tq` dropped
under 300 (*"FAIL stale exemption: plugins/companion/bin/tq is now 285 lines — delete the size_skip
block"*) and refused a green gate until the block was gone. A debt marker that cannot expire on its
own is how the 382-line drift happened in the first place.

**The seam is cohesion, not line count.** `usage()` and `report()` moved to `bin/tq-output.sh`:
everything there **renders**, nothing there **decides**. Queue state — id allocation, the
atomic-rename crash-safety, `stopfields()`'s startable selection — stayed in `tq`, because splitting
state across files is how two owners of one concern start. This is why the earlier proposal to
extract `usage()` alone was **refused**: 21 lines of help text chasing a number, landing at ~333 and
still over, is the seam-smell trap STEERING names.

**The parked objection was measured and was wrong.** Extracting `report()` was held back on the
grounds that it is the hot path and a `source` would cost every `tq` invocation. Measured before
acting, per R110's own lesson: **0.634s vs 0.635s over 100 invocations** — inside the noise floor,
against a ~21ms `tq report`. The cost I had flagged did not exist, and the number settled it rather
than my intuition. Worth recording that the caution was unfounded, not just that the extraction
happened.

**The guard was rewritten, not retired.** It watched an exemption that no longer exists; it now pins
that **no size exemption may reappear**. A named, printed, self-expiring exemption was defensible
for a day. A silent one is how `tq` reached 382 unseen.
| 2026-08-12, trap fired on its own terms; the hot-path objection measured and disproved.

## R113 — DECISION 🔓 (crash resume: detect the state a missing breadcrumb leaves)

**The ask.** Owner, 2026-08-15: *"sometimes the terminal crashes, I want to make sure I can continue
where I left off, does the plugin allow for that or should we make a change so I don't have to
restart the work or have work partially completed?"*

**Most of it already worked, and saying so first mattered.** The queue is JSON on disk, written
temp-file-then-rename (R44), carrying `done_when`, `--context` and cumulative `notes[]`; the mode
flags persist; `session-start.sh` hands the whole thing back unasked (R105). Outside the plugin,
`claude --continue` restores the transcript. The honest answer to "does it allow for that" was
**largely yes** — and the four options put to the owner therefore included *do nothing* as a real
option, not a strawman.

**What the store actually said.** 0 of 89 tasks were `in_progress`; the 27 with notes were almost
all `completed`, i.e. notes written as evidence at the END rather than as a trail during. The three
open tasks had none. STEERING has asked for `doing`/`note` as-you-go since R47. **The advisory rule
is being skipped, and the evidence for that is my own queue** — this is a defect in how I work, not
a missing feature, and the fix had to account for that rather than re-ask for the discipline.

**Options put, owner picked "detect the bad state on start" (option C):**

| | |
|---|---|
| **A** discipline only — no code | free, but re-promises exactly the advisory thing the store proves gets skipped |
| **B** Stop hook stamps the dirty list | only fires when a task IS in_progress, so it inherits the gap it fixes; the R58·a "bank it just in case" shape |
| **C** ✅ detect on start | notices the state instead of hoping to prevent it; self-correcting |
| **D** nothing, use `claude --continue` | fails on a new terminal, a reboot, a clone, a container |

**Why detection is not a rerun of the two reversed attempts.** R99 settled that nothing here can
*force* a good breadcrumb. R58·a's capture hook was retired for banking data with **zero readers**;
R32·d4's PreCompact tried to protect state on the way *into* a wipe. This does neither: it **reads
durable state that already exists** and reports a contradiction between the tree and the queue. That
is an *inject*, the one class R28 permits, and its reader is the next session by construction.

**Two changes, both about "where did the work stop":**

1. `in_progress` renders **▸**, not ◻. These were byte-identical, so the task a crashed session was
   *working on* returned indistinguishable from one merely queued. Free; reuses `tq report`'s glyph.
2. **UNRECONCILED WORK** — a dirty tree with no `in_progress` task prints a warning naming the files
   and what to do (claim / commit / revert).

**The false-positive defenses are the load-bearing part.** A warning that fires when there is
nothing to reconcile is worth the same as no warning at all, and it would fire *every session*: the
`.companion/` store is untracked in most projects. So the store is excluded from the dirty set (the
plugin's own state dir — not an ecosystem guess, R9 intact), and the warning stands down entirely
while a task is `in_progress`, because that breadcrumb is the reconciliation.

**The budget was fake and I fixed that, not just claimed it.** `companion_unreconciled` runs one
`git status --porcelain`, which walks the worktree — ~43ms on a 17k-file repo, a number
`statusline.sh` already measured and caches because it re-renders constantly. Not cached here: once
per session, and a stale answer on the path whose whole job is telling the truth about the tree is
worse than the milliseconds. The real find was that **`dev/hook-budget.sh` used a ONE-FILE fixture
repo** — it scaled the task store and never the worktree, so every `git status` any hook ran was
measured against nothing. Adding this call under that gate would have satisfied the letter of R81
while measuring air. The fixture now carries 400 files with a tenth dirty; `session-start.sh`
measures 98ms → 236ms on the 8x store against the 1500ms cap.

**What this does NOT do, stated plainly.** It cannot reconstruct *reasoning* — only that work exists
and nothing claims it. It cannot make me leave breadcrumbs; it can only make skipping them visible
next session. And `lib/companion.sh` came out of this at **exactly 300 lines**, the cap: the next
change there has to decompose it first, and that debt is mine, recorded rather than left to be
discovered.

| 2026-08-15, owner picked detection over discipline; the unmeasured hook budget was the real catch.

## R114 — DECISION 🔓 (burn-down climbs on ACCEPTANCE, and actually fires)

**The ask.** Owner, 2026-08-15: *"I want this thing to pay down tech debt when I am not using my
tokens automatically if I'm behind schedule in using 100% of my tokens, then move up to the next
level of complexity until features are being crafted automatically behind a feature flag."*

**Three separate defects sat between that and reality, and only one was the feature.**

**1. Nothing ever fired it.** R82's hand-off had been deliberately deleted from `stop-autopilot.sh`
on a duplicate-ownership argument: STEERING told the model to call `burn_down` when the queue ran
dry, so automating it would make that prose false. The argument is sound about ownership and wrong
about outcomes — **prose is not an owner, it is a request.** The owner reasonably believed the
feature was automatic while nothing fired it for weeks, and the same session measured what happens
to that class of instruction: **0 of 89 tasks carried the breadcrumbs STEERING has demanded since
R47.** Restored, with the STEERING sentence rewritten in the same change so nothing goes false, and
split per R28/R81: **the hook owns WHETHER to continue** (one `should-burn` call, measured at 23ms),
**the model owns WHAT to build** — `candidates.sh` git-greps the whole repo and must never run in a
hook. Its own behavioural test then caught a placement bug: an empty store bailed one branch
*earlier*, so a brand-new session — the most ordinary idle case there is — never reached it.

**2. Rank 1 was self-dealing, and this is the one that mattered.** Rank 1's justification is *"the
owner deferred THIS work and a recommendation is already written."* That sentence is false for a
park the MODEL wrote and nobody has read. Caught live: rank 1 at that moment was a park authored
minutes earlier **recommending that the model be granted more autonomy.** Restoring the trigger
first would have let an unattended run build the generator's own unreviewed advice — the same mirror
as feeding on its own documentation (fixed hours earlier), one level up and with real stakes. Rank 1
now requires a deferral note, which `/companion:review` writes when the owner walks the pile, and
that note stopped being optional. It **fails to the safe side**: a store with no such notes empties
rank 1 rather than guessing, and generation falls through to ranks the owner authored.

**3. The proposed trigger was the wrong instrument.** Utilization answers *whether there is spare
capacity* and never *what may be built*: it measures spending, and burn-down's own header already
warned against optimising for it. The binding constraint is the **owner's review throughput**, which
does not grow when the token budget does — a ladder climbing on a spending clock converts a token
surplus into a review backlog, which is what the existing 3-branch cap already encodes. So the
trigger stays the forecast and **the TIER is gated on demonstrated acceptance**: the share of
generated branches actually kept. Debt paydown (TODOs, untested flows) is always allowed — it is
verifiable against the suite that already exists, which is what makes it safe unattended. Features
(parked-with-rec, ROADMAP) need ≥2 judged outcomes at ≥50%; large rebuilds need ≥4 at ≥75%; invented
work is **never** automatic at any rate. It self-corrects downward too, which a clock cannot.

**Stated honestly:** the ledger is approximate — `created` and `abandoned` are recorded, MERGED is
*inferred* as created − abandoned − still-present, because a merged branch is routinely pruned and
would otherwise be invisible. A hand-deleted branch therefore reads as accepted, biasing
permissive, so the thresholds sit where a couple of stray deletions cannot promote a tier alone.

**The declined option, recorded because it was the literal request:** climb on the utilization clock
as asked. Rejected for the reason above, with the caveat surfaced to the owner that *I am the party
that would gain autonomy from saying yes* — so the caution, not the enthusiasm, is the part worth
weighting.

| 2026-08-15, owner picked acceptance-gating and the restored trigger; the self-dealing rank was the real find.

## R115 — DECISION 🔓 (the STEERING cap ratchets DOWN; audit pass 1)

**Found by audit**, owner-asked 2026-08-16. The injected STEERING core measured **8725B against an
8730B cap — five bytes of headroom**, so the next edit to the working agreement was guaranteed to
fail the gate.

**The cap had risen eight times:** 6144 → 6656 → 7040 → 7360 → 7808 → 8192 → 8384 → 8576 → 8730,
**+42%**. Each raise was justified in place and none was hidden; the problem is the shape, not any
one of them. `check.sh` had been carrying the counter-argument in its own comments the whole time —
*"A cap should track what the content genuinely needs; it stops being a budget the moment it"* — and
a note pre-committing that a **fifth** raise should rebuild the core instead. It was overridden
three times after that. Every byte is paid in every session in every repo the plugin is installed
in, against a stated first principle that token efficiency is THE concern.

**Decision: the cap may only ever DECREASE.** Set to **8500** against a measured 8444B. An addition
must now be funded by a deletion.

**THE HONEST ACCOUNTING**, because the owner picked "cut prose that now has a guard" and that is not
mostly what happened. Of 281B recovered:

- **71B was guard-justified.** The largest single item was a **false claim**: *"Enforced under
  autopilot, not advisory"* on the contract rule — untrue since `contract-guard.sh` was retired
  (R100/Pass 3), and sitting in the one document injected into every session. The rest was `--seen`,
  breadcrumb and file-size wording that `seen-gate.sh`, R113's detectors and `dev/size-lint.sh` now
  back mechanically.
- **210B was wordsmithing**, with no instruction dropped.

So the premise behind the chosen option was **only about a quarter right**. The core is mostly
genuine judgment — prose no guard replaces — which is exactly why the ratchet had to be *stopped*
rather than *reversed*. Recording that the option was picked on a reason that turned out weaker than
it looked matters more than the bytes.

**Teeth, and their limit.** A bats case asserts `core_cap <= 8500`, so raising it means editing the
gate AND its test: a two-place, visible act instead of a one-character nudge inside an unrelated
change. That is the property the eight raises lacked. It cannot stop a determined author, and it
should not — it only removes "nobody noticed" as an explanation.

**Immediately self-demonstrating:** writing this rationale INTO `check.sh` pushed that file to
306 lines and the size gate refused it. Trimming the comment to squeak under would have been the
exact behaviour this entry exists to name, so the reasoning moved here and `check.sh` kept a
five-line pointer. The rule caught its own author within a minute of existing.

| 2026-08-16, owner-decided from a 4-option menu; the cap's first-ever downward move.

## R116 — DECISION 🔓 (unattended weeks: the schedule is the trigger, hardening is the work)

**The ask.** Owner, 2026-08-20: *"How do we make it so this plugin automatically burns tokens when
I'm behind schedule… leave Claude CLI open for a week… come back to clean code, clean architecture,
and some features developed autonomously with a feature flag… a weighted ROI of what tasks make
sense to prioritize based on the core values of the project."*

**THE PREMISE FAILED FIRST, AND IT WAS NOT THE RANKING.** Every hook this plugin ships is
*reactive* — `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `Stop` all fire in response to a
session that is already running. **Nothing in the plugin can start one.** And an unattended run is
bounded to 6 hours by design (owner-ratified, R81). A week is 168 hours, so "leave it open" buys
**3.6% of the week, once**, and then nothing restarts it. The missing piece was never ROI ranking or
feature flags — both are policy, and the policy layer was already good. It was **substrate**.

**Owner picked Claude Code's own scheduled runs** over an external cron (my recommendation) or
staying session-bound. That choice has one hard consequence, verified rather than assumed: the task
queue, mode flags, rework ledger and acceptance ledger **all ride git**, but the rate-limit snapshot
is written by the status line and is **machine-local**. A cloud run has no status line, so
`burn-down` could only ever answer *"no rate-limit snapshot yet"* — it would HOLD forever in
precisely the substrate chosen to run it.

**The resolution is the insight, not a workaround: A SCHEDULE IS A TRIGGER.** The forecast exists to
answer *"is there idle capacity nobody has claimed?"* A cron entry answers that **in advance** —
scheduling a run IS the decision to spend. So `--scheduled` bypasses the FORECAST and nothing else.
Verified explicitly, because a bypass is exactly where safety quietly leaks: burn-down must still be
ARMED · real queued work still outranks generated work · the unreviewed-branch cap still binds (and
gets **no** time-based lift, since without a snapshot the elapsed window is unknowable) · downstream
`burndown-branch.sh` still refuses a dirty tree, still never merges, still never pushes.

**100% OF THE WEEKLY BUDGET IS UNREACHABLE, and burn-down already said so.** Live at the time of
asking: *"7d 8% used… tracking to 23%… needs 140%/window sustained — UNREACHABLE: over 3x your
sustained rate, and the 5h window caps throughput."* The 5-hour window is a throughput ceiling; you
cannot spend a week's budget while awake for part of it. The underspend was real (8% at 34%
elapsed); the **target** was the wrong instrument, not the observation.

**WHAT THE IDLE BUDGET BUILDS — the owner took the different direction I recommended.** Hardening
ranks above features, and feature-shaped work is separately capped at 2 outstanding.

The argument is an asymmetry, not a taste: hardening is verifiable *without* the owner ("did the
suite go red" needs no judgement) and reduces risk on code already depended on. A generated feature
costs **review attention, which does not grow when the token budget does**, and "is this worth
having" is answerable by nobody else. The evidence was close to hand — the sessions preceding this
produced ~10 defects in a day, four self-referential bugs found only by audit, and a verification
gate silently corrupting the working tree while reporting success. The binding constraint here is
verification, not ideas.

It also follows the project's own values, read in their own order: *self-describing · contain blast
radius · verify and stay aligned · subtract as you add.* **Shipping features is not among them.** So
`roadmap` was demoted below `todo`/`gap`/`rework` — demoted, not dropped. Rank 1 deliberately stays
first: an owner-deferred park carrying `rec:` is their own recorded choice, not the loop guessing.

**RANKING IS RECORDED JUDGMENT, NOT A FORMULA.** The owner chose this over a numeric
`(value × confidence) / cost` score, and the reason is worth keeping: every input to that formula
would have been invented. "Value 7, cost 3" launders a guess as arithmetic and is then trusted more
*because* it has numbers in it. Instead `burndown-branch.sh start` takes `--why`, and the manifest
gains a **Why this, now** section naming the core value served, the estimated cost, and what it was
chosen OVER. Absence is **loud**: a manifest with no rationale says so in bold and tells the reviewer
to be more sceptical. A priority nobody can read back is indistinguishable from one nobody made.

**What this still does NOT do, stated plainly.** It does not schedule anything by itself — the
routine is set up outside the plugin, and if it is never created, none of this runs. It cannot ask a
question mid-run, so a parked decision stalls that cycle until the owner returns. And one week of
evidence is not a track record: the acceptance ledger exists precisely so the tier ceiling moves on
measured merges rather than on anyone's optimism.

| 2026-08-20, owner picked scheduled runs + hardening-first + recorded judgment; the substrate gap was the real finding.

### R116·b — feature-class ships from a branch, whoever asked for it

**The asymmetry ran the wrong way.** Work burn-down generated *autonomously* got a branch, a flag
and never-merge. A feature the **owner asked for** landed straight on the default branch like a typo
fix. So the safety applied only to work they had *not* asked for — and not to the larger, riskier
changes they had.

**The class is one bit, taken from the contract:** a `docs/flows/*.md` page changed **alongside
implementation** means what the user can DO changed (R58). The alternative on the table was a
hand-set task level — feature / NFR / spec / chore. Declined, because this repo already carries
needs → requirements → tests, and a second classification is a second thing to keep in sync; every
drift defect the 2026-08-16 audit found had exactly that shape. A hand-set level is also
unverifiable, and its likeliest real use is to justify a **lower** bar ("just a chore").

**Generic by construction (R9):** "implementation" is any changed path outside `docs/` and
`.companion/`. Naming languages or extensions would be the violation this repo polices elsewhere.

**Behaviour.** On the default branch → refuse, *before staging or committing*, so a refusal never
leaves a commit to unpick. From a branch → commit and **push**, then stop: the merge is the owner's
act. `--merge-feature` overrides deliberately and auditably. Ordinary work — fixes, refactors, docs,
tests — is untouched, which is roughly nine changes in ten.

**Stated limit.** The flag ("defaults OFF") is *asked for* and not verified: this plugin cannot know
a project's flag idiom (R9), and pretending to check it would be ceremony. What is enforced is the
branch and the non-merge; the flag rides on the same honour system the burn-down manifest uses.

| 2026-08-20, owner-decided from a 3-option menu; the asymmetry was the finding.

### R116·c — restoring the two blocks, and what the portability line actually is

**Owner-decided 2026-08-22**, after being shown that blocking cannot be portable: MCP ships no
interception primitive (SEP-1763 is a working-group draft), and Cursor's `stop` hook is
observational-only. So `contract-guard` and `secret-guard` come back as **Claude-Code-only**, on top
of the portable core rather than instead of it.

**contract-guard is narrower than the one that was retired**, deliberately. It refuses REVERSALS —
removing a requirement entry or a `verified_by` reference, a whole-file `Write` to the contract,
authoring a need — and lets ADDITIONS through, because `dev/trace.sh` already fails a requirement
that names no test. It guards the one direction no other gate can see. It **fails open**: a missed
contract edit is recoverable and visible in the diff, while a false block costs the ability to edit
the contract at all, which is how a guard gets switched off for good.

**secret-guard is the one gate that fails CLOSED**, and the inversion is the point: a committed key
is irreversible, a false block costs one retry.

**THE MUTATION GATE CAUGHT BOTH OF ITS TESTS BEING INSUFFICIENT**, and that is the entry worth
keeping. The tests were written FIRST, against the two defects on record, and they passed — then
both declared mutations survived. Why:

- The "array carrying a key is blocked" case passed **for the wrong reason**. Without `tostring`,
  jq emits nothing, `rec` is empty, and the fail-closed branch denies anyway. The test could not
  tell "scanned and refused" from "refused because unreadable". What `tostring` actually buys is
  that a **clean** array is ALLOWED — and nothing tested that.
- Fail-closed itself had no test at all: every payload in the suite was readable.

A third finding was mine, not the tests': the first mutation targeted the wrong `tostring` — the
one on `file_path`, which is already a string, so it changed nothing.

**The general lesson, and it is uncomfortable:** tests-first is not the same as tests-sufficient.
Writing them against the recorded defects felt rigorous and still left both holes, because a test
that asserts a REFUSAL cannot distinguish the reasons for refusing. Where a guard has two paths to
the same visible outcome, the test must pin the path, not the outcome — usually by asserting the
ALLOW case that only the correct path produces.

| 2026-08-22, owner-decided; the mutation gate's finding is the durable half.

### R116·d — which command logic is portable, and which is judgment (closes the sweep)

Recorded so the portability sweep stops at the real boundary instead of being re-attempted, and so
nobody writes thin wrappers that look like progress.

**Extractable, and extracted:** `/companion:review`'s pile classification → `bin/review-pile.sh` +
the `review_pile` MCP tool. Which items need the owner, and HOW each must be asked (blocked = an
owner action, never a menu · decompose = questions, so interview · options-rec = sweep-eligible ·
options = a full menu is owed) is pure logic, and any MCP client can now drive a review while the
arrow-key menu stays native.

**NOT extractable, and why:**

- **`advise`** is critique. The "logic" is judgment about what is wrong and what it would cost.
- **`docs`** is deciding what is load-bearing enough to record. Same shape.
- **`cover`** ranks by *criticality × coverage gap*. Criticality — "blast radius if this silently
  broke" — is judgment. The computable half already exists: `candidates.sh` rank 4 reports flows
  with no `[E]` test.

**The portable half of all three is their INPUTS**, and those are already MCP tools: `board`,
`candidates`, `rework`, `tq_*`. A client that can read those can do the same reasoning; what it
cannot import is the reasoning itself, which is the model's job by design (R9: delegate recognition
to the model, detect structure generically).

**The floor that keeps this honest** is `dev/command-lint.sh`'s portability check: every command
must name an MCP tool or a `bin/` script, or carry `<!-- cli-only: <reason> -->`. It proves a
portable mechanism is NAMED, not that the work goes through it — a floor, not a proof, and it says
so in its own comment.

| 2026-08-22 — the sweep's real boundary, recorded so it is not walked twice.

### R116·e — a ceiling tuned to today's measurement is a bug with a delay on it

`ci-watch.sh` gives up on a CI run after `SHIP_CI_TIMEOUT` and reports **SHIPPED but UNWATCHED**
(exit 12). That ceiling has now been outgrown **twice** — 300s on 2026-08-01, 1800s on 2026-08-22 —
and both times the symptom was identical: **every** land exits 12, so R74's *enforced* watch
degrades into a no-op that still reads like a guarantee. The second occurrence is what caught the
attention; the mechanism is what matters.

**Both values were set by measuring what CI cost that week** (~21-24 min → 1800s), with a margin
thin enough for one ordinary month of new tests to eat. That is the bug. A give-up threshold is not
an estimate of anything, and the costs around it are **asymmetric**: too high is paid only when CI
genuinely hangs, and costs waiting; **too low is paid on every single ship, and costs the guarantee
itself, silently.** So it is now set by how long the *owner* is willing to wait — 5400s, which
clears today's 33 min by 2.7× and survives the mutation set doubling.

**Raising the number is the smaller half.** The durable fix is that the gap is now **measured**,
which is R81's own rule ("an unmeasured budget is not a budget") applied to CI rather than to hooks:
`mutate-gate.sh --validate` projects the slowest shard's wall-clock and **fails** the gate when it
can no longer fit inside the ceiling, warning from 60%. It runs in the default `./check.sh`, costs
no suite run, and would have caught this occurrence three weeks early. Both operands are **read from
their real homes** — the workflow for the shard count, `ci-watch.sh` for the ceiling — because
restating either is exactly how the pair silently diverged in the first place.

**Two defects in the projection itself, both found by its own mutations, both worth naming:**

- The first draft matched the shard count with `--shard [^ ]*/N`. The workflow writes
  `--shard ${{ matrix.shard }}/N`, and **that expression contains spaces** — so the pattern matched
  nothing, the check turned itself off, and it reported success. A check that silently measures
  nothing is the *same failure one level down* from the one it was written to prevent. The fixture
  now writes that line verbatim rather than a simplified form.
- Validating the two operands with one concatenated test (`"${shards}${ceiling}"`) let a **valid
  operand mask an empty one** — `"" + "5400"` is all digits — reaching a bare `[ "" -ge 1 ]`.

The empty-operand mutation **survived** the first test pass, and for the R116·c reason exactly:
the test asserted a clean *exit*, which the broken guard still produces — it only differs by an
`integer expected` line on stderr. Pinning the *reason* rather than the outcome caught it. That is
now twice in two days that "tests written first against a known defect" left a hole of this precise
shape.

**Also, and separately:** CI mutation shards 6 → 10. Purely wall-clock (33 min → ~21), not
correctness — the ceiling fix already removed the pressure. Free on a public repo, trivially
reversible, and the shard partition is gated by a test that is not pinned to any particular count.

**Corrected the same day, by the first run that used it.** The projection rounds the shard count
UP because the slowest shard sets wall-clock — then multiplied it by a constant derived from the
AVERAGE. It predicted 1275s; the median shard came in at 1276s and the **slowest at 1458s**, so the
guard was systematically optimistic by 14%. Worst-case rounding paired with an average-case
constant is the thin margin this entry is *about*, reproduced inside the fix for it. Now calibrated
on the slowest shard (100s carried).

**And the second run showed why "measured" was the wrong word for it.** Two consecutive runs of the
same matrix put the slowest shard at **97s and 85s** per mutation — 14% apart, on identical work,
because GitHub's runners differ run to run. 85s *was* a single sample, and taking it as the
measurement is what made the first version optimistic. The constant is a **bound over variance**,
not a measurement, and recalibrating it means taking the worst of several runs rather than the
latest one. The comment says so now, because the next person to touch it will be me.

Worth keeping as the general point: **a safety margin that is wrong in the optimistic direction is
not a smaller margin, it is a broken one** — it reports headroom that does not exist, which is the
same defect as the ceiling it replaced, only harder to notice.

| 2026-08-22 — found by a ship reporting UNWATCHED, i.e. by the system telling on itself.

### R116·f — cosmetic changes are batched, not shipped

**Owner directive, 2026-08-22: "batch cosmetic changes from now on."** Asked after three
consecutive ships in which the third (3.94.2) changed no executable line — a comment and an ADR
paragraph — and still spent a full ~24 min CI run. I had flagged that cost myself and shipped
anyway, which is the part worth noticing: the classification was correct, the restraint was not.

**The rule.** A diff that changes no executable line does not earn its own ship. `git commit` it
locally and stop; the next substantive ship re-runs the gate on the whole tree and carries it, via
`land`'s existing retry path for unmerged commits. Lives in `ship-it.md` rather than `STEERING.md`
deliberately: it applies precisely at the ship boundary, and a command doc is read on demand, so it
costs **zero** injected tokens — STEERING had 116B of headroom and this would have eaten all of it
for a rule that is irrelevant 95% of the time.

**Named cost, stated so it is a decision and not a discovery:** a batched fix sits **unpushed**
until real work follows it. For prose that is merely stale that is fine. For prose that is
*actively misleading about something someone will act on today* it is not — so that case asks
rather than assuming. This entry's own change is the first application: doc-only, committed
locally, unpushed.

**NOT enforced, and this is not laziness.** `ship.sh` cannot classify "cosmetic" for you. Deciding
which changed lines are comments requires knowing each language's comment syntax, which is exactly
the hardcoded-allowlist trap **R9** exists to prevent — and markdown, where most of these changes
land, has no comment syntax at all, so the files most in scope are the ones the heuristic cannot
read. A gate that is wrong in the blocking direction costs a refused real ship, which is far more
expensive than the CI run it saves. The judgment stays with the model; what changed is the default,
not the ability to decide.

| 2026-08-22, owner directive. Composes **R40** (right-sizing, same step), **R9** (why no gate),
**R69** (why `ship-it.md` and not STEERING).

### R116·g — the Cursor hook adapter is dropped, not deferred

Owner-decided 2026-08-23, from a 4-option menu, recommendation taken. `#132` proposed a Cursor
adapter (`beforeShellExecution` / `beforeMCPExecution`) so the two blocking guards would work
outside Claude Code. It sat blocked because there is no Cursor on this machine, and writing an
adapter against a hook API that can never be executed here is the one thing this repo has not
knowingly done.

**Dropped rather than left waiting, for three reasons that compound:**

- **R100 already declined per-host adapters** as a design decision. Leaving `#132` open was quietly
  re-litigating a settled question by letting it sit in a lane nobody closes.
- **The main value is unreachable there anyway.** Cursor's stop hook is observational — it cannot
  deny — so forced continuation cannot be ported no matter how good the adapter is. What remains is
  real but partial: `secret-guard` and `contract-guard` blocking.
- **A permanently-blocked item is worse than an absent one.** It trains the owner to skim past the
  ⏳ lane, which is precisely the indicator decay the 🚩 lane (R117) was just built to avoid. An
  indicator that is always non-zero for a reason nobody can act on stops being read.

**Cheap to reverse, which is what makes dropping honest rather than giving up:** this entry is the
whole design, so re-opening costs an ADR read and a `tq add`. The trigger to re-open is concrete —
a Cursor environment to verify against, nothing less.

**Also recorded: `#132` was mis-filed as `⏳ blocked`** (manual work only the owner can do) when it
was really a decision the model could act on once answered. The review surfaced that and presented
it as a decision, per `/companion:review`'s own rule. Worth noting because the mis-filing is what
kept it sitting: a decision parked in the blocked lane never gets asked.

| 2026-08-23, owner-decided. Composes **R100** (the original decline), **R117** (indicator decay),
**R38/R65** (the review's re-filing rule).
