#!/usr/bin/env bash
# tq-ask — the model's CLI for the open-decisions ledger. Call it when you pose a
# decision the user must answer, so it can't be lost to type-ahead, and resolve it
# when answered. Keyed by the current repo (so the SessionStart/UserPromptSubmit/
# Notification hooks surface the same ledger). Run from inside the project.
#
#   tq-ask.sh open "<question>" "<recommended option>"   # log a pending decision
#   tq-ask.sh resolve <id|all>                           # clear when answered
#   tq-ask.sh list                                       # show open decisions
#
# Read/written only under the plugin's state dir; never touches your project.

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/decisions.sh
. "$PLUGIN_DIR/lib/decisions.sh"
set +e   # tasks.sh enables errexit; this CLI manages its own exit codes

root="$(tq_root_for_cwd "$PWD")"
cmd="${1:-list}"

case "$cmd" in
  open)
    [ -n "${2:-}" ] || { echo "usage: tq-ask.sh open \"<question>\" \"<recommended>\"" >&2; exit 2; }
    id="$(tq_decision_add "$root" "$2" "${3:-}")"
    printf 'Logged open decision #%s — it will be re-surfaced each prompt until you run: tq-ask.sh resolve %s\n' "$id" "$id"
    ;;
  resolve)
    [ -n "${2:-}" ] || { echo "usage: tq-ask.sh resolve <id|all>" >&2; exit 2; }
    tq_decision_resolve "$root" "$2"
    printf 'Resolved decision %s. Open now: %s\n' "$2" "$(tq_decision_count "$root")"
    ;;
  list|"")
    rows="$(tq_decision_list "$root" 2>/dev/null || true)"
    if [ -z "$rows" ]; then printf 'No open decisions for %s\n' "$root"; exit 0; fi
    printf 'Open decisions for %s:\n' "$root"
    printf '%s\n' "$rows" | while IFS=$'\t' read -r id q rec; do
      printf '  #%s  %s%s\n' "$id" "$q" "$( [ -n "$rec" ] && printf '  (recommended: %s)' "$rec" )"
    done
    ;;
  *)
    echo "usage: tq-ask.sh {open \"<q>\" \"<rec>\" | resolve <id|all> | list}" >&2; exit 2 ;;
esac
