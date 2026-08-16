#!/usr/bin/env bash
# portability-lint.sh — the traps that keep costing this repo real time, checked mechanically
# because prose demonstrably has not prevented them. The first two keep shipping red CI because the
# LOCAL toolchain cannot reproduce the other platform. Extracted from check.sh so the SUITE can exercise them (same reason
# as doc-lint.sh and mutate-gate.sh): inline in check.sh they had declared mutations and no tests,
# so the mutation gate reported them as HOLES — a guard that cannot fail is not a guard.
#
#   sc2015  `A && B || C` — shellcheck flags it, but only on some builds. The local build (0.11.0)
#           stays silent where CI's (0.9.0) does not, so the gate is green right up until it is not.
#           Shipped red in 3.16.0, 3.17.0 and again today.
#   bre     `\?` `\+` `\|` in sed/grep — GNU extensions that BSD (the macOS lane) reads as LITERALS.
#           Shipped red three times before today; today `slugify` used `\+` and burn-down could not
#           create a single branch on macOS while Linux stayed green.
#
# Both shapes are sometimes correct on purpose. A deliberate use is marked `# sc2015-ok` / `# bre-ok`
# on the line, which makes the exemption a reviewable act rather than a silent habit.
#
#   fixtures  `$(mktemp -d)` in a test — bats removes BATS_TEST_TMPDIR itself, a bare mktemp does
#             not. One session of this suite left 37,000 dirs in /tmp and exhausted the inode
#             table, after which unrelated tests fail in ways that look like code defects.
#             This lint lives HERE rather than in a bats case because a test that greps for the
#             pattern necessarily contains it, and so fails on itself forever.
#
#   portability-lint.sh sc2015 <file...>
#   portability-lint.sh bre    <file...>
#   portability-lint.sh fixtures <test-file...>
#   portability-lint.sh all    <file...>
set -uo pipefail

lint_sc2015() {
  local rc=0 hit
  while IFS= read -r hit; do
    case "$hit" in *sc2015-ok*) continue ;; esac
    echo "  FAIL $hit"; rc=1
  done < <(grep -HnE '\][[:space:]]*&&[[:space:]]*\[[^]]*\][[:space:]]*\|\|' "$@" 2>/dev/null \
           | grep -vE ':[0-9]+:[[:space:]]*#')
  return "$rc"
}

lint_bre() {
  local rc=0 hit
  while IFS= read -r hit; do
    case "$hit" in *bre-ok*) continue ;; esac
    echo "  FAIL $hit"; rc=1
  done < <(grep -HnE '(sed|grep)[[:space:]]+[^|]*\\[+?|]' "$@" 2>/dev/null \
           | grep -vE ':[0-9]+:[[:space:]]*#' \
           | grep -vE '(sed|grep)[[:space:]]+(-[a-zA-Z]*[Er][a-zA-Z]*[[:space:]])')
  return "$rc"
}

