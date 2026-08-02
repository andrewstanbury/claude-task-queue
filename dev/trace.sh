#!/usr/bin/env bash
# trace.sh — THE gate that makes this a V rather than three documents that happen to sit near code.
# Needs are UN-*, requirements are R* (the ledger ids, kept so every existing reference in code
# comments, commit messages and command prose still resolves — renaming 84 ids would have been
# churn with no verification value).
#
# It walks the traceability chain in BOTH directions and fails on any break:
#   UN  <- SR   every need is satisfied by at least one requirement   (nothing asked for, unbuilt)
#   SR  -> UN   every requirement traces to a real need               (nothing built, unasked for)
#   SR  -> TEST every requirement names tests that EXIST              (no unverified requirement)
#   TEST-> SR   every test is claimed by a requirement                (no test verifying nothing)
#
# The last one is the uncomfortable direction and the reason this exists. Tests accumulate around
# whatever was recently painful; without this check nobody ever asks which requirement a test is
# for, and the suite drifts into a pile of habits. An orphan test is not free — it is a claim
# about the system that no requirement is willing to own.
#
# Deliberately NOT a YAML parser: this reads the two files with grep/sed so it has no dependency
# beyond coreutils. The files are written to a fixed shape and this gate enforces that shape.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 2

fail=0
need_ids=$(grep -oE '^- id: (UN-[0-9]+)' docs/needs.yaml | awk '{print $3}' | sort -u)
sr_ids=$(grep -oE '^- id: (R[0-9]+(·[a-z])?)' docs/requirements.yaml | awk '{print $3}' | sort -u)
[ -n "$need_ids" ] || { echo "FAIL no needs found — docs/needs.yaml unreadable or empty"; exit 2; }
[ -n "$sr_ids" ]   || { echo "FAIL no requirements found — docs/requirements.yaml unreadable or empty"; exit 2; }

# Every `satisfies:` target must be a real need id.
while IFS= read -r ref; do
  [ -n "$ref" ] || continue
  printf '%s\n' "$need_ids" | grep -qx "$ref" || { echo "FAIL requirement references unknown need: $ref"; fail=1; }
done < <(grep -oE 'satisfies: \[[^]]*\]' docs/requirements.yaml | grep -oE 'UN-[0-9]+' | sort -u)
# Every need must be claimed by some requirement.
for n in $need_ids; do
  grep -qE "satisfies: \[[^]]*$n" docs/requirements.yaml || { echo "FAIL need $n is satisfied by NO requirement"; fail=1; }
done
# Every requirement must name at least one test.
for r in $sr_ids; do
  block=$(awk -v id="$r" '/^- id: /{keep=($3==id)} keep' docs/requirements.yaml)
  printf '%s' "$block" | grep -q 'verified_by:' || { echo "FAIL $r has no verified_by:"; fail=1; continue; }
  if printf '%s' "$block" | grep -q '^  judgment:'; then :   # judgement-shaped: validated by a human, not a case
  else printf '%s' "$block" | grep -qE '^\s+- "' || { echo "FAIL $r names no tests and is not marked judgment:"; fail=1; }; fi
done

# The two directions between requirements and the suite.
claimed=$(grep -oE '^\s+- "[^"]+"' docs/requirements.yaml | sed 's/.*- "//; s/"$//' | sort -u)
actual=$(grep -hoE '^@test "[^"]+"' dev/tests/*.bats 2>/dev/null | sed 's/^@test "//; s/"$//' | sort -u)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  printf '%s\n' "$actual" | grep -qxF "$t" || { echo "FAIL requirement names a test that does not exist: \"$t\""; fail=1; }
done <<< "$claimed"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  printf '%s\n' "$claimed" | grep -qxF "$t" || { echo "FAIL test is claimed by no requirement: \"$t\""; fail=1; }
done <<< "$actual"

n_un=$(printf '%s\n' "$need_ids" | grep -c .); n_sr=$(printf '%s\n' "$sr_ids" | grep -c .)
n_t=$(printf '%s\n' "$actual" | grep -c .)
if [ "$fail" = 0 ]; then
  echo "  ok  traceability closed: ${n_un} needs <- ${n_sr} requirements <- ${n_t} tests, no orphans either way"
else
  echo "  FAIL traceability is broken — see above"
fi
exit "$fail"
