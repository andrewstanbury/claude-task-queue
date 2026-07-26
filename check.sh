#!/usr/bin/env bash

# ── ./check.sh --mutate (R78) ──────────────────────────────────────────────────────────────────
# A green suite proves the tests pass, not that they CAN fail. Three fixtures in one session were
# vacuous — each masked by another rule it also tripped — and every one hid a real defect. This
# mode applies each declared mutation to the enforced core and asserts the suite goes RED. A
# mutation that stays green is a hole: a test that cannot fail. CI-only by design; it costs a full
# suite run per mutation, so it is never part of the default gate.
if [ "${1:-}" = "--mutate" ]; then
  mfile="plugins/companion/tests/mutations.txt"
  [ -f "$mfile" ] || { echo "no $mfile"; exit 2; }
  command -v bats >/dev/null 2>&1 || { echo "  SKIP — bats not installed"; exit 0; }
  # RESTORE ON ANY EXIT. This mutates the live working tree — including `secret-guard.sh`, a hook
  # that is ACTIVE in this repo. Without a trap, one Ctrl-C leaves the secret gate disabled and a
  # mutated file staged by the next `git add -A` (R7 must never fail open). Belt and braces: the
  # trap restores, and `.gitignore` covers `*.mutbak` so a stray one can never be committed.
  # shellcheck disable=SC2329  # invoked via the trap below, not by name
  _mut_restore() {
    find plugins -name '*.mutbak' -print0 2>/dev/null |
      while IFS= read -r -d '' b; do mv -f "$b" "${b%.mutbak}"; done
  }
  trap '_mut_restore' EXIT INT TERM HUP
  holes=0; ran=0
  while IFS= read -r line; do
    case "$line" in ''|'#'*) continue ;; esac
    tgt="${line%%::*}"; tmp="${line#*::}"; sedscript="${tmp%%::*}"; what="${tmp#*::}"
    [ -f "$tgt" ] || { echo "  SKIP (missing) $tgt"; continue; }
    cp "$tgt" "$tgt.mutbak"
    if ! sed -i.bak "$sedscript" "$tgt" 2>/dev/null; then
      mv "$tgt.mutbak" "$tgt"; rm -f "$tgt.bak"
      echo "  FAIL mutation did not apply — the sed script is stale: $what"; holes=$((holes+1)); continue
    fi
    rm -f "$tgt.bak"
    if cmp -s "$tgt" "$tgt.mutbak"; then
      mv "$tgt.mutbak" "$tgt"
      echo "  FAIL mutation matched NOTHING (stale pattern): $what"; holes=$((holes+1)); continue
    fi
    ran=$((ran+1))
    if bats plugins/companion/tests >/dev/null 2>&1; then
      echo "  HOLE  suite stayed GREEN with: $what"; holes=$((holes+1))
    else
      echo "  ok    caught: $what"
    fi
    mv "$tgt.mutbak" "$tgt"
  done < "$mfile"
  echo
  if [ "$holes" -gt 0 ]; then printf '== Mutation result ==\n  %s HOLE(S) of %s — a test that cannot fail is not coverage\n' "$holes" "$ran"; exit 1; fi
  echo "== Mutation result =="; echo "  all $ran mutations caught"; exit 0
fi

# One-command check — the single source of truth for what this repo enforces.
#
# CI (.github/workflows/ci.yml) provisions every tool and runs THIS script, so
# "green locally" == "green in CI", except that tools you don't have installed
# locally are SKIPPED with a note (CI has them all and is authoritative).
# Exits non-zero on any failure.

set -uo pipefail
cd "$(dirname "$0")" || exit 1
shopt -s nullglob

fail=0
have()    { command -v "$1" >/dev/null 2>&1; }
section() { printf '\n== %s ==\n' "$1"; }

