# NFR — the quality-attribute contract (R54 contract, pillar b)

The **intentionally-agreed** non-functional requirements a ground-up `advise` regen (R54) must
meet. Only what the owner *actively picked* is here (R53 anti-laundering); each passes the filter
*"would advise build differently if this weren't true?"* Provenance: **inferred-from-ledger/memory,
owner-confirmed** 2026-07-17 (a best-guess candidate the owner actively selected).

Organized by **priority tier** (this doc's native axis — priority is what resolves NFR conflicts).
NFRs are deliberately **cross-cutting**: most constrain *every* UX path/pattern at once, so there's
no per-row spine link (adding "all paths" to each row would violate N1). The shared spine
(`docs/UX.md`) is referenced only where an NFR maps to a *specific* path — flagged with `↳`.

## P0 — foundational (changes what advise builds, fundamentally)

| # | NFR | How it constrains a regen | Source |
|---|---|---|---|
| N1 | **Token efficiency is the core lens** — minimal runtime-loaded surface; on-demand > injected; CLAUDE.md is the only auto-loaded doc | Keep injected surface minimal; resist new always-injected docs; prefer lazy/on-demand loading. The *steering* injection is the one output with real token cost. | R3, memory |
| N2 | **Generic / wide-audience — no hardcoded language/framework/ecosystem allowlists** | Delegate *recognition* to the model; detect *structure* generically; hardcode only unavoidable *invocation*. No baked-in ecosystem lists. | R9 |
| N3 | **CLI-only, artifact-free** — the only human surface is the CLI + status line | No GUI/web/artifact surfaces; all output through the terminal + status line. | memory |
| N4 | **Tiny enforced core; everything advisory is one steering doc** — code only for *block / inject / control-flow* | Preserve the R24/R28 split: don't turn advisory prose into hooks; don't fragment the steering doc; keep the enforced core minimal. | R24, R28 |

## P1 — shapes design

| # | NFR | How it constrains a regen | Source |
|---|---|---|---|
| N5 | **Autonomy on reversible, plain-language consent on consequential** (the line is reversibility + cost + data-safety) | Act freely on reversible work; gate the irreversible/binding behind a plain-language ask. `↳` UX: *recommendation-first* pattern + Path 3 (autopilot's consent line). | R14 |
| N6 | **Native-first — a hook/custom mechanism must earn its place** | Prefer Claude Code's native mechanisms; build custom only where native can't do the job (the one owned exception is the task queue, R8). | R10 |
| N7 | **Prevention > detection** | Favor blocking a bad outcome (a gate) over reporting it after the fact (a warning). | memory, feature-eval |

## Explicitly NOT contract (disposable / incidental — a regen may change it)

- **Implementation tech: Bash + jq, zero build, files ≤300 lines.** The owner **deliberately did
  not** make this contract (2026-07-17) — it's incidental implementation, not an agreed quality
  attribute. A regen is **free to choose a different language/structure** provided it still meets
  N1–N7, reproduces the UX (`docs/UX.md`), and passes every invariant check (`docs/INVARIANTS.md`).
  *(Note: N1 token-efficiency + N3 CLI-only still bound the choice heavily in practice.)*

---

## Conflict-resolution (when NFRs collide)

Not yet elicited — a future pass should record priority/tradeoffs (e.g. token-efficiency vs
completeness; native-first vs control). Until then, P0 outranks P1, and any collision with a
**safety invariant** (`docs/INVARIANTS.md`) is decided in favour of the invariant.
