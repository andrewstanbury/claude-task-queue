# quality-bar — global floor (per-flow bars in each flow spec)

Filter: "would a redesign build differently if this weren't true?" — owner-agreed only.

Every attribute names HOW it is checked (R118). `reviewed at ship — <question>` is a first-class
answer, not a placeholder: most quality attributes are judgment, and a fake mechanical gate is worse
than an honest human one because it reads as coverage. What the check enforces is that the pairing
EXISTS — a floor, not a proof.

floor (a redesign must meet ALL):
- N1 token efficiency is the core lens — minimal runtime-loaded surface; on-demand > injected; CLAUDE.md is the only auto-loaded doc; the steering injection is the one real token cost → validated by: `dev/token-budget.sh` in check.sh — STEERING core ≤8500B and command descriptions ≤140B, measured every run
- N2 generic/wide-audience — no language/framework/ecosystem allowlists; model recognizes, structure detected generically, only invocation hardcoded → validated by: `dev/command-lint.sh` portability floor (every command names an MCP tool or bin/ script) + reviewed at ship — "does this hardcode a language, framework or ecosystem allowlist, or detect structure generically?"
- N3 CLI-only, artifact-free — human surface = CLI + status line → validated by: reviewed at ship — "does this add a human surface outside the CLI and status line, or a file the owner has to keep?"
- N4 tiny enforced core — code only for block/inject/control-flow; all advisory = one steering doc [R24 R28] → validated by: `dev/size-lint.sh` (≤300 lines, decompose when it fires) + `dev/hook-budget.sh` (hook cost MEASURED against store size and branch count, 1500ms stall cap)
- N5 autonomy on reversible, consent on consequential → validated by: `contract-guard.sh` refuses requirement REVERSALS, `ask-guard.sh`+`ask-close.sh` park every question until positively answered, and ship's feature-class gate refuses the default branch — each with bats cases and declared mutations
- N6 native-first — custom only where native can't (owned exception: the task queue) → validated by: reviewed at ship — "could a native Claude Code or MCP mechanism do this, and if not, why not?"
- N7 prevention > detection → validated by: reviewed at ship — "does this stop the failure happening, or only report it afterwards?"

NOT the bar (redesign may change freely): implementation tech (bash+jq, zero build, ≤300-line files) — incidental, provided N1–N7 + flows + INVARIANTS checks hold.

conflicts: P0 (N1–N4) > P1 (N5–N7); any collision with a safety invariant → invariant wins.

HONEST TALLY (2026-08-23, the first time anyone counted): three of seven carry a mechanical gate
(N1, N4, N5); N2 is half-mechanical; N3, N6 and N7 are judgment only. That is not a defect to fix by
inventing gates — "native-first" and "prevention > detection" are not mechanically decidable — but
it IS the thing worth knowing before a publish, and it was invisible until the pairing was written
down.
