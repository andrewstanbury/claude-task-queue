---
description: Ship finished work — verify, sync the contract docs, commit, push, and merge to the default branch
---

Take verified work from the working tree to shipped. Pushing and merging are externally
visible, so be careful and confirm the irreversible steps.

**The mechanical spine runs on the rail (R71):** `"${CLAUDE_PLUGIN_ROOT}/bin/ship.sh"` executes
the deterministic steps in two calls — `preflight` before your judgment, `land` after it — so
you spend turns on judgment, not on running git one command at a time. **The rail bails loudly
instead of improvising**; each nonzero exit hands a specific problem back to you (codes below).
Judgment stays yours: the case, the devil's-advocate, the contract impact, the flow-page
proposal, the commit message, the history curation.

1. **Preflight — Verify FIRST, one call.** Run `"${CLAUDE_PLUGIN_ROOT}/bin/ship.sh" preflight`
   (if the repo has no `./check.sh` / `.companion/check.sh`, append its gate as trailing args —
   `preflight make test`, `preflight npm test`, whatever it uses; recognizing that is your job, R9.
   Remember the same command — step 5's `land` needs it as `--gate <cmd…>`). This runs the
   gate, the contract-drift backstop (R58 — read its output), `tq export` (R60 — the queue
   snapshot rides the ship), and prints the branch/upstream summary + `git status` + diff stat
   you'd otherwise gather by hand. **Gate failed (exit 4) → STOP and report; do not ship broken
   work. No gate found (exit 3) → supply one or stop.**
2. **State the case before you commit (the challenge slot, R30·d6).** In one short block, name:
   **risks** (what could this break, or what would you regret?), **what it changes** (behavior /
   interface / requirements — cite the R-IDs it touches or would reverse), and **why it's still
   worth it.** A real answer only exists if you actually weighed the change — that's the point;
   don't skip it.
   - **If the change is consequential** (irreversible, externally binding, architecturally
     significant, or high blast-radius): spawn a **devil's-advocate sub-agent** — hand it the diff
     + the goal and ask it to find every reason *not* to ship, independently. Surface its
     objections. A rubber-stamp from a context that didn't build the change is worth little; an
     objection from one is worth a lot — if it lands a real one, fix or reconsider before you push.
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
5. **Land — one call.** Run `"${CLAUDE_PLUGIN_ROOT}/bin/ship.sh" land -F <msgfile>` (if the repo
   has no `./check.sh`/`.companion/check.sh`, append `--gate <cmd…>` **last** — it slurps the rest
   of the line as the gate command, so a multi-word gate like `--gate make test` works, matching
   the positional `preflight <cmd…>` form). The rail re-runs the gate on the exact tree
   being shipped, stages everything, refuses staged credential shapes, commits, **ff-only** merges
   to the default branch, pushes, and prunes the shipped branch (`-d` only, local + remote). It
   never force-pushes, never deletes the default, and its merged-branch sweep is **list-only**.
   **On a nonzero exit the rail prints the specific problem AND its remedy** — read that line and act
   on it (gate-fail → fix + re-land; non-ff → rebase/curate then re-land, the retry path ships your
   existing commits; push-fail → the commit is safe locally, resolve the remote; nothing/refused →
   read + decide). Don't pre-guess the failure; the bail text is authoritative.
   - **PR flow instead:** if the owner wants review first, skip `land`, push the branch, and open
     a PR with `gh` (structured body: one-line summary · changes grouped by area · requirement IDs
     · test plan + result); without `gh`, print the compare URL.
6. **Sweep merged branches (R35) — owner-confirmed.** `land` printed any *other* branches already
   merged into the default (list-only by design — deleting a teammate's branch needs a human yes).
   If the repo is yours alone, or the owner confirms the list, prune now by hand: `git branch -d`
   each (never `-D`), `git push origin --delete` for confirmed remote ones, `git fetch --prune`. (Or
   pass `--prune-all` to a future `land` call to have the rail do it.) Never mass-delete remote
   branches silently.
7. **Confirm** in one plain line what shipped and what was cleaned up (branch / commit / PR URL +
   which branches were deleted), so the owner can install or review.

Never force-push or rewrite published history unless the owner explicitly asks.
