---
description: Ship finished work — verify, commit, push, and merge to the default branch
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
3. **Review + commit.** Show `git status` and a short `git diff --stat`. Commit the work with a
   clear message (what changed + why). If a version/marketplace manifest is part of this change,
   make sure it's bumped.
4. **Push + integrate → the default branch.** Land the verified work on the default branch:
   - On a **feature / `autopilot/*` branch** with `gh`: merge to the default branch (fast-forward
     or squash) — or open a PR if the owner wants review first.
   - Without `gh`: push the branch and print the compare/PR URL to open manually.
   - Already on the **default branch**: push it.
5. **Clean up merged branches (R35) — only after the merge SUCCEEDS.**
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
6. **Confirm** in one plain line what shipped and what was cleaned up (branch / commit / PR URL +
   which branches were deleted), so the owner can install or review.

Never force-push or rewrite published history unless the owner explicitly asks.
