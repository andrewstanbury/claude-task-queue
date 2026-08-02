#!/usr/bin/env bash

# ── ./check.sh --mutate (R78) ────────────────────────────────────────────────────────
# The gate lives in dev/ — it verifies the plugin, it is not part of it. Delegated, not
# reimplemented, and not shipped to anyone who installs the plugin.
if [ "${1:-}" = "--mutate" ]; then
  shift
  exec "$(dirname "$0")/dev/mutate-gate.sh" "$@"
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
elif [ "${core_b:-0}" -gt 6656 ]; then
  # 12288 -> 6144 when the core was cut 11097B -> 5919B, then 6144 -> 6656 once a devil's-advocate
  # pass proved that 5919B core had silently DROPPED EIGHT BEHAVIOURAL RULES. The old cap was
  # calibrated against a defective measurement, so defending it meant compressing real instructions
  # to protect a number derived from bad data — which is how the rules got lost in the first place.
  # This is still a 40% cut from 11097B, with the eight restored and ~380B of honest headroom.
  # A cap should track what the content genuinely needs; it stops being a budget the moment it
  # starts deciding what the content is allowed to say.
  echo "  FAIL STEERING.md injected core: ${core_b}B > 6656B"; tok_fail=1; fail=1
fi
# LESSONS is two-tier like STEERING (owner-picked 2026-08-01): the cap applies to what is actually
# INJECTED, not to the file. Without the split the file was 5B under its ceiling while the process
# tells every session to append to it — so each new lesson was paid for by deleting a true one.
# Marker policed exactly as STEERING's: zero → the whole file injects (cap silently under-measured),
# two+ → the awk cut truncates at the first while this gate still reads green.
les_n="$(grep -c 'lessons injection stops here' docs/LESSONS.md 2>/dev/null || true)"
if [ -f docs/LESSONS.md ] && [ "${les_n:-0}" -ne 1 ]; then
  echo "  FAIL docs/LESSONS.md: 'lessons injection stops here' marker count is ${les_n:-0}, must be exactly 1"; tok_fail=1; fail=1
fi
for spec in "CLAUDE.md:4096" "docs/LESSONS.md:6144"; do
  f="${spec%%:*}"; cap="${spec##*:}"; [ -f "$f" ] || continue
  # Measure what session-start actually injects (same awk, same fail-open) — not the whole file.
  b="$(awk '/lessons injection stops here/{exit} {print}' "$f" | wc -c | tr -d '[:space:]')"
  if [ "${b:-0}" -gt "$cap" ]; then echo "  FAIL $f: ${b}B injected > ${cap}B (injected every session)"; tok_fail=1; fail=1; fi
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
  fm="$(dev/doc-lint.sh fm "$f")"   # one shared reader — CRLF/BOM safe (R78)
  draw="$(printf '%s\n' "$fm" | awk -F'description: '   '/^description: /{print $2; exit}')"
  hraw="$(printf '%s\n' "$fm" | awk -F'argument-hint: ' '/^argument-hint: /{print $2; exit}')"
  d="$(unquote "$draw")"; hint="$(unquote "$hraw")"

  # Frontmatter lint lives in dev/doc-lint.sh so the SUITE can exercise it (R78) — check.sh runs
  # bats, so anything inline here is untestable by construction and was a named gap.
  if ! out="$("$PWD/dev/doc-lint.sh" frontmatter "$f")"; then
    printf '%s\n' "$out"; tok_fail=1; fail=1
  fi

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
# Ledger evidence lint — also in dev/doc-lint.sh, same reason (R78).
led_fail=0
if ! out="$(dev/doc-lint.sh ledger docs/REQUIREMENTS.md)"; then
  printf '%s\n' "$out"; led_fail=1; fail=1
fi
[ "$led_fail" -eq 0 ] && echo "  ok (ledger measurements cite their evidence)"

[ "$tok_fail" -eq 0 ] && echo "  ok (STEERING core ${core_b}B/6656B; command descriptions ≤140B; arg-taking commands hinted)"

# NOTE: the contract-drift backstop (bin/contract-drift.sh) deliberately does NOT run here
# (R58 amended 2026-07-22): a warning on every mid-work gate run — where drift is the normal
# intermediate state — trains its own tune-out, and CI is a clean-tree no-op anyway. It runs at
# the ONE boundary where drift is real and actionable: /companion:ship-it's contract-sync step.

section "Hook budget (R81 — hooks stay O(1) in store size; MEASURED, not asserted)"
# Lives in dev/hook-budget.sh so the SUITE can exercise it (same reason as doc-lint, R78).
# Primary assertion is a SCALING RATIO, not a wall-clock cap — see that file's header for why an
# absolute-ms budget is machine-dependent and self-defeating. This is the gate that would have
# stopped the 2085ms->16108ms session-start scan (measured 8.06x, caught) from ever shipping.
if ! "$PWD/dev/hook-budget.sh"; then
  echo "  FAIL — a hook's cost grows with the task store (R81)"; fail=1
fi

section "Tests (bats)"
if have bats; then
  # One suite, one location — the tests moved to dev/ with the gates they run (they verify the
  # plugin; they are not part of it). No glob: a loop over one fixed path is just a path.
  d=dev/tests
  if [ -d "$d" ]; then
    echo "  -- $d --"
    bats --print-output-on-failure "$d" || fail=1
  else
    echo "  FAIL — $d missing"; fail=1
  fi
else
  echo "  FAIL — bats not installed (required to run tests)"; fail=1
fi

section "Result"
if [ "$fail" -eq 0 ]; then echo "  PASS"; else echo "  FAILURES — see above"; fi
exit "$fail"

