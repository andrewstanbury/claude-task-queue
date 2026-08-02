#!/usr/bin/env bash
# portability-lint.sh — the two traps that keep shipping red CI because the LOCAL toolchain cannot
# reproduce the other platform. Extracted from check.sh so the SUITE can exercise them (same reason
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
#   portability-lint.sh sc2015 <file...>
#   portability-lint.sh bre    <file...>
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

mode="${1:-all}"; shift || true
[ "$#" -gt 0 ] || { echo "usage: portability-lint.sh [sc2015|bre|all] <file...>" >&2; exit 2; }
rc=0
case "$mode" in
  sc2015) lint_sc2015 "$@" || rc=1 ;;
  bre)    lint_bre "$@"    || rc=1 ;;
  all)    lint_sc2015 "$@" || rc=1; lint_bre "$@" || rc=1 ;;
  *)      echo "usage: portability-lint.sh [sc2015|bre|all] <file...>" >&2; exit 2 ;;
esac
exit "$rc"
