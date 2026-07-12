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
4. **Push + integrate.**
   - On a **feature branch** with `gh` available: open a PR, or — if the owner wants it landed —
     merge to the default branch (fast-forward or squash) and delete the branch.
   - Without `gh`: push the branch and print the compare/PR URL to open manually.
   - Already on the **default branch**: push it.
5. **Confirm** in one plain line what shipped and where (branch / commit / PR URL), so the owner
   can install or review.

Never force-push or rewrite published history unless the owner explicitly asks.
