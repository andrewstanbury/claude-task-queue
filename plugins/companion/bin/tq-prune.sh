#!/usr/bin/env bash
# tq-prune.sh — STORE MAINTENANCE for `tq`, extracted 2026-08-16 when the size gate warned that
# `tq` was at 285/300. Same seam `tq-orphans.sh` was cut on and the same category: this DELETES
# things, which is a different job from running the queue, and cohesion — not line count — is what
# decides a split (the rule `tq` itself learned the hard way in R110).
#
# STATE IS PASSED IN, NEVER RE-DERIVED. `tq` resolves the store, the session dir and the repo
# identity through logic it deliberately keeps standalone; re-deriving any of it here would put a
# second copy of that decision behind the one operation in the whole plugin that removes the
# owner's history. `tq` execs this with TQ_STORE / TQ_DIR / TQ_ROOT / TQ_RID already set.
#
# Every guard below is load-bearing and each is a recorded incident, not caution:
#   · never this session · never follow a symlink (an rm -rf once emptied the link TARGET and
#     reported success) · this repo only (the store is shared, so pruning another project is
#     cross-repo bleed) · ANY open/parked/blocked work is a hard keep · an UNREADABLE file is a
#     keep, because reading jq's stdout instead of its exit status once deleted a store holding a
#     parked decision · age measured with POSIX -mtime (BSD find has no -newermt).
#
# Deliberately a CLI command and NOT wired into any hook: R68 forbids a hook deleting anything.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "tq prune: jq required" >&2; exit 1; }
STORE="${TQ_STORE:?tq prune: TQ_STORE not set — run this through \`tq prune\`}"
DIR="${TQ_DIR:?tq prune: TQ_DIR not set — run this through \`tq prune\`}"
root="${TQ_ROOT:-}"
rid="${TQ_RID:-}"

# R81 follow-up: PERF#1 made the cross-session resume scan 56x faster, but it is still O(store)
# — just with a tiny constant. This is what keeps the store BOUNDED rather than merely cheap.
#
# Deliberately a CLI command and NOT wired into any hook: R68 forbids a hook deleting anything,
# and that rule is right — an unattended delete of the owner's history is exactly the blast
# radius it exists to prevent. Scoped to THIS repo's session dirs only: the store is shared
# across projects, and pruning another project's history from here would be cross-repo bleed.
days=90; dry=0
while [ "$#" -gt 0 ]; do case "$1" in
  --days) days="$(printf '%s' "${2:-}" | tr -dc '0-9')"; [ -n "$days" ] || { echo "tq prune: --days needs a number" >&2; exit 1; }; shift 2 ;;
  --dry-run|-n) dry=1; shift ;;
  *) echo "tq prune: unknown argument '$1'" >&2; exit 1 ;;
esac; done
gone=0; kept=0
for d in "$STORE"/*/; do
  [ -d "$d" ] || continue
  [ "${d%/}" = "${DIR%/}" ] && { kept=$((kept+1)); continue; }          # never THIS session
  # NEVER follow a symlink. The glob matches symlinks-to-directories and yields a TRAILING
  # SLASH, which makes `rm -rf` recurse THROUGH the link and empty the target — measured:
  # an archived session dir outside the store was destroyed while the link itself survived,
  # and prune reported success. A linked store dir is someone's deliberate arrangement; skip it.
  [ -L "${d%/}" ] && { kept=$((kept+1)); continue; }
  # this repo only (same identity-then-legacy-abspath rule as matching_files)
  { [ "$(cat "$d.repo" 2>/dev/null || true)" = "$rid" ] || [ "$(cat "$d.root" 2>/dev/null || true)" = "$root" ]; } || continue
  # ANY open work — pending or in_progress, including ❓ parked and ⏳ blocked — is a hard keep.
  # The EXIT STATUS is the guard, not the stdout: `jq -s` prints `0` and exits 2 when it cannot
  # OPEN a file (permissions, I/O error, a root-owned file from a sudo run, a flaky SD card),
  # so reading stdout alone turned "unreadable" into "zero open tasks" and DELETED the store.
  # Measured: a chmod-000 file holding a ❓ parked task was destroyed, reported as success.
  # Any failure to read is now a KEEP — deleting what we could not inspect is unforgivable here.
  if ! n="$(jq -s '[.[]|select(.status=="pending" or .status=="in_progress")]|length' "$d"*.json 2>/dev/null)"; then
    kept=$((kept+1)); continue
  fi
  case "$n" in ''|*[!0-9]*) kept=$((kept+1)); continue ;; esac
  [ "$n" -gt 0 ] && { kept=$((kept+1)); continue; }
  # Age: POSIX `-mtime` (BSD find has no -newermt). Any file touched inside the window keeps it.
  [ -n "$(find "$d" -type f -mtime -"$days" 2>/dev/null | head -1)" ] && { kept=$((kept+1)); continue; }
  if [ "$dry" -eq 1 ]; then echo "  would remove $(basename "${d%/}")"
  else rm -rf "${d%/}" 2>/dev/null || { kept=$((kept+1)); continue; }; fi
  gone=$((gone+1))
done
if [ "$dry" -eq 1 ]; then echo "tq prune (dry run): $gone finished store(s) older than ${days}d would go, $kept kept"
else echo "tq prune: removed $gone finished store(s) older than ${days}d, kept $kept (any open/parked/blocked work is never touched)"; fi
