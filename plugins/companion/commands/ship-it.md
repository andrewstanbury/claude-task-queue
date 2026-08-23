---
description: "[pr] [--gate <cmd>] — verify, sync contract docs, commit, push, merge to the default branch; pr opens a PR instead"
argument-hint: "[pr] [--gate <cmd>]"
---

Take verified work from the working tree to shipped. Pushing and merging are externally
visible, so be careful and confirm the irreversible steps.

**`$ARGUMENTS` sets two things, both optional:**
- **`pr`** — take the **PR flow** (step 5's alternative) instead of merging to the default branch:
  everything through step 4 is identical, then push the branch and open the PR rather than calling
  `land`. Decided up front so you don't discover it mid-flow. **It leaves the rail** — step 5's PR
  bullet enumerates the four `land` guarantees it forgoes, two of them safety. Read them before
  offering `pr` as the easy option.
- **`--gate <cmd>`** — the project's gate command, when it isn't a `./check.sh` / `.companion/check.sh`
  the rail can find on its own (`--gate npm test`, `--gate make test`). Pass it through **verbatim**
  as the `gate` array argument to *both* tool calls — `ship_preflight`'s `gate` and `ship_land`'s
  `gate`. With none, recognize the gate yourself (R9) as before; **never ship without one** (exit 3
  means stop).

**The mechanical spine runs on the rail (R71):** the **`ship_preflight`**/**`ship_land`**/
**`ship_handoff`** tools on the `companion-tq` MCP server (R100/Pass 5b — the same portable surface
any MCP client reaches; `bin/ship.sh` is the CLI they wrap, byte-identical behavior) execute
the deterministic steps in two calls — `ship_preflight` before your judgment, `ship_land` after it —
so you spend turns on judgment, not on running git one command at a time. **The rail bails loudly
instead of improvising**; each nonzero exit hands a specific problem back to you (codes below).
Judgment stays yours: the case, the devil's-advocate, the contract impact, the flow-page
proposal, the commit message, the history curation.

1. **Preflight — Verify FIRST, one call.** Call **`ship_preflight`**
   (if `--gate <cmd…>` was passed, or the repo has no `./check.sh` / `.companion/check.sh`, pass
   it as the `gate` array — `{gate: ["make", "test"]}`, `{gate: ["npm", "test"]}`, whatever it uses;
   recognizing an unpassed one is your job, R9.
   Remember the same command — step 5's `ship_land` needs it as its own `gate` argument). This runs the
   gate, the contract-drift backstop (R58 — read its output), the queue (it rides the commit — R96) (R60 — the queue
   snapshot rides the ship), and prints the branch/upstream summary + `git status` + diff stat
   you'd otherwise gather by hand. **Gate failed (exit 4) → STOP and report; do not ship broken
   work. No gate found (exit 3) → supply one or stop.**
2. **State the case before you commit (the challenge slot, R30·d6).** In one short block, name:
   **risks** (what could this break, or what would you regret?), **what it changes** (behavior /
   interface / requirements — cite the R-IDs it touches or would reverse), and **why it's still
   worth it.** A real answer only exists if you actually weighed the change — that's the point;
   don't skip it.
   - **ALWAYS spawn a devil's-advocate sub-agent — this is the default, not a judgment call.**
     Hand it the diff + the goal and ask it to find every reason *not* to ship, independently, and
     to *demonstrate* failures rather than speculate. Surface its objections verbatim, then verify
     each yourself before accepting it — an adversary can be wrong too. The old wording ran one only
     "if the change is consequential", which asks you to rate the riskiness of your own work: the
     least reliable judgment available, and the step a near-miss depends on. **Evidence it earns its
     keep:** the 2026-07-29 ship was green on `check.sh` with 130 tests and the DA still found five
     real defects — a batched `jq` that wiped the whole backlog on one corrupt file, a prune that
     deleted a store holding parked work, an `rm -rf` that followed a symlink out of the store, and
     a secret gate that failed OPEN on array content. All five would have shipped.
   - **Scale the DEPTH to the risk, never the decision to run one** (R12 proportionality): a
     focused pass on a small, reversible diff; a full adversarial pass — parser/edge-case attack,
     delete paths, fail-open paths, portability — for anything touching `.companion/da-paths`
     surface, a deletion, or a requirement reversal. **Depth is YOUR judgment; the `da` finding is
     what `land` enforces.** They are deliberately different scopes: a ledger-only edit reverses a
     requirement but changes no behaviour, so it is not in `da-paths` and will not be blocked —
     run the pass anyway, because that is a risk the gate cannot see. A rubber-stamp from a context that didn't build
     the change is worth little; an objection from one is worth a lot. `land` REJECTS a bare
     "clean" (R78), so a pass that genuinely found nothing must still say what it *examined*.
3. **Sync the contract + docs before you land (R57).** A ship that changes what the user *sees or
   does* must not leave the recorded contract a commit behind. Preflight already printed the drift
   backstop's warnings — act on them here:
   - **Name the contract impact.** Read the diff and identify which R54 pillar it touches — **UX**
     (a command / flow / output the user sees), **NFR** (a quality attribute), or an **invariant**
     (a must-hold). Pull the *relevant logged design* for what changed — the affected
     `docs/flows/<flow>.md` spec (steps + tests + quality, R66 machine shape), the invariant — and fold it into
     the commit body (and the PR body), **called out loudest for UX changes** so a reviewer sees the
     *experience* delta, not just the code.
   - **Propose the flow-page update, recommendation-first — the contract stays owner-governed.** If the
     change alters UX (a command added / removed / renamed, a flow or output changed), **draft the
     `docs/flows/<flow>.md` edit** — the `steps:` lines to add / change / remove and the `tests:` +
     Changes lines, keeping each test line's `[E]`/`[S]` kind — and present it recommendation-first
     for the owner to confirm or adjust (the same `AskUserQuestion` shape; under autopilot, park it as
     a `❓` carrying the drafted edit). On approval, leave the flow-page edit in the tree — `land`
     stages everything, so it rides the same commit as the code and the contract never drifts a
     commit behind. Do **not** silently rewrite the contract: the R61 anti-drift gate + the
     drift-guard stay the backstop (a broken Tests ref fails CI), and the owner still governs what
     the experience *is* (R54). Same for a genuine quality or invariant change — propose the
     `docs/flows/_quality-bar.md` / `docs/INVARIANTS.md` edit.
   - **Refresh the README docs index.** Ensure the `README` has a **Documentation** section that
     links each `docs/*.md` (the contract + the map), and update it if this ship added / removed /
     renamed a doc — so a GitHub reviewer reaches the docs in one click. Keep it a plain link list;
     don't copy the docs' content into the README (that just makes a second thing to drift).
4. **Write the message + right-size (R40) — then curate if needed.** Preflight's status/diff-stat
   tells you the shape. **Right-size first:** if the diff mixes unrelated concerns or is large, say
   so in one line and offer to split it into separate logical commits — commit those units by hand
   (each with a full message), then let `land` ship them via its retry path (it ships existing
   unmerged commits when nothing is staged). On an **`autopilot/*` or `wip/*` (handoff, R72) branch**, curate the checkpoint
   string the same way first: `git reset --soft "$(git merge-base HEAD <default>)"`, then re-commit
   in logical groups — don't merge raw checkpoints, don't flatten to an opaque squash
   (`rebase -i` is unavailable; the soft-reset is the equivalent). For the single-unit common case,
   write **one review-optimized message to a temp file** for `land -F`:
   - **Subject** — imperative, ≤~72 chars, naming *what* changed (and this project's version +
     the requirement IDs it touches when it has them). *Generic (R9): use the project's own
     convention — Conventional Commits, a ticket prefix, whatever it uses — don't impose one.*
   - **Body** — **What changed** (the concrete edits), **Why** (the outcome, not the mechanics),
     **Requirements/issues** it touches or reverses (cite the IDs — a 🔒 needs explicit sign-off),
     **Tasks** it closes (the `tq`/tracker items), and the **Test result** (`check.sh` green, N tests).
   - If a version/marketplace manifest is part of the change, make sure it's bumped **before** land
     (the gate re-runs there and checks version match).
5. **Land — one call.** *(Invoked with `pr`? Skip straight to the PR-flow bullet — don't call
   `ship_land`.)* **If the diff touches `plugins/*/bin|lib` or `check.sh`, `ship_land` REFUSES without
   a `da` finding ("<what the devil's-advocate attacked, or: clean>", exit 11, R78)** — step 2's pass is
   required there, not optional, and the note rides the commit as a `Devil-advocate:` trailer.
   Don't write "clean" unless one actually ran and found nothing. Call **`ship_land`** with `message`
   (the commit message text — the tool writes it to a temp file for you, no `-F <msgfile>` plumbing
   needed) and the same `gate` step 1 used. The rail re-runs the gate on the exact tree
   being shipped, stages everything, refuses staged credential shapes, commits, **ff-only** merges
   to the default branch, pushes, and prunes the shipped branch (`-d` only, local + remote). It
   never force-pushes, never deletes the default, and its merged-branch sweep is **list-only**.
   **On a nonzero exit the rail prints the specific problem AND its remedy** — read that line and act
   on it (gate-fail → fix + re-land; non-ff → rebase/curate then re-land, the retry path ships your
   existing commits; push-fail → the commit is safe locally, resolve the remote; nothing/refused →
   read + decide). Don't pre-guess the failure; the bail text is authoritative.
   - **After the push, land ENFORCES a CI watch (R74)** — a green local gate is *not* a green CI
     (gitleaks/shellcheck skip locally when absent; a shellcheck build can miss a lint CI catches).
     Land blocks until the run concludes, so **give this Bash call a long timeout** (the watch is
     bounded by `SHIP_CI_TIMEOUT`, default 5400s — a GIVE-UP threshold, deliberately far above what CI costs today, because too-low is paid on every ship and costs the guarantee silently. **That exceeds the max timeout of a single Bash call, so run the ship in the BACKGROUND and read its output when it finishes** — a foreground call will be cut off mid-watch and tell you nothing). **exit 10 = SHIPPED but CI RED** → the commit is
     already on the default, so **fix forward** (read `gh run view <id> --log-failed`, fix, land the
     fix), don't try to un-ship. `gh` absent / no run / timeout → land says so and exits 0 (unwatched,
     not failed). Opt out only when you must with `SHIP_CI_WATCH=0`.
   - **PR flow instead (the `pr` argument, or the owner asks mid-flow for review first):** skip
     `land`, push the branch, and open
     a PR with `gh` (structured body: one-line summary · changes grouped by area · requirement IDs
     · test plan + result); without `gh`, print the compare URL. **Name the full trade-off — `pr`
     leaves the rail, so it forgoes all four of `land`'s guarantees:** (1) the **gate re-run on the
     exact tree being shipped**, (2) the **staged-credential refusal** at the commit boundary,
     (3) the **ff-only merge**, and (4) the **enforced R74 CI watch** (CI runs on the PR and the
     merge is a later, separate act, so nothing here blocks on it). (1) and (2) are *safety*, not
     convenience: you are hand-committing without the rail, so **re-run the gate yourself and eyeball
     `git diff --staged` for credential shapes before you push.** Step 6's sweep doesn't apply either
     (nothing merged yet).
6. **Sweep merged branches (R35) — owner-confirmed.** `land` printed any *other* branches already
   merged into the default (list-only by design — deleting a teammate's branch needs a human yes).
   If the repo is yours alone, or the owner confirms the list, prune now by hand: `git branch -d`
   each (never `-D`), `git push origin --delete` for confirmed remote ones, `git fetch --prune`. (Or
   pass `pruneAll: true` to a future `ship_land` call to have the rail do it.) Never mass-delete remote
   branches silently.
7. **Confirm** in one plain line what shipped and what was cleaned up (branch / commit / PR URL +
   which branches were deleted), so the owner can install or review.

Never force-push or rewrite published history unless the owner explicitly asks.
