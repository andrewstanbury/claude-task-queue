#!/usr/bin/env bash
# The unified per-repo feature surface (R50): ONE place to see and flip every enforced-core
# capability, instead of the old scatter (env var here, flag file there). `features` (no arg)
# lists state; `features <name> on|off` flips one. secret/steering are per-repo feature
# flags (lib companion_feature_*); autopilot/ship keep their OWN flag files, so we reflect + DELEGATE
# them to autopilot.sh rather than hold a second copy of that state. Steering is DELIBERATELY not
# flag-per-clause — it's ignorable-by-nature already (R28); the one steering knob is inject on/off.
set -uo pipefail
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
BIN="$(cd "$(dirname "$SELF")" && pwd)"
# shellcheck source=../lib/companion.sh
. "$BIN/../lib/companion.sh"

root="$(companion_root "$PWD")"

# Resolve a feature's *effective* state for display: a global env override (CI escape hatch) wins
# over the per-repo flag, which wins over the default. Only secret has an env override.
eff() {
  case "$1" in
    secret)  [ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && { echo "off (env CLAUDE_COMPANION_SECSCAN=0)"; return; } ;;
  esac
  companion_feature_state "$1" "$root"
}

list() {
  echo "companion features — $root"
  printf '  %-10s %s\n' "secret"    "$(eff secret)    — block writes that commit a credential (irreversible; the one enforced gate)"
  printf '  %-10s %s\n' "steering"  "$(eff steering)    — inject the working agreement (STEERING.md) at session start"
  printf '  %-10s %s\n' "autopilot" "$(companion_autopilot_on "$root" && echo on || echo off)    — keep draining the queue autonomously (/companion:autopilot)"
  printf '  %-10s %s\n' "ship"      "$(companion_ship_on "$root" && echo on || echo off)    — auto-commit autopilot work to an autopilot/* branch"
  echo "flip: /companion:features <name> on|off   (env overrides are global; unset them to let a per-repo flag apply)"
}

name="${1:-}"; val="${2:-}"
case "$name" in
  ""|list|status) list ;;
  secret|steering)
    case "$val" in
      on|off) : ;;
      *) echo "usage: features $name on|off" >&2; exit 1 ;;
    esac
    if [ "$name" = secret ] && [ "$val" = off ]; then
      echo "⚠️  Disabling the SECRET GATE for $root. This is the one irreversible-harm guard — a committed"
      echo "    key can't be un-leaked. Leave it on unless you have a specific reason; re-enable with"
      echo "    'features secret on'. (Anchored vendor keys are what it blocks; false positives are ~0.)"
    fi
    companion_feature_set "$name" "$root" "$val" && echo "$name → $val for $root"
    ;;
  autopilot) exec "$BIN/autopilot.sh" "${val:-status}" ;;
  ship)      exec "$BIN/autopilot.sh" ship "${val:-status}" ;;
  *) echo "usage: features [list] | features <secret|steering|autopilot|ship> on|off" >&2; exit 1 ;;
esac
