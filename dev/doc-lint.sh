#!/usr/bin/env bash
# doc-lint — two document checks the project gate runs, extracted so the TEST SUITE can exercise
# them (R78). They used to live inline in `check.sh`, which the suite cannot invoke without
# recursion (check.sh runs bats), so neither had a behavioural case nor a mutation — a gap R78 had
# to record rather than close. Called by `check.sh`; called directly by `companion-core.bats`.
#
#   doc-lint.sh frontmatter <file>...   command-prompt frontmatter, known-bad shapes only
#   doc-lint.sh ledger <file>           a ledger measurement must name where it was measured
#   doc-lint.sh fm <file>               print the frontmatter block (the one shared reader)
#
# Prints one `  FAIL <detail>` line per problem and exits 1 if any fired; silent + exit 0 when clean.
# Not a hook: dev/ship-time only, like `contract-drift.sh`.
set -uo pipefail

# THE frontmatter reader — one copy, because check.sh needs the same block for its byte cap and
# its hint-agreement check, and two copies of this awk meant a fix landed in only one of them.
# `sub(/\r$/,"")`: a CRLF file made line 1 `---\r`, which never equalled `---`, so the block came
# back EMPTY and every frontmatter check silently passed — fail-open on all of them at once.
# `sub(/^[^-]*/,"")` on line 1 strips a UTF-8 BOM the same way (a line with no `-` empties out and
# is correctly read as "no frontmatter").
read_fm() { awk '{sub(/\r$/,"")} NR==1{sub(/^[^-]*/,"")} NR==1&&$0=="---"{inf=1;next} inf&&$0=="---"{exit} inf{print}' "$1"; }

# FRONTMATTER — a LINT ON KNOWN-BAD SHAPES, not a YAML validator. The host parses frontmatter as
# YAML and drops the WHOLE block on a throw (description AND argument-hint together) behind a
# debug-level warning, which a line-grep can never see. Scoped to the two keys the gate reads: an
# earlier whole-block whitelist rejected `allowed-tools:` block/flow sequences and single-quoted
# scalars, all of which the host accepts — a gate that breaks valid commands is worse than none.
# It does NOT catch every throw (a `? ` indicator, malformed keys it doesn't read); R78 says so.
lint_frontmatter() {
  local f rc=0 fm key n v
  for f in "$@"; do
    [ -f "$f" ] || continue
    fm="$(read_fm "$f")"
    for key in description argument-hint; do
      n="$(printf '%s\n' "$fm" | grep -c "^$key:" || true)"
      if [ "${n:-0}" -gt 1 ]; then
        echo "  FAIL $(basename "$f") duplicate \`$key:\` key — YAML throws and the host drops the ENTIRE block (R78)"; rc=1
      fi
      v="$(printf '%s\n' "$fm" | sed -n "s/^$key: *//p" | head -1)"
      [ -n "$v" ] || continue
      case "$v" in
        \"*\"|\'*\') : ;;                                    # properly closed quotes: fine
        \"*|\'*)
          echo "  FAIL $(basename "$f") \`$key\` opens a quote it never closes — the host drops the ENTIRE block (R78)"; rc=1 ;;
        \>|\||\>-|\|-) : ;;                                 # folded/literal block scalar: valid YAML
        [\[\{\*\&\!%@\`\>\|,\#?-]*)
          echo "  FAIL $(basename "$f") \`$key\` starts with a YAML indicator and is unquoted — the host drops the ENTIRE block (R75)"; rc=1 ;;
        *": "*|*:)
          echo "  FAIL $(basename "$f") \`$key\` contains a colon and is unquoted — YAML reads it as a nested mapping (R75)"; rc=1 ;;
      esac
    done
  done
  return "$rc"
}

# LEDGER — a stated measurement must name where it came from. "The no-progress cap remains the
# backstop" shipped in an R-cell and was false; three byte figures in another were wrong. Neither is
# mechanically checkable, but *asserting a number without saying how you got it* is, and that is the
# habit that produced both. Hard units only (bytes / tokens / N-of-N): a rhetorical "~90% of the
# value" is a judgement, not a measurement, and must not trip this. A nudge, not a guarantee — the
# evidence markers are trivially satisfiable, so it prompts the author rather than proving anything.
lint_ledger() {
  local f="${1:-}" rc=0 row rid fb bare
  # A missing file used to exit 0, and check.sh then printed "ok" for a check it never ran.
  if [ ! -f "$f" ]; then echo "  FAIL ledger file not found: $f — the check did not run (R78)"; return 1; fi
  fb="$(basename "$f")"   # resolved once: computing it inside the loop reads as a write to $f
  while IFS= read -r row; do
    case "$row" in '| **R'*) : ;; *) continue ;; esac
    # Strip approximations FIRST. Matching `(^|[^~])[0-9]` could begin one digit inside the
    # number, so `~371B` tripped while `~9B` did not — the exemption only worked on single digits.
    # POSIX BRE only: `\?` is a GNU extension that BSD/macOS sed treats as a literal `?`, so the
    # first version of this silently matched nothing on the macOS lane and reddened CI.
    bare="$(printf '%s' "$row" | sed -e 's/[~≈][0-9][0-9.,]*/ /g')"
    printf '%s' "$bare" | grep -qE '[0-9][0-9,]* ?(B[^a-zA-Z]|bytes|tokens?)|[0-9]+/[0-9]+' || continue
    # shellcheck disable=SC2016  # backticks are literal — they delimit a filename in the prose
    printf '%s' "$row" | grep -qiE 'measured|verified|reproduc|exercis|mutation-tested|bats|check\.sh|`[^`]*\.(sh|md|json|bats)`' && continue
    rid="$(printf '%s' "$row" | sed -n 's/^| \*\*\(R[0-9]*\)\*\*.*/\1/p')"
    echo "  FAIL $fb $rid states a measurement with no evidence — say where it was measured (R78)"; rc=1
  done < "$f"
  return "$rc"
}

case "${1:-}" in
  fm)          shift; read_fm "${1:-}" ;;
  frontmatter) shift; lint_frontmatter "$@" ;;
  ledger)      shift; lint_ledger "${1:-}" ;;
  *) echo "usage: doc-lint.sh frontmatter <file>... | ledger <file> | fm <file>" >&2; exit 2 ;;
esac
