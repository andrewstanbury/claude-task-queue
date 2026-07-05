---
description: Ship completed work — verify, then commit, push, PR, squash-merge to main, delete the branch
allowed-tools: Bash
---

You are shipping a completed unit of work to the default branch. Do this IN ORDER —
the safety of the merge depends on step 1:

1. **Verify first — this is the gate.** Run this project's checks and confirm they
   PASS: `./check.sh` if it exists, else the project's tests/build (use the `/verify`
   skill if unsure how). If anything is red, STOP and fix or report — never ship a
   failing tree. This is the only thing standing between an unattended session and a
   bad merge, so do not skip it.
2. **Confirm the working tree holds only the intended change** (`git status`) — don't
   sweep unrelated edits into the release.
3. **Ship it.** Run:
   `bash "${CLAUDE_PLUGIN_ROOT}/bin/tq-ship.sh" --title "<concise imperative summary>" --body "<one-paragraph why>"`
   It branches if you're on the default branch, commits any pending work, pushes, opens
   a PR, squash-merges into the default branch, deletes the branch, and syncs. If the
   remote blocks the merge (branch protection / required checks), it stops and leaves
   the PR open — relay that; don't force it.
4. Relay in one plain sentence what shipped (the PR number + that it merged), or what
   blocked it.

**Autopilot:** shipping a verified, completed unit is an ACTION, not a decision, so it
is safe to run unattended — but ONLY once step 1 is green. Don't park it; this is the
one sanctioned push/merge. (Any important design/direction decision inside the work
would already have parked and blocked the task from reaching "done", so what ships is
by definition already decided and verified.) Ship at a coherent boundary — a finished
unit — not after every micro-task.
