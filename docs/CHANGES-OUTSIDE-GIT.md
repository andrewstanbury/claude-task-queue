# Changes outside git

**Only what `git log` cannot show you.** Infrastructure, cloud consoles, DNS, provider and OAuth
settings, credential rotations, dashboard toggles, anything changed by hand on a running system.
In-repo changes belong in git and must NOT be duplicated here — a file that restates git gets
skimmed, then ignored, then goes wrong.

**Why this file exists.** On another project, days went into chasing an Apple login configuration
that had already been confirmed twice. The actual cause was a recent AWS change — infrastructure an
agent had built incorrectly, and trusted precisely because it was ours. Nothing in the repo
recorded it, so clearing state erased the only place that knowledge lived.

**How it is used.** `session-start.sh` injects entries from the last 14 days
(`CLAUDE_COMPANION_CHANGE_WINDOW_DAYS`) into every session, so they arrive *unasked* after a
context clear or a compaction. Older entries stay here as history and cost nothing. A repo with no
recent out-of-band change injects nothing at all.

**Write an entry the moment the change happens**, not later — the knowledge is never cheaper than
at that moment. Anyone can append: agent or owner.

## 2026-08-12 — companion marketplace repointed from GitHub to this working tree (owner-decided)

`~/.claude/plugins/known_marketplaces.json` `andrewstanbury.source` changed
`{github: andrewstanbury/claude-task-queue}` -> `{directory: /home/deck/Documents/claude-task-queue}`,
then `claude plugin update companion@andrewstanbury` moved the install 3.82.0 -> 3.83.0.

**Why:** the plugin installed FROM GITHUB and the install record pinned `gitCommitSha 00cce40`, which
is still local HEAD — R109/R110/R111/R112/R87b are uncommitted, so a plain reinstall would have
fetched the identical 3.82.0, reported success, and changed nothing.

**This is a LOCAL OVERRIDE, and it is a footgun while it stands.** Every session on this machine now
resolves companion from the working tree, including mid-edit or broken states — the tree is no
longer a safe scratch space. **Revert with** `claude plugin marketplace remove andrewstanbury` then
`claude plugin marketplace add andrewstanbury/claude-task-queue`; config backed up at
`scratchpad/plugin-config-backup/` for the session. Once the work ships to main, repoint to GitHub —
the override should not outlive the reason for it.

## Format

    - YYYY-MM-DD · <surface> · <what changed>
      could break: <what depends on it — the honest guess, not a certainty>

`surface` is free text naming where it happened (`aws`, `dns`, `stripe`, `oauth`, `k8s`,
`vendor-console`). The `could break:` line is optional but is the part that pays off later: it is
what turns "something changed" into "start here".

## Log

<!-- newest first; entries older than the window stay as history -->
