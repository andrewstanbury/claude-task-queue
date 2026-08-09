#!/usr/bin/env bash
# resume — the on-demand, TRIAGE-AND-PULL twin of session-start.sh (reinstated R100/Pass 6,
# docs/adr/README.md R105). Content generation (STEERING, LESSONS, version-lag warning, R93
# out-of-band changes, rework, carried tasks) is shared with session-start.sh via
# lib/resume-report.sh — this script's own job is the triage half session-start.sh deliberately
# does NOT do: call it yourself, any time mid-session, to pull the same content on demand.
#
# Resume is a TRIAGE handoff (R39): it first turns autopilot OFF (announced when it was on) so the
# resumed decisions come back to the OWNER, not to autopilot — ask-guard.sh (reinstated) already
# blocks a question while autopilot is armed, but the triage-to-owner intent here is stronger and
# deliberate: a resume mid-drain is exactly the moment a parked ❓ should get a human, not a nudge.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "resume: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"
# shellcheck source=../lib/resume-report.sh
. "$PLUGIN_DIR/lib/resume-report.sh"

root="$(companion_root "$PWD")"
out=""

# Capture armed-ness BEFORE clearing it below — both the disarm announcement and whether the mode
# prose rides (inside companion_resume_report) depend on the state at CALL time, not after this
# script has already changed it.
was_armed=0
companion_autopilot_on "$root" && was_armed=1

# Disable autopilot first so the resumed pile is triaged, not autopiloted. Loud when it was on
# (don't silently clobber a persisted intent); quiet no-op when already off. session-start.sh
# (R100/Pass 6) deliberately does NOT do this — an automatic session start must never silently
# disarm a persisted "keep draining" intent; only an owner-invoked resume triages it away.
if [ "$was_armed" -eq 1 ]; then
  companion_autopilot_clear "$root"
  out="autopilot was ON — turned it OFF so the resumed pile comes back to you, not autopilot. Re-arm with /companion:autopilot on when you want to drain again."$'\n'
fi

steering_block="$(companion_resume_steering "$root" "$PLUGIN_DIR" "$was_armed")"
[ -n "$steering_block" ] && out="$out"$'\n\n'"$steering_block"
out="$out$(companion_resume_report "$root" "$PLUGIN_DIR")"

printf '%s\n' "$out"
