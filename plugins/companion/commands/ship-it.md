---
description: Ship finished work — verify, sync the contract docs, commit, push, and merge to the default branch
---

Take verified work from the working tree to shipped. Pushing and merging are externally
visible, so be careful and confirm the irreversible steps.

1. **Verify FIRST.** Run the project's own gate — its test/check script (`./check.sh`,
   `make test`, `npm test`, whatever the project uses). If it fails, **STOP** and report; do
   not ship broken work.
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
3. **Sync the contract + docs before you commit (R57).** A ship that changes what the user *sees or
   does* must not leave the recorded contract a commit behind. Before committing:
   - **Name the contract impact.** Read the diff and identify which R54 pillar it touches — **UX**
     (a command / flow / output the user sees), **NFR** (a quality attribute), or an **invariant**
     (a must-hold). Pull the *relevant logged design* for what changed — the affected
     `docs/flows/<flow>.md` page (Happy path + Tests + Quality bar), the invariant — and fold it into
     the commit body (and the PR body), **called out loudest for UX changes** so a reviewer sees the
     *experience* delta, not just the code.
   - **Propose the flow-page update, recommendation-first — the contract stays owner-governed.** If the
     change alters UX (a command added / removed / renamed, a flow or output changed), **draft the
     `docs/flows/<flow>.md` edit** — the Happy-path steps to add / change / remove and the Tests +
     Changes lines, keeping each test line's `[E]`/`[S]` kind — and present it recommendation-first
     for the owner to confirm or adjust (the same `AskUserQuestion` shape; under autopilot, park it as
     a `❓` carrying the drafted edit). On approval, **stage the flow-page edit *with* the code** so
     they land in one commit — the contract never drifts a commit behind. Do **not** silently rewrite
     the contract: the R61 anti-drift gate + the drift-guard stay the backstop (a broken Tests ref
     fails CI), and the owner still governs what the experience *is* (R54). Same for a genuine quality
     or invariant change — propose the `docs/flows/_quality-bar.md` / `docs/INVARIANTS.md` edit.
   - **Snapshot the queue so it travels (R60).** Run `"${CLAUDE_PLUGIN_ROOT}/bin/tq" export` to write
     the repo's still-open tasks to `.companion/queue.json`, and stage it with the commit — the
     backlog then rides along with the ship, so the work can be resumed on another machine (`git pull`
     + `/companion:resume`). Skip only if the repo keeps `.companion/` untracked on purpose.
   - **Refresh the README docs index.** Ensure the `README` has a **Documentation** section that
     links each `docs/*.md` (the contract + the map), and update it if this ship added / removed /
     renamed a doc — so a GitHub reviewer reaches the docs in one click. Keep it a plain link list;
     don't copy the docs' content into the README (that just makes a second thing to drift).

4. **Review + commit — write it to be *read* (R40).** Show `git status` and a short
   `git diff --stat`. Then **right-size first:** if the diff mixes unrelated concerns or is large,
   say so in one line and offer to split it into separate logical commits (or stacked PRs) — a
   reviewer, human or not, reads one concern at a time. Commit each logical unit with a
   **review-optimized message**, not a bare one-liner:
   - **Subject** — imperative, ≤~72 chars, naming *what* changed (and this project's version +
     the requirement IDs it touches when it has them). *Generic (R9): use the project's own
     convention — Conventional Commits, a ticket prefix, whatever it uses — don't impose one.*
   - **Body** — **What changed** (the concrete edits), **Why** (the outcome, not the mechanics),
     **Requirements/issues** it touches or reverses (cite the IDs — a 🔒 needs explicit sign-off),
     **Tasks** it closes (the `tq`/tracker items), and the **Test result** (`check.sh` green, N tests).
   - This makes even a single squashed commit self-documenting. If a version/marketplace manifest is
     part of the change, make sure it's bumped.
5. **Push + integrate → the default branch.** Land the verified work on the default branch:
   - On a **feature / `autopilot/*` branch** with `gh`: **first curate the history for review (R40,
     reshapes R34's squash-on-ship).** An `autopilot/*` branch is a string of per-turn
     `autopilot: checkpoint` commits (WIP included) — don't merge that raw, and don't flatten it to
     one opaque squash either. Reshape it into **one commit per logical unit** (typically per `tq`
     task): `git reset --soft "$(git merge-base HEAD <default>)"` to uncommit back to the branch
     point with all changes staged, then re-commit in logical groups (`git add -p` / by path),
     each with a step-3 message. `rebase -i` is unavailable in this environment — the soft-reset is
     the equivalent. **Fallback:** if the changes are too entangled to separate cleanly, make *one*
     commit with a full step-3 message (a good message beats a bad split). Then merge to the default
     (fast-forward preferred so the curated commits land as-is) — or open a PR if the owner wants
     review first, giving it a **structured body** (one-line summary · changes grouped by area ·
     requirement IDs touched · test plan + result · how to verify), the same content as the commits.
   - Without `gh`: push the branch and print the compare/PR URL to open manually.
   - Already on the **default branch**: push it (curation/PR steps don't apply — commit is already
     shaped in step 3).
6. **Clean up merged branches (R35) — only after the merge SUCCEEDS.**
   - Delete the branch you just shipped: local `git branch -d <branch>` (lowercase — it **refuses**
     an unmerged branch, so no work is ever lost) and, if a remote copy exists,
     `git push origin --delete <branch>`.
   - Prune other branches **already merged into the default**: `git branch -d` each of
     `git branch --merged <default>` except the default and the current branch, then `git fetch
     --prune` to drop stale remote-tracking refs.
   - **Guardrails:** never `-D` / force-delete; never delete the default branch; and if the repo is
     **shared** (branches on the remote you didn't create), *list the merged remote branches and
     confirm* before deleting them — a teammate's merged branch may still be wanted. Never
     mass-delete remote branches silently.
7. **Confirm** in one plain line what shipped and what was cleaned up (branch / commit / PR URL +
   which branches were deleted), so the owner can install or review.

Never force-push or rewrite published history unless the owner explicitly asks.
