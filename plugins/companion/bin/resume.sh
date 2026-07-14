#!/usr/bin/env bash
# Manual resume — re-surface THIS repo's still-open tasks from earlier sessions, on demand
# (the SessionStart hook does this automatically each new session; this is the "do it now"
# twin for when you want to pull them back mid-session). Prints the open tasks; the model
# reinstates them. Read-only on the store, best-effort.
#
# Resume is a TRIAGE handoff: it first turns autopilot OFF (announced when it was on)
# so the resumed decisions come back to the OWNER, not to autopilot — while autopilot is on
# the ask-guard blocks questions, so a parked ❓ that resurfaced would get autopiloted, not
# reviewed. Clearing the flag here also arms the parked-pile review that resume.md runs.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "resume: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

root="$(companion_root "$PWD")"

# A — disable autopilot first so the resumed pile is triaged, not autopiloted. Loud when it
# was on (don't silently clobber a persisted intent); quiet no-op when already off.
if companion_autopilot_on "$root"; then
  companion_autopilot_clear "$root"
  printf 'autopilot was ON — turned it OFF so the resumed pile comes back to you, not autopilot. Re-arm with /companion:autopilot on when you want to drain again.\n'
fi

carry="$(companion_open_tasks "$root")"
if [ -n "$carry" ]; then
  printf 'Open tasks carried over for %s — reinstate them (they are already in the queue):\n%s\n' "$root" "$carry"
else
  printf 'No carried-over open tasks for %s.\n' "$root"
fi
