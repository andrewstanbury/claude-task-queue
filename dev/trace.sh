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
# BYTE-WISE, not locale-collated. `sort -u` under a UTF-8 collation can judge two byte-DISTINCT
# lines equal and silently drop one, which is how a requirement claim vanished on the macOS lane
# while the Linux lane stayed green and the bytes on both sides were provably identical. Every
# comparison here is an identity test between a test title and a claim, so collation has no
# business in it. (Same family as the LC_ALL=C already required by the timing gate — LESSONS.)
export LC_ALL=C
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
  # The staleness stamps (R97). Enforced HERE, in the shape gate, for one reason: a field that is
  # optional is a field that is absent on the next entry someone adds, and dev/stale.sh cannot
  # report on a requirement it cannot date. `affirmed:` is when a HUMAN last confirmed this is
  # still wanted — editing the entry is not affirming it — and `affirmations:` is how many times
  # it has survived a challenge, which is what multiplies its threshold.
  printf '%s' "$block" | grep -qE '^  affirmed: [0-9]{4}-[0-9]{2}-[0-9]{2}[[:space:]]*$' \
    || { echo "FAIL $r has no well-formed \`affirmed: YYYY-MM-DD\` (R97 — stale.sh cannot date it)"; fail=1; }
  printf '%s' "$block" | grep -qE '^  affirmations: [0-9]+[[:space:]]*$' \
    || { echo "FAIL $r has no \`affirmations: <n>\` count (R97 — the challenge backoff has no exponent)"; fail=1; }
done

# The two directions between requirements and the suite.
claimed=$(grep -oE '^\s+- "[^"]+"' docs/requirements.yaml | sed 's/.*- "//; s/"$//' | sort -u)
actual=$(grep -hoE '^@test "[^"]+"' dev/tests/*.bats 2>/dev/null | sed 's/^@test "//; s/"$//' | sort -u)
while IFS= read -r t; do
  [ -n "$t" ] || continue
  # <<< herestring, NOT `printf ... | grep -qxF` (R30·d8 — shipped red on macOS, not Linux): under
  # `pipefail`, `-q` closes its stdin the instant it finds a match, and once the growing list of
  # claimed/actual titles (203 tests, 64 requirements as of R100) outgrows the pipe buffer (~16KB
  # on macOS vs ~64KB on Linux — exactly the platform split that made this Linux-invisible), a
  # LATER printf write() lands on that closed pipe and SIGPIPEs — a real match then reads back as a
  # pipeline FAILURE, so this gate could report a false FAIL depending on buffering, not content. A
  # herestring hands grep the data directly, with no separate writer process left to race.
  grep -qxF "$t" <<< "$actual" || { echo "FAIL requirement names a test that does not exist: \"$t\""; fail=1; }
done <<< "$claimed"
while IFS= read -r t; do
  [ -n "$t" ] || continue
  grep -qxF "$t" <<< "$claimed" || { echo "FAIL test is claimed by no requirement: \"$t\""; fail=1; }
done <<< "$actual"

n_un=$(printf '%s\n' "$need_ids" | grep -c .); n_sr=$(printf '%s\n' "$sr_ids" | grep -c .)
n_t=$(printf '%s\n' "$actual" | grep -c .)
if [ "$fail" = 0 ]; then
  echo "  ok  traceability closed: ${n_un} needs <- ${n_sr} requirements <- ${n_t} tests, no orphans either way"
else
  echo "  FAIL traceability is broken — see above"
fi
exit "$fail"