lint_fixtures() {
  local rc=0 hit
  while IFS= read -r hit; do
    echo "  FAIL $hit"; rc=1
  # Skip comments, like the other two lints: a line that NAMES the pattern is documentation, not
  # a leak, and without this the guard flags every explanation of itself.
  done < <(grep -HnF '$(mktemp -d)' "$@" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')
  return "$rc"
}

# boundary — a test fixture pinned to the EXACT value of a threshold the product compares against.
# The code reads its own clock a beat after the fixture is built, so a reset written as `now+86400`
# against a 86400s boundary arrives as 86399 and tips the branch at random: green locally, red on
# CI, and it reddened both lanes TWICE in one day. The prose lesson against this was written the
# same morning it was violated, in the test that DEFINES the threshold — which is this repo's own
# bar for making a rule mechanical.
#
# Constants are DERIVED from the source, never listed here (R9): any `NAME="${ENV:-<digits>}"` in
# the shipped bin/. Only values >= 600 count. Magnitude is the only signal available for telling a
# DURATION from a percentage or a count, and the first cut at >= 60 swept in TARGET=100, flagging
# six innocent "100%" assertions in the status-line tests — burying the two real hits. 600s is
# comfortably above any percentage or tally this product uses and below its smallest real timeout.
# A deliberate boundary test marks the line `# boundary-ok`.
lint_boundary() {
  local rc=0 v hit vals
  vals="$(grep -hoE '^[A-Z_]+="\$\{[A-Z_]+:-[0-9]+\}"' plugins/companion/bin/*.sh 2>/dev/null \
          | sed 's/.*:-//; s/}"//' | sort -u)"
  [ -n "$vals" ] || { echo "  FAIL boundary: derived NO threshold constants — the lint would pass vacuously"; return 1; }
  for v in $vals; do
    [ "$v" -ge 600 ] 2>/dev/null || continue
    while IFS= read -r hit; do
      case "$hit" in *boundary-ok*) continue ;; esac
      echo "  FAIL $hit"; echo "       ^ pinned to the ${v}s threshold — offset it, or mark the line # boundary-ok"; rc=1
    done < <(grep -HnE "(^|[^0-9])$v([^0-9]|\$)" "$@" 2>/dev/null | grep -vE ':[0-9]+:[[:space:]]*#')
  done
  return "$rc"
}

# sedi — `sed -i` with NO suffix. GNU treats the next argument as the SCRIPT; BSD (the macOS lane)
# treats it as the BACKUP SUFFIX and then reads the real script as a filename. The edit therefore
# does not happen, silently, and any test that depended on it passes for the wrong reason — which is
# exactly how it reddened macOS CI on 3.87.0: a test sabotaged a file, the sabotage never applied,
# the code under test behaved correctly, and the assertion that it should MISbehave failed.
# `sed -i.bak` (or `sed ... > tmp && mv`) works on both. FIFTH BSD-vs-GNU incident in this repo.
lint_sedi() {
  local rc=0 hit
  while IFS= read -r hit; do
    echo "  FAIL $hit"
    echo "       ^ bare 'sed -i' — BSD reads the next arg as a BACKUP SUFFIX. Use 'sed -i.bak' or 'sed … > tmp && mv'"
    rc=1
  # -i immediately followed by whitespace is the broken form; -i.bak / -i'' are fine. Comments are
  # skipped, and a line may opt out with `# sedi-ok` — the same escape the boundary lint uses. That
  # marker is not a loophole, it is the answer to the mirror problem this repo keeps rediscovering:
  # a line-based lint cannot tell CODE from DATA, so the lint's own failure message and the fixtures
  # that feed it a bad example all tripped it on the first run. Marking those is honest; widening
  # the pattern until they pass would blind it to the real thing.
  done < <(grep -HnE "sed[[:space:]]+(-[a-zA-Z]*[[:space:]]+)*-i[[:space:]]" "$@" 2>/dev/null \
           | grep -vE ':[0-9]+:[[:space:]]*#' | grep -vF 'sedi-ok')
  return "$rc"
}

mode="${1:-all}"; shift || true
[ "$#" -gt 0 ] || { echo "usage: portability-lint.sh [sc2015|bre|all] <file...>" >&2; exit 2; }
rc=0
case "$mode" in
  sc2015)   lint_sc2015 "$@" || rc=1 ;;
  bre)      lint_bre "$@"    || rc=1 ;;
  sedi)     lint_sedi "$@"   || rc=1 ;;
  fixtures) lint_fixtures "$@" || rc=1 ;;
  boundary) lint_boundary "$@" || rc=1 ;;
  all)      lint_sc2015 "$@" || rc=1; lint_bre "$@" || rc=1; lint_sedi "$@" || rc=1 ;;
  *)        echo "usage: portability-lint.sh [sc2015|bre|sedi|fixtures|boundary|all] <file...>" >&2; exit 2 ;;
esac
exit "$rc"