scripts=(check.sh plugins/*/bin/*.sh plugins/*/lib/*.sh)
manifests=(plugins/*/.claude-plugin/plugin.json plugins/*/hooks/hooks.json)

section "JSON valid"
for f in .claude-plugin/marketplace.json "${manifests[@]}"; do
  if jq empty "$f" 2>/dev/null; then echo "  ok   $f"; else echo "  FAIL $f"; fail=1; fi
done

section "Marketplace manifest"
if have claude; then
  if claude plugin validate . >/dev/null 2>&1; then echo "  ok"; else
    echo "  FAIL — claude plugin validate ."; claude plugin validate . 2>&1 | sed 's/^/    /'; fail=1
  fi
else
  echo "  SKIP — claude CLI not installed (run locally before publishing)"
fi

section "Version match (each plugin.json == its marketplace entry)"
vm_fail=0
for pj in plugins/*/.claude-plugin/plugin.json; do
  name=$(jq -r '.name // empty' "$pj")
  pv=$(jq -r '.version // empty' "$pj")
  mkt=$(jq -r --arg n "$name" '.plugins[] | select(.name==$n) | .version' .claude-plugin/marketplace.json)
  if [ -z "$name" ] || [ -z "$pv" ]; then
    echo "  FAIL $pj: missing name/version"; vm_fail=1; fail=1
  elif [ -z "$mkt" ] || [ "$mkt" = "null" ]; then
    echo "  FAIL $name: no marketplace entry"; vm_fail=1; fail=1
  elif [ "$pv" != "$mkt" ]; then
    echo "  FAIL $name: plugin.json $pv != marketplace $mkt"; vm_fail=1; fail=1
  fi
done
[ "$vm_fail" -eq 0 ] && echo "  ok"

section "ShellCheck"
if have shellcheck; then
  # SC1091: libs are sourced by a computed path at runtime — expected.
  if shellcheck -e SC1091 "${scripts[@]}"; then echo "  ok"; else fail=1; fi
else
  echo "  SKIP — shellcheck not installed (CI runs it)"
fi

section "Secret scan"
if have gitleaks; then
  if gitleaks detect --source . --no-git --redact; then echo "  ok"; else fail=1; fi
else
  echo "  SKIP — gitleaks not installed (CI runs it)"
fi

section "File size (<= 300 lines; decompose only when this fires)"
size_fail=0
for f in "${scripts[@]}"; do
  n=$(wc -l < "$f")
  if [ "$n" -gt 300 ]; then echo "  FAIL $f: $n > 300"; size_fail=1; fail=1; fi
done
[ "$size_fail" -eq 0 ] && echo "  ok"

section "Token budget (injected artifacts stay capped — R69)"
# Every byte here is paid EVERY session in EVERY installed repo; the budget is enforced, not
# advisory (the pre-R69 STEERING silently grew to 2.5x its documented token size — a doc-only
# budget demonstrably fails). BSD wc pads output — strip whitespace before numeric use (LESSONS).
tok_fail=0
core_b="$(awk '/injection stops here/{exit} {print}' plugins/companion/STEERING.md | wc -c | tr -d '[:space:]')"
marker_n="$(grep -c 'injection stops here' plugins/companion/STEERING.md || true)"
# Marker must appear EXACTLY once: zero → the whole doc gets injected; two+ → the awk cut
# silently truncates the core at the first occurrence while this gate keeps reading green.
if [ "${marker_n:-0}" -ne 1 ]; then
  echo "  FAIL STEERING.md: 'injection stops here' marker count is ${marker_n:-0}, must be exactly 1"; tok_fail=1; fail=1
elif [ "${core_b:-0}" -gt 12288 ]; then
  echo "  FAIL STEERING.md injected core: ${core_b}B > 12288B"; tok_fail=1; fail=1
fi
for spec in "CLAUDE.md:4096" "docs/LESSONS.md:6144"; do
  f="${spec%%:*}"; cap="${spec##*:}"; [ -f "$f" ] || continue
  b="$(wc -c < "$f" | tr -d '[:space:]')"
  if [ "${b:-0}" -gt "$cap" ]; then echo "  FAIL $f: ${b}B > ${cap}B (auto-loaded/injected every session)"; tok_fail=1; fail=1; fi
done
# Command `description:` frontmatter is ALSO always-loaded injection (the whole command list rides
# every session), yet R69 never capped it — the same silent-growth class. Cap each at 140B (a label,
# not a summary of the body); ceiling with working room over the current max (116B, handoff.md), not
# reverse-engineered. Prevention > detection (N7) — keeps a paragraph from creeping back in.
# Parameter names declared in a description or an argument-hint, one per line. Within each `[...]`
# group: cut the descriptive tail at the first em-dash or `: `, drop `<placeholders>`, then split on
# `|` and whitespace so an enum group names EVERY alternative (`[a|b | ship c]` -> a, b, ship) rather
# than only its first token — that blind spot let two thirds of autopilot's surface drift unnoticed.
# `[-- goal: …]` names `goal`; `[--gate <cmd>]` names `--gate`; a bare ledger id `[R55]` is ignored.
cmd_params() {
  printf '%s' "$1" | awk '{
    while (match($0, /\[[^]]*\]/)) {
      g = substr($0, RSTART + 1, RLENGTH - 2); $0 = substr($0, RSTART + RLENGTH)
      sub(/ —.*$/, "", g); sub(/:[ \t].*$/, "", g); gsub(/<[^>]*>/, "", g)
      gsub(/\|/, " ", g)
      n = split(g, w, /[ \t]+/)
      for (i = 1; i <= n; i++) {
        t = w[i]; sub(/[:,;.]$/, "", t)
        if (t ~ /^R[0-9]+$/) continue                       # a ledger citation, not a parameter
        if (t ~ /^--?[A-Za-z][A-Za-z0-9_-]*$/ || t ~ /^[A-Za-z][A-Za-z0-9_-]*$/) print t
      }
    }
  }' | sort -u
}
# Strip one layer of YAML double-quoting so caps are measured on the value the host actually loads.
unquote() { local v="$1"; case "$v" in \"*\") v="${v#\"}"; v="${v%\"}" ;; esac; printf '%s' "$v"; }
for f in plugins/companion/commands/*.md; do
  fm="$(awk 'NR==1&&$0=="---"{inf=1;next} inf&&$0=="---"{exit} inf{print}' "$f")"
  draw="$(printf '%s\n' "$fm" | awk -F'description: '   '/^description: /{print $2; exit}')"
  hraw="$(printf '%s\n' "$fm" | awk -F'argument-hint: ' '/^argument-hint: /{print $2; exit}')"
  d="$(unquote "$draw")"; hint="$(unquote "$hraw")"

  # FRONTMATTER SANITY for the two keys this gate reads (R75/R78). The host parses frontmatter as
  # YAML and drops the WHOLE block on a throw — description and argument-hint together — behind a
  # debug-level warning, which a line-grep can never see. This is a LINT ON KNOWN-BAD SHAPES, not a
  # YAML validator, and it is scoped to `description:`/`argument-hint:` on purpose: an earlier
  # whole-block whitelist rejected `allowed-tools:` block/flow sequences and single-quoted scalars,
  # all of which the host accepts happily — a gate that breaks valid commands is worse than none.
  # It does NOT catch every throw (duplicate keys, a `? ` indicator); the ledger says so plainly.
  for fmkey in description argument-hint; do
    fmn="$(printf '%s\n' "$fm" | grep -c "^$fmkey:" || true)"
    if [ "${fmn:-0}" -gt 1 ]; then
      echo "  FAIL $(basename "$f") duplicate \`$fmkey:\` key — YAML throws and the host drops the ENTIRE block (R78)"; tok_fail=1; fail=1
    fi
    fmv="$(printf '%s\n' "$fm" | sed -n "s/^$fmkey: *//p" | head -1)"
    [ -n "$fmv" ] || continue
    case "$fmv" in
      \"*\"|\'*\') : ;;                                       # properly closed quotes: fine
      \"*|\'*)
        echo "  FAIL $(basename "$f") \`$fmkey\` opens a quote it never closes — the host drops the ENTIRE block (R78)"; tok_fail=1; fail=1 ;;
      [\[\{\*\&\!%@\`\>\|,\#?-]*)
        echo "  FAIL $(basename "$f") \`$fmkey\` starts with a YAML indicator and is unquoted — the host drops the ENTIRE block (R75)"; tok_fail=1; fail=1 ;;
      *": "*|*:)
        echo "  FAIL $(basename "$f") \`$fmkey\` contains a colon and is unquoted — YAML reads it as a nested mapping (R75)"; tok_fail=1; fail=1 ;;
    esac
  done

  db="$(printf '%s' "$d" | wc -c | tr -d '[:space:]')"
  if [ "${db:-0}" -gt 140 ]; then echo "  FAIL $(basename "$f") description: ${db}B > 140B (per-session command-list injection)"; tok_fail=1; fail=1; fi

  # A body that reads $ARGUMENTS must declare a hint; a hint must not promise params the body ignores.
  takes_args=0
  # shellcheck disable=SC2016  # the literal string "$ARGUMENTS" is the target; expansion is wrong here
  grep -qF '$ARGUMENTS' "$f" && takes_args=1
  if [ "$takes_args" = 1 ] && [ -z "${hint// /}" ]; then
    echo "  FAIL $(basename "$f") reads \$ARGUMENTS but has no non-empty frontmatter argument-hint: (R75 — params must be visible in the / menu)"; tok_fail=1; fail=1
  fi
  if [ "$takes_args" = 0 ] && [ -n "${hint// /}" ]; then
    echo "  FAIL $(basename "$f") declares argument-hint: but the body never reads \$ARGUMENTS (R75 — the / menu would promise params the command ignores)"; tok_fail=1; fail=1
  fi
  # The hint renders with `truncate-end`, so the tail — usually the second parameter — is what
  # silently disappears. 80 chars is generous.
  if [ "${#hint}" -gt 80 ]; then
    echo "  FAIL $(basename "$f") argument-hint: ${#hint} chars > 80 (truncates in the / input box — name the params, don't document them)"; tok_fail=1; fail=1
  fi

  # description <-> argument-hint AGREEMENT, BOTH directions (R75 amended). The description is what
  # you read while BROWSING the / menu; the hint appears only once the command is already chosen. Two
  # places now state one fact, so neither may name a parameter the other doesn't.
  hp="$(cmd_params "$hint")"; dp="$(cmd_params "$d")"
  if [ -n "${hint// /}" ] && [ -z "$hp" ]; then
    echo "  FAIL $(basename "$f") argument-hint names no parameter in [brackets] — the agreement check cannot see it (R75)"; tok_fail=1; fail=1
  fi
  if [ -z "${hint// /}" ] && [ -n "$dp" ]; then
    echo "  FAIL $(basename "$f") description promises $(echo "$dp" | tr '\n' ' ')but there is no argument-hint (R75 — agree, or say '(no args)')"; tok_fail=1; fail=1
  fi
  if [ -n "$hp" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      # Set-compare when the description uses brackets. A substring test alone is too loose: renaming
      # `[branch]` to `[ref]` passed because the word "branch" survived in the prose. An enum-style
      # description (autopilot) has no bracket group, so it falls back to substring rather than being
      # forced into notation it reads worse in.
      if [ -n "$dp" ]; then
        case "$(printf '\n%s\n' "$dp")" in *"$(printf '\n%s\n' "$p")"*) continue ;; esac
      else
        case "$d" in *"$p"*) continue ;; esac
      fi
      echo "  FAIL $(basename "$f") argument-hint names \`$p\` but the description does not (R75 — the / menu and the autocomplete must agree)"; tok_fail=1; fail=1
    done <<EOF
$hp
EOF
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$(printf '\n%s\n' "$hp")" in *"$(printf '\n%s\n' "$p")"*) continue ;; esac
      echo "  FAIL $(basename "$f") description names \`$p\` but the argument-hint does not (R75 — agreement is both ways)"; tok_fail=1; fail=1
    done <<EOF
$dp
EOF
  fi
done
# A ledger MEASUREMENT must name where it came from (R78). "The no-progress cap remains the
# backstop" shipped in an R-cell and was simply false; three byte figures in another were wrong.
# Neither is mechanically checkable — but *asserting a number without saying how you got it* is,
# and that is the habit that produced both. Hard units only (bytes / tokens / N-of-N): a rhetorical
# "~90% of the value" is a judgement, not a measurement, and must not trip this. Calibrated against
# the existing ledger before landing: 5 rows carry a hard measurement, 0 lacked evidence.
led_fail=0
if [ -f docs/REQUIREMENTS.md ]; then
  while IFS= read -r row; do
    case "$row" in '| **R'*) : ;; *) continue ;; esac
    if printf '%s' "$row" | grep -qE '(^|[^~])[0-9][0-9,]* ?(B[^a-zA-Z]|bytes|tokens?)|(^|[^~])[0-9]+/[0-9]+'; then
      # shellcheck disable=SC2016  # backticks are literal here — they delimit a filename in the prose
      if ! printf '%s' "$row" | grep -qiE 'measured|verified|reproduc|exercis|mutation-tested|bats|check\.sh|`[^`]*\.(sh|md|json|bats)`'; then
        rid="$(printf '%s' "$row" | sed -n 's/^| \*\*\(R[0-9]*\)\*\*.*/\1/p')"
        echo "  FAIL docs/REQUIREMENTS.md $rid states a measurement with no evidence — say where it was measured (R78)"; led_fail=1; fail=1
      fi
    fi
  done < docs/REQUIREMENTS.md
fi
[ "$led_fail" -eq 0 ] && echo "  ok (ledger measurements cite their evidence)"

[ "$tok_fail" -eq 0 ] && echo "  ok (STEERING core ${core_b}B/12288B; command descriptions ≤140B; arg-taking commands hinted)"

# NOTE: the contract-drift backstop (bin/contract-drift.sh) deliberately does NOT run here
# (R58 amended 2026-07-22): a warning on every mid-work gate run — where drift is the normal
# intermediate state — trains its own tune-out, and CI is a clean-tree no-op anyway. It runs at
# the ONE boundary where drift is real and actionable: /companion:ship-it's contract-sync step.

section "Tests (bats)"
if have bats; then
  for d in plugins/*/tests tests; do
    [ -d "$d" ] || continue
    echo "  -- $d --"
    bats --print-output-on-failure "$d" || fail=1
  done
else
  echo "  FAIL — bats not installed (required to run tests)"; fail=1
fi

section "Result"
if [ "$fail" -eq 0 ]; then echo "  PASS"; else echo "  FAILURES — see above"; fi
exit "$fail"
