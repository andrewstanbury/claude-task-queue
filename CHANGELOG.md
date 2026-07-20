# Changelog

Notable changes. Per-change detail lives in `git log`; this file keeps the headlines.

## companion 3.8.2 — 2026-07-19

*The secret-gate shield is now a warning-only indicator.*

- **No more always-on shield.** The status line no longer shows a persistent 🛡️ when the gate is on
  (the default) — a permanent "all fine" badge is noise. It shows `🛡️✗` **only when the gate is
  disabled** (the contextually-important state: a safety feature is off). The whole active-features
  section is omitted when nothing is active, so a quiet session reads `● v… : 📋 … : …`.

## companion 3.8.1 — 2026-07-19

*Status-line shield spacing fix.*

- **Shield icon renders at full emoji width.** Restored the 🛡️ variation selector so the shield is
  the same width as ✈️/📦 — without it the shield rendered text-narrow and looked like it had no
  space after it. (3.8.0 removed the selector to fix a *different* terminal's phantom-cell; the real
  cause was icon-width inconsistency, so all three feature icons are now uniform emoji width.)

## companion 3.8.0 — 2026-07-19

*Decisive autopilot mode + a status-line version indicator.*

- **`/companion:autopilot decisive on` (new mode, R59).** An opt-in intensity on top of autopilot:
  instead of parking every decision, it **picks its recommended option for reversible choices**
  (design/wording/direction included) and **records each**, then keeps going — parking or blocking
  **only** the irreversible-critical (a push, delete, spend, anything you can't cleanly undo). Every
  auto-pick is a recorded breadcrumb, so `/companion:review` can audit them and you can reverse any
  after the fact — that audit trail is what makes auto-deciding safe. Shown on the status line as
  `✈️⚡`. Off by default; a no-op unless autopilot is on. It deliberately relaxes R33/R49 (which
  always parked taste) **only** while you opt in — recorded as visible amendments.
- **Status line shows the plugin version.** `v<x.y.z>` (read from the manifest) now renders right
  after the beacon, so it's clear which companion is installed.
- **Shield double-space fixed.** The 🛡 glyph dropped its U+FE0F variation selector, which rendered a
  phantom trailing cell (a double space before the divider) on some terminals.
- **Status-line dividers.** Section dividers are now `:` (was `│`), with single even spacing between
  the active-feature icons (🛡 ✈️ 📦).

## companion 3.7.0 — 2026-07-19

*Pickup and triage become two commands again — `/companion:resume` re-surfaces earlier-session work, `/companion:review` clears the backlog waiting on you (R38/R39 re-split).*

- **`/companion:review` (restored).** Walks the backlog that needs *you* — parked ❓ decisions +
  blocked ⏳ owner-actions — one at a time, recommendation-first, recording each pick before new
  work. This is what runs when you turn autopilot off, and you can run it any time to clear the pile.
- **`/companion:resume` is now session-pickup only.** It re-surfaces this repo's carried-over tasks
  (autopilot off first, preserving each task's ❓/⏳/📋 class), then hands off to `/companion:review`
  for anything waiting on your input — instead of doing both in one command.
- **Why the re-split.** The two were merged in 3.4.0 for less surface; the owner chose the clearer
  seam — pickup (a session-boundary move) and triage (deciding the parked pile) are different jobs.
  Recorded as a visible reversal of the R38/R39 fold (the ledger notes it was taken over the
  recommendation to keep them merged). All the ritual's behavior + checks are preserved; only the
  command boundary moved. Surface goes 8 → 9 commands.

## companion 3.6.0 — 2026-07-19

*The living contract — the UX + quality-attribute record stays accurate at any moment while you build, as one plugin, not a split (R58).*

- **Prompt capture (new hook).** A `UserPromptSubmit` hook (`bin/capture.sh`) banks every prompt to
  a per-repo write-only store — the raw material for keeping the contract current. It **injects
  nothing** (zero runtime token cost, N1); it's read on demand, never pasted into context.
- **The contract reflex (steering).** When a request or edit changes what the user sees/does (UX) or
  a quality attribute (NFR), the working agreement now moves the `docs/UX.md` / `docs/NFR.md` entry
  **first** (recommendation-first) and queues the code against it — the continuous twin of
  `/companion:document`'s batch sweep, so the contract leads the code instead of chasing it.
- **Drift backstop (check).** `bin/contract-drift.sh` (generic, R9) surfaces behaviour that changed
  without a contract doc moving — run by `check.sh` and `ship-it`. Advisory by design (a warning,
  never a hard fail): most changes don't touch the contract, so a gate would false-positive; the
  reflex is the prevention, this is the visibility net.
- **`/companion:cover` (new command).** Ranks the UX paths by criticality × coverage gap and
  recommends the ideal test for each critical one, in the repo's own idiom, queued as tasks — it
  **recommends, never writes** test files. The test-recommendation arm of the same contract.
- **Why one plugin, not two.** A separate planning plugin would duplicate the queue/gate/status line
  and add a second SessionStart injection — the one real token cost — against N1, and reverse the
  R24/R52 collapse. The contract isn't separable from the loop that ships against it. (R58, 🔒.)

## companion 3.5.0 — 2026-07-18

*`/companion:ship-it` becomes contract-aware — the recorded contract can't drift a commit behind (R57).*

- **ship-it names the contract impact.** It reads the diff, identifies which R54 pillar it touches
  (UX / NFR / invariant), and folds the relevant logged design into the commit + PR body — loudest
  for UX changes, so a reviewer sees the experience delta, not just the code.
- **ship-it proposes the UX-doc update, recommendation-first.** When a ship changes UX, it drafts
  the `docs/UX.md` edit for you to confirm, then stages it **with** the code so they land in one
  commit. It never silently rewrites the contract — the owner still governs the experience, and the
  drift-guard check stays the backstop. (Same for genuine NFR/invariant changes.)
- **ship-it maintains a README docs index + `docs/` is the default home.** A `Documentation` section
  in the README links every `docs/*.md`, kept current each ship, so a GitHub reviewer reaches the
  contract in one click. `document` records generated contract docs under `docs/` by default.

## companion 3.4.0 — 2026-07-18

*Command-surface trim (9 → 7), each reversal signed off + logged in the ledger.*

- **`/companion:review` renamed to `/companion:resume`** (R38 🔒 amended). Same ritual —
  session-pickup (re-surface earlier tasks) + parked-pile review — under the name that leads with
  its first move. All behavior + checks preserved.
- **`/companion:regen` removed; its engine inlined into `/companion:redesign`** (R54/R55 amended).
  The bounded per-target rebuild (R1–R5: bound → checks-first-or-refuse → regenerate → apply-on-branch
  → auto-revert-on-red) is now redesign's D3 per-module pass. A single target is just one pass. The
  R56 command-gate test moved from `regen.md` to `redesign.md`.
- **`/companion:redesign` now requires `/companion:document` first** (D1). It rebuilds against the
  *logged* UX + quality-attribute contract, so it refuses to proceed without a current one.
  `document` stays a standalone command (it also feeds `/companion:advise`, R41).
- **`/companion:features` removed completely** (R50 🔒 amended). The per-repo toggle CLI + `features.sh`
  + the dead `companion_feature_set`/`_state` lib helpers are gone. **The secret gate is untouched** —
  its fail-safe per-repo `secret=off` read (G1/G2, isolated) and the steering-off read remain, with
  their invariant checks rewritten to drive the flag file directly. Per-repo secret/steering now toggle
  via a hand-written flag or `CLAUDE_COMPANION_SECSCAN=0`; autopilot/ship keep their own command.

## companion 3.3.0 — 2026-07-17

*UX-contract reorganization, just-in-time requirements capture, and a command-surface trim (10 → 9).*

- **`docs/UX.md` recatalogued into two axes — Happy paths + Design patterns.** The user-experience
  contract (R54 pillar a) is now organized as **journeys** (5 happy paths: first run · core loop ·
  hands-off drain · pickup · improve-the-design) plus the **recurring conventions** they're built
  from (7 patterns, defined once and referenced by name from each step). Every `[E]`/`[S]` row and
  its check survived the reshape; the `Slash commands` drift guard still holds.
- **The other contract docs cross-reference the UX spine.** `INVARIANTS.md` (per risk-area),
  `NFR.md` (per priority), and `REQUIREMENTS.md` (chronological) keep their native axes but now point
  rows/sections at the happy path / pattern they serve (`↳`) — one shared spine, not identical buckets.
- **Just-in-time requirements capture (new STEERING nudge).** When a load-bearing decision is made
  during normal work, Claude now offers to log its *why* **then** — tiered (check › 🔒 › 🔓,
  provenance `stated`), the inline twin of `/companion:document`. `document` becomes the batch
  backstop (pre-existing decisions + autopilot runs); JIT is the preferred, contemporaneous path.
- **`/companion:resume` folded into `/companion:review` (R39 amended, owner sign-off).** The
  on-demand session pickup is now `review`'s step 1 (runs `resume.sh` — autopilot-off-first +
  class-preserving reinstatement — then walks the pile). All three R39 behaviors + checks preserved;
  one fewer command. `resume.sh` (the script) stays, shared with the SessionStart hook.

## companion 3.2.0 — 2026-07-17

*Maintainer-facing testing & contract hardening — **no user-visible behavior change vs 3.1.0** —
making 3.1.0's regen/redesign trustworthy before a real rebuild.*

- **Behavior-coverage net (R56) — the suite grew from ~38 to 53 checks.** A 3-agent audit found
  "beacon-class" gaps: intended, load-bearing behaviors no test pinned, which a from-scratch regen
  would silently drop (as a dogfooded `regen` of `statusline.sh` dropped the autopilot-beacon
  animation). Added characterization tests closing them — the autopilot Stop-nudge payload, resume's
  `done-when`/latest-`note` sub-lines, `tq`'s report `→ next` pointer + glyph header + note-append,
  `features`→`autopilot` delegation, the compaction R49 clause, non-AWS vendor-key blocking (which
  also corrected a *false* `INVARIANTS.md` claim — it advertised six vendors, only AWS was tested),
  the stall-counter reset, and more — plus **structural guards** that each command prompt keeps its
  critical gate step, and the statusline's section-order + semantic colors. The command layer tops
  out at structural guards: a prompt's behavior is judgment, not mechanically verifiable (the R56 ceiling).
- **The UX contract is self-defending.** `docs/UX.md` (R54's contract pillar a) was synced to the
  real **10** commands, and a check now **fails CI** if a command ships without a UX.md entry — so
  the contract can't silently drift from reality (it had, mid-development: 8 vs 10).
- **Dogfooded both edit commands (R54/R55).** `regen` of `statusline.sh` correctly returned "don't
  apply — already faithful" (and its R5 behavior-check caught a regression the tests missed);
  `redesign`'s **D0 gate correctly refused** a blind whole-app rebuild because the net wasn't yet
  complete — which is exactly what the behavior-net work above then addressed.

## companion 3.1.0 — 2026-07-17

- **Contract-preserving regeneration — new `/companion:regen` + `/companion:redesign` commands
  (R54/R55).** Two discoverable commands beyond critique: **`regen <target>`** rebuilds one bounded
  target from the ground up against the recorded contract; **`redesign`** rebuilds the whole
  application as a sequence of bounded, check-gated passes. (`advise` stays **critique-only** — the
  edit modes were split out into their own commands so they show in the `/` menu.) Both treat
  implementation as disposable but are **gated**: they clear autopilot first, refuse unless every
  relevant invariant check is green (`redesign` verifies whole-app coverage up front), apply only on
  a branch, re-run `check.sh`, and **auto-revert on any red** — so a rebuild **can't silently drop a
  fail-safe**. The **logged contract is UX + quality attributes** (`docs/UX.md` + `docs/NFR.md`); the
  safety net is the existing checks (`docs/INVARIANTS.md` + `check.sh`), not a catalogue. The uncheckable
  R45 guard (G4) stays a documented owner-ack residual.
- **`/companion:document` tags by contract pillar (R54).** Each finding routes to its pillar doc —
  safety-invariant → a check, UX → `UX.md`, agreed-NFR → `NFR.md`, incidental/technical → disposable.
- **The R54 contract foundation the rebuilds read.** Created the three contract pillars —
  `docs/UX.md` (experience), `docs/NFR.md` (7 owner-agreed quality attributes), `docs/INVARIANTS.md`
  (the enumerated safety net) — and closed two invisible fail-safe gaps with tests: the secret gate
  stays **active** on a corrupt flag file, and it **sources no lib** so a broken dependency can't
  disable it.
- *Prototype note:* the regen/redesign modes are prompt flows, not yet exercised on a real rebuild.

## companion 3.0.1 — 2026-07-17

- **Sharpen the recommendation reflex in STEERING.** Added a lead "Moves" beat so the first thing
  Claude checks each turn is: *decision-shaped → recommendation-first options (R5), and close every
  reply with a one-line brutal-honest verdict* — while explicitly **not** menu-ifying trivial asks.
  Raises the salience of the R5/R49/R51 contract without new machinery or duplication.

## companion 3.0.0 — 2026-07-17

- **Retired `touch.sh`, the format-on-edit hook (major — a user-facing surface removed).** The
  enforced core now has **no *execute* hook** — only *block* (secret gate), *inject* (session-start),
  and *control-flow* (autopilot). Formatting is a steering nudge now, not an enforced pass; the
  `format` feature toggle and `CLAUDE_COMPANION_TOUCH` env var are gone. **Retires R25**; **R51**
  records the move. Whole-project formatting is still available via `/companion:advise`.
- **Nudge + queue as the product's shape (R52, direction A).** The companion is framed as one loop —
  **propose → queue → drain**: context surfaces a recommendation-first nudge → the owner picks → it
  enters `tq` → it drains. STEERING gains pick-from-CLI options as the **default shape of every
  owner-input moment** (with own-answer / just-chat escapes), an **always-on brutal-honest verdict**,
  a **context-nudge catalogue** (debt → tq task · big blast → split · repetitive drain → autopilot ·
  done → ship-it), and **TDD-as-discipline** (no test-writing mandate; the `--done` acceptance
  drives). Delivered as steering, not new hooks — the only proactive plugin surfaces are SessionStart
  injection + statusline + `AskUserQuestion` (autocomplete-prompt injection is not possible; verified
  with claude-code-guide).
- **One-plugin packaging freed (R52 amends R24).** R24's anti-sprawl *principle* stays locked; the
  single-plugin *packaging* is now a current-state fact, so a future `tq`-standalone extraction is
  un-blocked.
- **Per-repo feature surface — `/companion:features` (R50).** One place to view and flip every
  enforced-core capability per repo — **secret** (the gate) · **steering** (the SessionStart
  injection) · **autopilot** · **ship** — resolution order **env var → per-repo flag → default**,
  with a loud warning when the irreversible secret gate is disabled. (Landed here from prior
  uncommitted work; the `format` toggle it once carried was removed with `touch.sh`, above.)
- **Ledger overhaul — a 4-agent adversarial audit of all 52 entries, then a sweep.** Synced stale
  bodies to the shipped system (R28/R24 no longer name the deleted formatter or call `tq` a
  "fallback"; R7 no longer contradicts the secret gate; dead 4-plugin vocab reworded in R15/R19/R21;
  R18 retired). Demoted two shipped-changelog build-trackers (R30/R32) from 🔒. Moved gotchas/impl out
  of the ledger (R44 → a bats check; R45 → code comment; R46 → `LESSONS.md`; R42 → R39). Deduped the
  recommendation contract to a canonical **R5** (R17/R49/R51/R52 now cite it; STEERING states it
  once). Extracted the ledger-honesty rules to **R53**. Downgraded locked aphorisms/specs to 🔓
  (R6/R11/R12/R16/R37/R40/R41/R47); R50's secret-gate fail-safe invariant deliberately kept 🔒.
- **Tests:** removed `touch.sh`'s cases, added an R44 atomic-write guard; the enforcement spine is
  intact (**35 cases green**). `check.sh` unchanged.

## companion 2.12.1 — 2026-07-14

- **Surface the latest note on cross-session resume** — completes the notes-array feature from
  2.12.0, which *stored* `.notes[]` but nothing *read* it. `companion_open_tasks` (the
  resume / post-compaction re-anchor renderer) now shows a `└ note: <latest>` line under each
  carried-over task, beside the existing `└ done when:` line — so a crash/compaction resumes from
  the last breadcrumb, not just the subject. Falls back to legacy `.description` for pre-array
  tasks. Resume-only: the live `tq report` stays Design-D compact, so **R47** is untouched.

## companion 2.12.0 — 2026-07-14

- **Ported the two verified fixes from third-party PR #126** (author co-credited): `tq note` now
  **appends to `.notes[]`** instead of overwriting `.description`, so a second breadcrumb no longer
  erases the first; and the autopilot continue-nudge (`stop-autopilot.sh`) now names the next task's
  **`#id` + done-when**, so the model resumes against acceptance criteria, not a bare subject. The
  **symlink-safe `SELF` resolution** across all `bin/` scripts (relative `readlink` targets resolved
  against the symlink's own dir — fixes central-symlink installs) was salvaged from the same PR.
- **Declined the rest of #126, on review** — its `tq report` rewrite reversed locked **R47**; its
  statusline count refactor dropped in-progress tasks from the `📋` count (a regression, and not one
  of the PR's stated bugs); it added a dangling `lib/tidy.sh` reference; and it stripped `R##` comment
  anchors repo-wide (kept, per **R45/R46**). PR #126 superseded and closed with the rationale.

## companion 2.11.0 — 2026-07-14

- **The recommendation contract** (ledger **R49**, 🔒) — sharpens the brutal-honest posture from
  advisory prose the model skips into an explicit contract: a request that asks you to
  choose / redesign / compare / evaluate / "what do you recommend" **owes 2–4 genuinely different
  options, each naming its cost, the recommended one marked first, plus the honest read** (up to
  "don't do this"). It fires **identically off or on autopilot** — off, ask it live
  (`AskUserQuestion`); on, park the *same* payload in the `❓` subject so the resume review is a real
  choice, not a rubber-stamp. STEERING + the `ask-guard` deny message; refines **R36/R38/R39**;
  generic per **R9** (judgment by reading the request, never a keyword hook).

## companion 2.10.0 — 2026-07-14

- **`tq report` → Design-D compact** (ledger **R47**, 🔒) — the report is now a glyph-count header
  (`📋 ▸n ◻n ❓n ⏳n ✔n`), **one line per active task**, completed shown as a **count only**, and a
  trailing `→ next: #id` pointer. `done_when` is no longer rendered in the live report (it reprints
  on every `add`/`doing`/`done`, so its height is a constant tax) — it's still **stored** and
  re-surfaced on cross-session resume, so crash-resume is unaffected. STEERING notes the `→ next`
  pointer is a *mechanical* default: override it aloud when blast-radius/dependency says otherwise.
- **Testing policy: keep the enforcement spine, don't grow format tests** (ledger **R48**, 🔒) — an
  audit found the ~30-case suite is mostly real enforcement (secret gate, hook-fuzz contract,
  autopilot control-flow, ship-mode-never-touches-default, validators), not theater. Policy: keep
  `check.sh` green; when an intentional change reddens an assertion, **loosen it to behavioral**
  rather than pin cosmetics; don't add a format test per feature. Removed 4,500 lines of stale
  `hud-gates` worktree tests. Reshapes CLAUDE.md's "verify with `./check.sh`" into keep-green-don't-grow.

## companion 2.9.0 — 2026-07-13

- **`/companion:document` refinement + first dogfood run** (ledger R41 refined; R42–R46 added). The
  command now presents its candidate *whys* as the multiple-choice options — the owner picks or
  overrides, there is **always** an open-ended "write your own rationale," and **only an active pick
  records an entry** (an unchosen guess never becomes a 🔒). Running it on this repo recorded five
  previously-undocumented, load-bearing decisions: the `❓/⏳` prefix-view over `pending` (R42), the
  secret gate now covering `NotebookEdit`'s `.new_source` (R43), `tq`'s atomic temp-then-`mv` writes
  (R44), `stop-autopilot`'s redundant default-branch guard (R45), and `IFS=$'\t'` on tab-delimited
  reads (R46) — three backed by executable checks. Fixed two stale-doc drifts (statusline
  `refreshInterval` comments, MAP `touch.sh` row).

## companion 2.8.1 — 2026-07-13

- **De-dup autopilot flag teardown** — new `companion_autopilot_clear()` shared helper; `resume.sh`
  and `autopilot.sh off` both call it instead of a hand-rolled `rm -f`, so the teardown can't drift.
  Internal refactor, no behavior change (closes the R39 devil's-advocate follow-up).

## companion 2.8.0 — 2026-07-13

- **`/companion:document`** (ledger R41) — new command, the *producer* side of advise: scans an
  existing repo for load-bearing, undocumented decisions and records them tiered *executable check ›
  🔒 › 🔓 › dropped*, with strength-of-why setting the lock and a provenance tag — so advise stops
  guessing and can't reverse a critical choice that was never written down. Reuses the R29/R38 loop,
  writes the existing ledger (no new doc format), generic per R9, a command not a hook (R28).

## companion 2.7.0 — 2026-07-13

- **`/companion:ship-it` produces review-optimized output** (ledger R40) — structured commit/PR
  messages (What/Why/requirement-IDs/tasks/tests), curated one-commit-per-logical-unit history on
  `autopilot/*` merges instead of an opaque squash (reshapes R34's squash-on-ship; the per-turn
  capture is unchanged), structured PR bodies, and a right-size nudge for large/mixed diffs — so
  shipped work reads as easy-to-review even when no human reviews it.

## companion 2.6.0 — 2026-07-13

- **`/companion:resume` is a triage handoff** (ledger R39) — it turns autopilot off first
  (announced, never a silent clobber) so the resurfaced pile comes back to the owner, reinstates
  carried-over tasks preserving their `❓/⏳/📋` classification (never promoting a parked decision to
  a plain open task), then runs the R38 review. The fix lives in the task's *type*, so
  triage-vs-drain survives in either mode.

## companion 2.5.0 — 2026-07-13

- **Turning autopilot off starts a parked-pile review** (ledger R38) — new `/companion:review`:
  walks the `❓ [parked]` + `⏳ [blocked]` pile one at a time, recommendation-first, and records each
  pick back to `tq` **before** any new work. Triggered two ways so neither path misses it — the
  `/companion:autopilot off` command invokes it, and a STEERING clause fires it on the plain-language
  "turn it off" path. Scope is parked+blocked only (open tasks need doing, not deciding); each item
  can be deferred and the owner can bail (default, not a wall); clean no-op when the pile is empty.
  A **command, not a hook** (R28 — presenting recommendations is `AskUserQuestion` workflow), reusing
  the `/companion:advise` loop (R29) rather than a parallel machine.

## companion 2.4.0 — 2026-07-13

- **Domain-glossary layer** (ledger R37) — a project the companion governs keeps a terse,
  Claude-facing `docs/GLOSSARY.md` mapping a *coined term → its meaning* (e.g. "materialization
  cascade"); Claude coins one when a concept recurs and reuses it when naming, so one word carries
  twenty and naming stays consistent. Joins the map + ledger + stack-notes as part of a
  self-describing project (STEERING), **loaded on demand — not injected each session** — so it can't
  erode the token-efficiency value (R3). Steering convention, not a hook (R28). The one idea mined
  from mattpocock/skills' `CONTEXT.md`; this repo dogfoods its own `docs/GLOSSARY.md`.

## companion 2.3.0 — 2026-07-12

- **Autopilot reframed as "keep-going," not "owner-away"** (ledger R36) — it means keep draining the
  queue without stopping; the owner may be present, queuing tasks and keeping it on deliberately.
  Behaviors are unchanged (don't stop to ask, park decisions + design/taste choices, reversible-only)
  — the "away / when they return" framing is gone from STEERING, the ask-guard, stop-autopilot, and
  the docs. This dissolves the R33 present/absent tension: there's no presence to detect.
- **Ship-mode won't commit a hardcoded secret** (R34 gap fix) — before an auto-commit checkpoint it
  scans the staged diff for high-confidence key shapes and skips (unstages) if one is present
  (`git add` isn't seen by the secret gate). The gate keeps its own inline copy of the regex so it
  never gains a fail-open dependency.

## companion 2.2.0 — 2026-07-12

- **Ship-mode** (ledger R34) — `/companion:autopilot ship on`: while autopilot is on, the Stop hook
  auto-commits each turn's work to an `autopilot/*` branch (reversible checkpoints; **never the
  default branch, never a push**) for you to review + `/companion:ship-it` on return. Shown as 📦.
  The safe subset of "auto-ship": commit is reversible; the push/merge stays your manual command.
- **ship-it prunes merged branches** (ledger R35) — after merging to the default branch, it deletes
  the branch it shipped (local + remote) and prunes other `--merged` branches via `git branch -d`
  (never `-D`, never the default/current); shared repos are confirmed before deleting remote branches.
- **Status line regrouped** (R34) — three plugin sections, then generic: ⠋ beacon · │ 🛡️ ✈️ 📦 │
  (active features) · │ 📋 ❓ ⏳ │ (the queue, its own section) · model · git. The shield gained an
  emoji variation selector (🛡️) so it renders at consistent width with the other icons.

## companion 2.1.0 — 2026-07-12

- **Status-line task icon** — the open-task count is now `📋 N` (was `◻N`), with a space after the
  icon (and after `❓`/`⏳`). The emoji renders consistently where `◻` could show as a tofu box.
  (The per-item bullet in the `tq` report + resume stays `◻`.)
- **Autopilot parks design choices** (ledger R33) — a visual/design/direction/wording choice is the
  owner's call even when reversible, so under autopilot it's parked (`❓`, with options +
  recommendation) and surfaced on return rather than auto-decided. Refines R26: reversibility was
  the only auto-decide axis; ownership of taste was the missing one. STEERING + the ask-guard
  message, no new hook.

## companion 2.0.1 — 2026-07-12

- **Docs reconcile** (no behavior change) — `AGENTS.md` and `docs/ROADMAP.md` had drifted (last
  reconciled at 1.3.0): refreshed the enforced-core lists (touch.sh format-only + autopilot), the
  command set (`audit`→`advise`), the test-file split (`companion-{core,hud,fuzz}.bats`), and the
  decision arc through R32. Documented `tq`'s single-writer assumption in its header.

## companion 2.0.0 — 2026-07-12

Self-critique pass: `/companion:advise` run on the plugin itself (an independent 4-lens critic
panel) found a real bug and that several 1.7–1.9 additions over-reached (ledger R32). All 9 fixes:

- **BREAKING — `/companion:audit` retired**, merged into `/companion:advise` (which now also does
  the whole-project cleanliness sweep; few findings → one-at-a-time, many → queued directly).
- **Bug fix** — the status line mis-parsed a model name or project path containing a space (default
  `IFS` split the tab-separated fields); now `IFS=$'\t'`, with a regression test.
- **`touch.sh` drops the `pre-commit` fast-path** — it could hang an edit for minutes on first run
  and ran linters, not just formatters; per-extension formatters (config-aware) remain.
- **`pre-compact.sh` deleted** — it was an advisory nudge wearing a hook, contradicting R28; the
  reliable compaction re-anchor (SessionStart) stays.
- **Compaction re-anchor trimmed** — re-injects the queue + LESSONS + a pointer, not the full
  ~2.4k-token STEERING (saves that per compaction).
- **Status line `refreshInterval` 1 → 3s** — keeps the beacon while cutting the idle wake ~3×.
- **Secret gate**: vendor-anchored key shapes still block (exit 2); the fuzzy `name=value`
  heuristic now only *warns*, so it can't false-block a legitimate edit.
- **`tq cancel <id>`** — retract a mis-queued task (cancelled; excluded from counts + resume, file
  kept) instead of a false `done` or a lingering `open`.
- **README** — a commands list (incl. `advise`), a status-line glyph legend, and a "turn on the
  status line" callout.

## companion 1.9.0 — 2026-07-12

Completes the R30 Claude-first refinements (Batch 3 of 3):

- **Compaction re-anchor** (R30·d2) — `session-start.sh` fires on `source=compact`, so after the
  context is summarized it re-injects STEERING + the live queue (with each task's done-when) +
  LESSONS, with a compaction-aware lead. A new `pre-compact.sh` (PreCompact) nudges the model to
  freshen the in-progress breadcrumb/done-when just before the summary.
- **Challenge slot + devil's-advocate** (R30·d6) — `/companion:ship-it` now requires stating
  risks / what-changes / R-IDs before committing, and spawns a devil's-advocate sub-agent (an
  independent context prompted to attack the change) for consequential ships.
- **Audit is a sub-agent panel** (R30·d5) — `/companion:audit` fans out one lens per sub-agent
  (size / debt / blast-radius / perf), synthesizes, and queues — main context stays clean.

## companion 1.8.0 — 2026-07-12

- **Tasks carry a `done-when`** (R30·d1) — `tq add … --done "<acceptance>"` (or `tq done-when <id>`);
  the acceptance test renders in the report + SessionStart resume, so a task re-read after a
  context compaction re-derives the right next action instead of guessing at a bare subject.
- **STEERING is checklist-first** (R30·d3) — each section opens with an imperative "Moves"
  checklist; the prose rationale stays below it. Scannable for compliance, keeps the *why*.
- **CI hardening** (R30·d8) — a hook-fuzz test (every hook survives empty / garbage / truncated /
  huge / emoji stdin without crashing) + strict conditions locked in: scrubbed git identity, so a
  test that forgets `-c user.email` fails in CI rather than in a user's repo.

## companion 1.7.0 — 2026-07-12

- **Project `LESSONS.md`** (R30·d7) — a curated, model-maintained file of repo-specific gotchas
  (portability/test/CI traps), injected each session by `session-start.sh` so a new session doesn't
  re-learn them. Gotchas only; decisions stay in the ledger, work in the queue.
- **Activity-only beacon** (R30·d9) — the status-line beacon now animates only while there's work
  in motion (autopilot draining or a task in-progress) and shows a static ● when idle.
- **Formatter respects the project's toolchain** (R30·d4) — `touch.sh` prefers the project's own
  `pre-commit` on the touched file when configured, and honors black-vs-ruff from `pyproject`,
  before falling back to the per-extension formatter.
- **Playtests are autopilot-conditional** (ledger R31) — under autopilot the companion no longer
  raises playtests (it captures a `⏳ [blocked] playtest` task instead, resurfaced on return);
  with autopilot off it offers a quick playtest when the change has a human-observable surface.

## companion 1.6.0 — 2026-07-12

- **`/companion:advise`** (ledger R29) — an independent, brutally-honest critique ritual. Takes a
  target (file / subsystem / decision / topic; default: the whole project), spawns a critic
  **panel** with distinct lenses so the critique comes from contexts that didn't build the thing,
  and presents each recommended change as a **recommendation-first `AskUserQuestion`, one at a
  time**; then closes the loop into `tq` + an offered ledger entry. Every critic may conclude "no
  change" — a manufactured delta is the fake pushback the steering doc forbids. Operationalizes
  the R5/R17 challenge posture as an on-demand command; owner-present (blocked under autopilot).

## companion 1.5.0 — 2026-07-12

- **Status bar redesign** — the single `📋 N` count split into `◻ open · ❓ parked · ⏳ blocked`,
  plus git `↑ahead ↓behind`. The parked-task scan behind it is now a single `jq` pass (~18×
  faster; it runs every second).
- **Architecture realignment (ledger R28)** — the hook/steering boundary is now decided by a
  component's *nature*: code only for what must **execute** (the formatter) or **block** (the
  secret gate), plus autopilot's control-flow guarantee — **judgment and nudges are steering.**
  This **retired the R27 edit-gates** (design-preview + return-review) and the intent→outcome
  reminder; `touch.sh` is now **format-only** (blast-radius + size → steering, R25 reshaped).
  Deleted `work-guard.sh`, `prompt.sh`, `intent-note.sh`; retired `CLAUDE_COMPANION_GATES` and
  `CLAUDE_COMPANION_SIZE_BUDGET`.
- Tests split into `companion-core.bats` / `companion-hud.bats`. CI hardening folded in from
  1.4.x (git identity in tests, jq broken-pipe, macOS bash-3.2 status-line crash).

## companion 1.4.0 — 2026-07-12

- **Animated status line** — a braille-orbit health beacon (`refreshInterval:1`), `│ 🛡 │`
  spacing fix, consolidated off the deprecated `hud` plugin onto `companion`. (Kept in 1.5.0.)
- **R27 edit-gates** (design-preview + return-review blocks, intent→outcome reminder) + 🎨/🔒
  status icons — **retired one day later in 1.5.0 (R28)** as the wrong side of the hook/steering
  line. `author` field added; macOS + CI hardening (1.4.1–1.4.2).

## companion 1.3.0 — 2026-07-12

- **`/companion:ship-it`** — verify the project's gate → commit → push → PR/merge to the
  default branch. Codifies the ship flow.
- **`/companion:resume`** + `bin/resume.sh` — manually re-surface this repo's unfinished tasks
  from an earlier session (the on-demand twin of the automatic SessionStart resume).
- Internal: the shared `lib/companion.sh` (renamed from `lib/autopilot.sh`) now holds the
  cross-session open-tasks helper, used by both SessionStart and manual resume.
- First step of "restore features onto the one-plugin spine" — the removed commands other than
  these two stay gone by owner choice.

## companion 1.2.0 — 2026-07-11

- **Autopilot is enforced + persisted** (ledger R26). `/companion:autopilot on|off` sets a
  per-repo flag that survives restarts; while on, the Stop hook auto-continues the queue (until
  only parked ❓/⏳ remain, no-progress capped) and a PreToolUse guard blocks `AskUserQuestion`.
  The status line shows ✈️. Env: `CLAUDE_COMPANION_AUTOPILOT_CONTINUE`, `_MAX`, `_STATE_DIR`.
- **Design-preview restored** to the steering doc: the full wireframe convention
  (`╔═╗` container, `▒` input, `█` primary, recommended-first) — steering-only, no gate.
- (These closed the two advisory-only gaps from the post-rebuild capability review.)

## companion 1.1.0 — 2026-07-11

- **Clean-as-you-touch** (`bin/touch.sh`, PostToolUse): after you edit a file, format it with
  the project's own formatter, surface its blast radius (dependents), and flag it if it's over
  the size budget. Non-blocking; `CLAUDE_COMPANION_TOUCH=0` disables, `CLAUDE_COMPANION_SIZE_BUDGET`
  tunes size. A conscious partial-reversal of the rebuild's austerity (ledger R25).
- **`/companion:audit`** — on-demand whole-project sweep (size / debt / blast-radius hotspots),
  queues the fixes via `tq`.
- The task queue is now fully self-owned (its own store, not native tasks), reprints on every
  state change, and a minimal status line returned. (Rolled up from the same day.)

## companion 1.0.0 — 2026-07-11

**Ground-up rebuild.** The four plugins (`task-queue`, `tidy`, `charter`, `hud`) were
replaced by one plugin, **`companion`**, built on a single principle: *steering is a
document, enforcement is code, never confuse the two.*

- **Steering** — all the prose that shapes how Claude works (task queue, the brutal-honest
  recommendation posture against the requirements ledger, clean-as-you-go, autopilot) now
  lives in one file, `plugins/companion/STEERING.md`, put in context once per session.
- **Enforced core** — the only behavior that must execute or block, kept as code: a pre-write
  secret gate (`secret-guard.sh`), cross-session task resume (`session-start.sh`), and the
  `tq` queue fallback for models with the native task tools gated off.
- **Retired**: the per-hook token-budget NFR, the cross-plugin drift-guard and mirrored
  detectors, the status line (`hud`), and every advisory Stop/PreToolUse prose-hook.
- ~12,500 lines → a few hundred. Rationale and reshaped requirements: `docs/REQUIREMENTS.md`
  (R24).

## Before 1.0.0

The four-plugin history (task-queue / tidy / charter / hud, versioned independently through
mid-2026) is in `git log` — the commit messages carry the same detail this file used to.
