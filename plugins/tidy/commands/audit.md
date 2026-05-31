---
description: Read-only whole-project audit against the companion's standards
argument-hint: "[path]"
allowed-tools: Bash, Read, Grep, Glob
---

! "${CLAUDE_PLUGIN_ROOT}/bin/tidy-distill.sh" "$ARGUMENTS"

The weight report above is deterministic facts (file weight, heaviest/over-budget
files, cruft markers, junk). The companion's per-touch and on-stop checks only
fire when you *edit* or *finish* — an audit edits nothing — so run them here
yourself. **Audit this project read-only and produce a prioritized, proportional
report.** Cover:

1. **Correctness & verification** — run the project's own tests (`npm test` /
   `go test ./...` / `pytest` / `make test`, or `CLAUDE_TIDY_TEST_CMD`) and its
   configured linters (eslint incl. jsx-a11y, golangci-lint, stylelint, ruff, …);
   report failures and findings. **If there are no tests at all, that's the top
   risk** — call it out first.
2. **Maintainability** — dead code, duplication, and over-budget files from the
   report: the subtract-as-you-add opportunities. Is the design right-sized, or
   over-engineered for what the product needs?
3. **Project knowledge (proportional)** — does the project document what its
   complexity *warrants*: a project map, a roadmap/what's-next, decisions
   (DECISIONS.md/ADRs), stack notes, quality attributes (QUALITY.md)? **Don't
   demand all of these from a small repo** — flag only the genuinely-missing
   baseline (map + what's-next), or, for a web project, missing Lighthouse-aligned
   quality attributes (CWV, a11y, SEO, print/responsive, progressive enhancement).
4. **Currency & security** — outdated or deprecated dependencies (read the
   manifests); for web, accessibility/performance/best-practice gaps.
5. **Naming & clarity** — does the code speak the owner's domain language, or
   hide behind generic tech abstractions?

Rules of engagement:
- **Read-only.** Do not change code during the audit. Run the project's checks
  bounded (skip anything that would take very long, and say you skipped it).
- **Proportional.** Weight findings by impact; don't drown a small project in
  nits. A 200-line app and a 200k-line system get different bars.
- **Plain language.** The owner may be non-technical — explain each finding and
  its risk in plain terms, grouped into **Must fix** vs **Nice to have**.
- End with a short, prioritized action list, and **offer to fix the top items**
  (those fixes then go through format/lint/test on touch and the verification
  floor — nothing lands until the suite is green).
