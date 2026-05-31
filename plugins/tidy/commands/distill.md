---
description: Whole-project subtractive prune pass — surface weight, then cut cruft
argument-hint: "[path]"
allowed-tools: Bash, Read, Grep, Glob, Edit
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tidy-distill.sh" "$ARGUMENTS"

The report above is **read-only facts** — file weight, the heaviest and
over-budget files, cruft markers, and junk artefacts. Now run the **subtractive
pass**, which is your judgment to make (the script can't):

1. **Open the heaviest / over-budget files** and hunt for what can leave:
   - dead code (unreferenced functions, types, exports, files),
   - duplication and near-duplication (the same logic in two places),
   - things a recent change made redundant ("X supersedes Y").
   Prefer **reuse over re-creation** and the **smaller surface** — propose
   deletions and merges, not just reorganisation.
2. **Reconcile docs against code:** README / ROADMAP / project MAP / examples
   that reference moved or removed files, stale instructions, drifted snippets.
3. **Delete the junk artefacts** if they truly shouldn't be tracked.

Rules of engagement:
- **Delete provably-unused code yourself** — tests are the guardrail (characterize
  first if needed, then confirm the suite stays green). The owner may be
  non-technical, so don't ask them to validate a technical removal.
- For a **genuinely ambiguous** removal (you can't tell if it's still needed), ask
  in **plain language** what the thing is for — not with a technical diff.
- Keep each change **scoped and test-covered**; run the project's checks after.
- Success = **net complexity down**, not files merely shuffled.

If `$ARGUMENTS` named a subpath, focus the pass there; otherwise cover the repo,
starting with the heaviest files the report listed.
