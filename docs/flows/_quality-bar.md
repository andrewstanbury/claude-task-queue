# Quality bar (global)

The **cross-cutting quality attributes** every flow is held to — the demoted, de-ceremonied `NFR.md`
(R62). Per-flow quality lives in each flow's **Quality bar** section; this is the shared floor that
constrains *all* of them. Each passes the filter *"would a `redesign` build differently if this
weren't true?"* — only owner-agreed attributes are here (not incidental implementation).

## The floor (a `redesign` must still meet all of these)
- **N1 · Token efficiency is the core lens** — minimal runtime-loaded surface; on-demand > injected;
  CLAUDE.md is the only auto-loaded doc. The steering injection is the one output with real token cost.
- **N2 · Generic / wide-audience** — no hardcoded language/framework/ecosystem allowlists; delegate
  recognition to the model, detect structure generically, hardcode only unavoidable invocation.
- **N3 · CLI-only, artifact-free** — the only human surface is the CLI + status line; no GUI/web/artifact.
- **N4 · Tiny enforced core** — code only for *block / inject / control-flow*; everything advisory is
  one steering doc (the R24/R28 split).
- **N5 · Autonomy on reversible, consent on consequential** — act freely on reversible work; gate the
  irreversible/binding behind a plain-language ask (the *recommendation-first* pattern + autopilot's line).
- **N6 · Native-first** — prefer Claude Code's native mechanisms; build custom only where native can't
  (the one owned exception is the task queue).
- **N7 · Prevention > detection** — favour blocking a bad outcome (a gate) over reporting it after.

## Explicitly NOT the bar (a redesign may change it freely)
Implementation tech (Bash + jq, zero build, files ≤300 lines) is **incidental**, not an agreed
quality attribute — a redesign may pick a different language/structure provided it still meets N1–N7,
reproduces the flows, and passes every `docs/INVARIANTS.md` check.

## Conflict resolution
P0 (N1–N4) outranks P1 (N5–N7); any collision with a safety invariant (`docs/INVARIANTS.md`) is
decided in favour of the invariant.
