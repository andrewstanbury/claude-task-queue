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

## Format

    - YYYY-MM-DD · <surface> · <what changed>
      could break: <what depends on it — the honest guess, not a certainty>

`surface` is free text naming where it happened (`aws`, `dns`, `stripe`, `oauth`, `k8s`,
`vendor-console`). The `could break:` line is optional but is the part that pays off later: it is
what turns "something changed" into "start here".

## Log

<!-- newest first; entries older than the window stay as history -->
