#!/usr/bin/env bash
# Manual resume — re-surface THIS repo's still-open tasks from earlier sessions, on demand
# (the SessionStart hook does this automatically each new session; this is the "do it now"
# twin for when you want to pull them back mid-session). Prints the open tasks; the model
# reinstates them. Read-only, best-effort.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "resume: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

root="$(companion_root "$PWD")"
carry="$(companion_open_tasks "$root")"
if [ -n "$carry" ]; then
  printf 'Open tasks carried over for %s — reinstate them (they are already in the queue):\n%s\n' "$root" "$carry"
else
  printf 'No carried-over open tasks for %s.\n' "$root"
fi
