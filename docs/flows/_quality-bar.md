# quality-bar — global floor (per-flow bars in each flow spec)

Filter: "would a redesign build differently if this weren't true?" — owner-agreed only.

floor (a redesign must meet ALL):
- N1 token efficiency is the core lens — minimal runtime-loaded surface; on-demand > injected; CLAUDE.md is the only auto-loaded doc; the steering injection is the one real token cost
- N2 generic/wide-audience — no language/framework/ecosystem allowlists; model recognizes, structure detected generically, only invocation hardcoded
- N3 CLI-only, artifact-free — human surface = CLI + status line
- N4 tiny enforced core — code only for block/inject/control-flow; all advisory = one steering doc [R24 R28]
- N5 autonomy on reversible, consent on consequential
- N6 native-first — custom only where native can't (owned exception: the task queue)
- N7 prevention > detection

NOT the bar (redesign may change freely): implementation tech (bash+jq, zero build, ≤300-line files) — incidental, provided N1–N7 + flows + INVARIANTS checks hold.

conflicts: P0 (N1–N4) > P1 (N5–N7); any collision with a safety invariant → invariant wins.
