---
description: Checkpoint mid-flight work — tree + queue — to a pushed branch for another machine (no gate; gate fires at ship)
---

Hand the current state of this machine to another one, using git as the transport (R72). This is
a **checkpoint, not a ship**: the project gate is deliberately not run (a red tree mid-work is
normal), and nothing lands on the default branch.

1. Run `"${CLAUDE_PLUGIN_ROOT}/bin/ship.sh" handoff`. One call: `tq export` (the queue rides the
   commit, R60) → stage everything → **refuse staged credential shapes** (it pushes) → commit —
   on the default branch the WIP moves to a fresh `wip/<stamp>` branch (WIP never lands on
   default); on a feature branch it commits in place → `push -u`.
2. Handle its bails: **exit 6** nothing to hand off (clean tree, empty queue — say so, done) ·
   **exit 8** no remote / push failed (the checkpoint is safe locally — resolve the remote, push)
   · **exit 9** a credential shape is staged (unstage/redact it first — never hand off a secret).
3. Relay its final lines to the owner in one line: the branch that was pushed, and the pickup —
   on the other machine `git fetch && git checkout <branch> && /companion:resume` (imports the
   queue, classes + breadcrumbs intact).

**Two honest limits (name them if relevant).** (a) handoff runs **no gate** and stages the whole
tree (`git add -A`) — the only content guard is the standard anchored-credential backstop, which
is narrow; a scratch `.env`, an unheadered key, or a generic bearer token in an untracked file
**will** be committed and pushed to the `wip/*` branch (throwaway, but externally visible). Glance
at `git status` first if the tree is messy. (b) On the default branch it leaves you **on the new
`wip/*` branch**, not back on the default — `git checkout <default>` to return.

When the work later finishes (either machine): `/companion:ship-it` — `land` ships the handoff
branch like any feature branch (curate the `wip:` checkpoint into a real message first, step 4
there).
