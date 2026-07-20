# Conventions (patterns)

The recurring conventions the flows are built from — defined **once** here, referenced **by name**
from each flow that uses one (a pattern is exercised at many points; restating it would drift).
Each carries its `[E]`/`[S]` kind and, where one exists, a resolving test.

## recommendation-first `[S]`
Anything decision-shaped arrives as a recommendation-first pick-from-CLI menu (recommended option
marked), and every reply closes with a one-line brutal-honest verdict. — eyeball only 👁

## queue-one-at-a-time `[S]/[E]`
Requests become `tq` tasks, smallest-blast-first, each with a done-when, worked one at a time with a
breadcrumb. The companion owns its store; deliberately not Claude's native tasks. The `tq` CLI —
`add · doing · note · done · cancel · list · report` — **reprints the queue on every change**; it's
the spine the user watches.
- [E] `tq: done-when — --done on add + the done-when subcommand STORE it` ✅
- [E] `tq: add/doing/done write the companion store + stamp the repo root` ✅

## wireframe-first `[S]`
A visual change gets a wireframe/ASCII sketch agreed before code. — eyeball only 👁

## clean-as-you-go `[S]`
Weigh blast radius, subtract, YAGNI; verify by exercising, not asserting; recap in one line. — eyeball only 👁

## offer-not-act nudges `[S]`
Context nudges are **offers, not actions**: debt → task · big blast → split · repetitive drain →
autopilot · finished chunk → ship-it. — eyeball only 👁

## contract-preserving rebuild `[S]`
`redesign` reproduces the logged flow + quality-bar contract, gated on the safety checks, applied on
a branch — the experience is preserved, the implementation may change. — eyeball only 👁

## guardrails default-on `[E]`
Safety features (secret gate, status-line health, ship-mode's never-main) are on by default and
opt-out only; disabling the secret gate warns loudly.
- [E] `secret gate: blocks a real AWS key (exit 2)` ✅
- [E] `status line: 🛡✗ when the secret gate is disabled` ✅

## living-contract `[E]/[S]`
The flow + quality-attribute contract stays accurate continuously (R58): every prompt is
**captured** (hook, write-only, zero injection), a change to what the user sees/does or a quality
attribute **moves the flow page first** (steering reflex — the continuous twin of
`/companion:document`), and a **drift backstop** (`check.sh`/`ship-it`) surfaces behaviour that
outran the contract. `/companion:cover` is its test scaffolding arm.
- [E] `capture: banks the prompt, injects nothing` ✅
- [E] `contract-drift: warns when behaviour changed without a contract doc` ✅
