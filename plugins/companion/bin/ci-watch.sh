#!/usr/bin/env bash
# ci-watch — watch the CI run for a commit to conclusion (R74). Extracted from `ship.sh`, which had
# reached its 300-line cap; `ship.sh land` calls this after a successful push.
#
#   ci-watch.sh <sha>
#
# Exits:  0  GREEN, or genuinely no CI to watch (no `gh`, no run ever registered, watch opted out)
#        10  CI concluded RED — the commit is already on the default branch, so FIX FORWARD
#        12  a run was in flight and the watch gave up on it — SHIPPED but UNWATCHED (R74 amended)
#
# Why 12 exists: the timeout used to return 0 with a "not failed" line, so a watch that gave up read
# exactly like a watch that passed. That is not hypothetical — adding a ~9min CI job put the run
# duration either side of the 300s default, and two ships reported "not failed" while one of them
# was red on macOS. `gh` absent or no run appearing still exits 0 (there is genuinely nothing to
# watch); abandoning a run that EXISTS is a different fact and now has its own code.
#
# Opt out with SHIP_CI_WATCH=0; tune SHIP_CI_APPEAR / SHIP_CI_POLL / SHIP_CI_TIMEOUT (seconds).
set -uo pipefail

sha="${1:-}"
[ -n "$sha" ] || { echo "usage: ci-watch.sh <sha>" >&2; exit 2; }
short="$(git rev-parse --short "$sha" 2>/dev/null || printf '%s' "$sha")"

case "${SHIP_CI_WATCH:-1}" in 0) printf '== ship.sh: CI watch off (SHIP_CI_WATCH=0)\n'; exit 0 ;; esac
command -v gh >/dev/null 2>&1 || {
  printf '== ship.sh: gh not found — CI UNWATCHED (a local PASS is not a CI PASS)\n'; exit 0; }

# 300s -> 1800s (2026-08-01). The default was shorter than this repo's own CI: the mutate job runs
# ~21-24 min, so EVERY land exited 12 ("shipped but unwatched") and the watch had to be repeated by
# hand — a guarantee that never once fired is worse than no guarantee, because it reads as one.
# Raising a CEILING costs nothing when CI is fast: the watch returns the moment the run concludes,
# so this only changes behaviour for runs that would otherwise have been abandoned.
appear="${SHIP_CI_APPEAR:-90}"; poll="${SHIP_CI_POLL:-10}"; timeout="${SHIP_CI_TIMEOUT:-1800}"
printf '== ship.sh: watching CI for %s (opt out: SHIP_CI_WATCH=0) …\n' "$short"

# 1) wait for a run to register against this commit
run_id=""; tries=0; max=$(( appear / 5 + 1 ))
while [ "$tries" -lt "$max" ]; do
  run_id="$(gh run list --limit 20 --json databaseId,headSha \
    -q "map(select(.headSha==\"$sha\"))[0].databaseId // empty" 2>/dev/null || true)"
  [ -n "$run_id" ] && break
  tries=$((tries + 1)); sleep 5
done
[ -n "$run_id" ] || {
  printf '== ship.sh: no CI run appeared for %s — UNWATCHED (check: gh run list)\n' "$short"; exit 0; }

# 2) poll to conclusion (check-then-sleep: an already-finished run costs no wait)
tries=0; max=$(( timeout / poll + 1 ))
while [ "$tries" -lt "$max" ]; do
  st="$(gh run view "$run_id" --json status,conclusion -q '.status + "/" + (.conclusion // "")' 2>/dev/null || true)"
  case "$st" in
    completed/success) printf '== ship.sh: CI GREEN (run %s)\n' "$run_id"; exit 0 ;;
    completed/*)       printf 'ship.sh: CI RED (run %s: %s) — SHIPPED; fix forward: gh run view %s --log-failed\n' \
                         "$run_id" "$st" "$run_id" >&2; exit 10 ;;
  esac
  tries=$((tries + 1)); sleep "$poll"
done
# A run EXISTS and we stopped watching it. Not a pass — say so with its own code (R74 amended).
printf 'ship.sh: CI STILL RUNNING after %ss — SHIPPED but UNWATCHED; verify: gh run watch %s\n' \
  "$timeout" "$run_id" >&2
exit 12
