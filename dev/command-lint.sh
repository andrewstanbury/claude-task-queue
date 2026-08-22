#!/usr/bin/env bash
# command-lint.sh — the COMMAND CONTRACT checks (R75), extracted from check.sh 2026-08-03 when the
# 300-line size guard fired. The guard's rule is "split on cohesion, not to trim length", and this
# is the cohesive half: one loop over `commands/*.md` enforcing that a command's description and
# argument-hint agree with each other and with what the body actually reads. The other half of the
# old "Token budget" section — the injected BYTE caps — stays in check.sh, because it measures
# documents rather than commands.
#
# Extracted for the same reason as doc-lint.sh / mutate-gate.sh / portability-lint.sh: inline in
# check.sh the SUITE cannot reach it, so its declared mutations had nothing that could redden.
#
# Prints FAIL lines; exit 1 if any fired. Takes no arguments — it globs the shipped commands, the
# same set check.sh used to.
set -uo pipefail
cmd_fail=0
failsec() { cmd_fail=1; }   # local shim: check.sh stamps sections, here we only need the flag
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
    printf '%s\n' "$out"; failsec
  fi

  db="$(printf '%s' "$d" | wc -c | tr -d '[:space:]')"
  if [ "${db:-0}" -gt 140 ]; then echo "  FAIL $(basename "$f") description: ${db}B > 140B (per-session command-list injection)"; failsec; fi

  # A body that reads $ARGUMENTS must declare a hint; a hint must not promise params the body ignores.
  takes_args=0
  # shellcheck disable=SC2016  # the literal string "$ARGUMENTS" is the target; expansion is wrong here
  grep -qF '$ARGUMENTS' "$f" && takes_args=1
  if [ "$takes_args" = 1 ] && [ -z "${hint// /}" ]; then
    echo "  FAIL $(basename "$f") reads \$ARGUMENTS but has no non-empty frontmatter argument-hint: (R75 — params must be visible in the / menu)"; failsec
  fi
  if [ "$takes_args" = 0 ] && [ -n "${hint// /}" ]; then
    echo "  FAIL $(basename "$f") declares argument-hint: but the body never reads \$ARGUMENTS (R75 — the / menu would promise params the command ignores)"; failsec
  fi
  # The hint renders with `truncate-end`, so the tail — usually the second parameter — is what
  # silently disappears. 80 chars is generous.
  if [ "${#hint}" -gt 80 ]; then
    echo "  FAIL $(basename "$f") argument-hint: ${#hint} chars > 80 (truncates in the / input box — name the params, don't document them)"; failsec
  fi

  # description <-> argument-hint AGREEMENT, BOTH directions (R75 amended). The description is what
  # you read while BROWSING the / menu; the hint appears only once the command is already chosen. Two
  # places now state one fact, so neither may name a parameter the other doesn't.
  hp="$(cmd_params "$hint")"; dp="$(cmd_params "$d")"
  if [ -n "${hint// /}" ] && [ -z "$hp" ]; then
    echo "  FAIL $(basename "$f") argument-hint names no parameter in [brackets] — the agreement check cannot see it (R75)"; failsec
  fi
  if [ -z "${hint// /}" ] && [ -n "$dp" ]; then
    echo "  FAIL $(basename "$f") description promises $(echo "$dp" | tr '\n' ' ')but there is no argument-hint (R75 — agree, or say '(no args)')"; failsec
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
      echo "  FAIL $(basename "$f") argument-hint names \`$p\` but the description does not (R75 — the / menu and the autocomplete must agree)"; failsec
    done <<EOF
$hp
EOF
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      case "$(printf '\n%s\n' "$hp")" in *"$(printf '\n%s\n' "$p")"*) continue ;; esac
      echo "  FAIL $(basename "$f") description names \`$p\` but the argument-hint does not (R75 — agreement is both ways)"; failsec
    done <<EOF
$dp
EOF
  fi
done

# ---- DOC vs IMPLEMENTATION: a mode the script implements must be documented (R75) ----
# The checks above prove the description, the argument-hint and the body agree WITH EACH OTHER.
# They cannot catch the failure that actually happened: `autopilot.sh` implemented
# `burndown on|off|status` and all three documents omitted it CONSISTENTLY, so a whole mode — the
# only one that authors its own work — was reachable but invisible, found by accident 2026-08-15.
# Three agreeing documents are not evidence when the thing they agree about is absent from all of
# them; the missing edge was always doc-vs-CODE.
#
# Scoped to autopilot deliberately: it is the one command whose surface is a mode ENUM parsed by a
# top-level `case` in a single script, which is what makes the modes mechanically extractable. A
# generic "every command vs its bin script" check would have to guess at each script's arg parsing,
# and a guess that fails open is the shape this is replacing.
_ap_sh="plugins/companion/bin/autopilot.sh"
_ap_md="plugins/companion/commands/autopilot.md"
if [ -f "$_ap_sh" ] && [ -f "$_ap_md" ]; then
  _ap_doc="$(cat "$_ap_md" 2>/dev/null)"
  # Top-level case arms only (exactly two leading spaces), minus the actions every mode shares.
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    case "$m" in on|off|status|pause|resume) continue ;; esac
    case "$_ap_doc" in *"$m"*) continue ;; esac
    echo "  FAIL autopilot.md never mentions the \`$m\` mode, which $_ap_sh implements (R75 — doc vs CODE, not doc vs doc)"
    cmd_fail=1
  done <<EOF
$(sed -n 's/^  \([a-z][a-z]*\)).*/\1/p' "$_ap_sh" 2>/dev/null)
EOF
fi

# ---- PORTABILITY FLOOR: every command must have somewhere portable to stand (R100, #129) ----
# The plugin's thesis is that CAPABILITY is portable (MCP tools + bin/ scripts, reachable from
# Cursor or any MCP client) while PRESENTATION is native (slash commands, arrow-key menus, the
# status line). A command whose steps name no portable mechanism at all is a capability that exists
# ONLY as Claude-Code prose — exactly the drift this thesis loses to, and the kind of rule this
# session has repeatedly shown gets skipped when it lives only in a document.
#
# WHAT THIS CAN AND CANNOT PROVE, stated plainly because a gate oversold is worse than none. It
# checks that a command NAMES at least one MCP tool or bin/ script. It cannot check that the tool
# named is the RIGHT one, or that the command's real work goes through it — that is semantics, and
# a lint that pretended otherwise would be theatre. This is a FLOOR: no command can silently exist
# with zero portable footing, and a genuinely native one has to SAY SO.
#
# The exemption is deliberate and must carry a reason: `<!-- cli-only: … -->`. /companion:setup
# earns it — it wires the status line into Claude Code's own settings.json, which has no meaning in
# another client. An exemption with no reason is refused, because "cli-only" with no argument is
# how a real leak gets waved through.
_cmd_tools="$(grep -oE '^  "[a-z_]+",' plugins/companion/mcp-server/index.js 2>/dev/null | tr -d ' ",')"
if [ -n "$_cmd_tools" ]; then
  for f in plugins/companion/commands/*.md; do
    [ -f "$f" ] || continue
    _base="$(basename "$f")"
    if grep -qE '<!--[[:space:]]*cli-only:[[:space:]]*[^[:space:]>-]' "$f"; then continue; fi
    if grep -qE '<!--[[:space:]]*cli-only:?[[:space:]]*-->' "$f"; then
      echo "  FAIL $_base carries a cli-only marker with NO reason — say why it cannot be portable"
      cmd_fail=1; continue
    fi
    _hit=0
    for _t in $_cmd_tools; do
      grep -qF "\`$_t\`" "$f" && { _hit=1; break; }
    done
    [ "$_hit" -eq 1 ] || grep -qE '`[a-z][a-z-]*\.sh`|`bin/' "$f" && _hit=1
    if [ "$_hit" -ne 1 ]; then
      echo "  FAIL $_base names no MCP tool and no bin/ script — its capability is reachable only from Claude Code. Route it through a portable mechanism, or mark it <!-- cli-only: <reason> -->"
      cmd_fail=1
    fi
  done
else
  echo "  FAIL portability floor: derived NO MCP tool names — the check would pass vacuously"
  cmd_fail=1
fi

[ "$cmd_fail" -eq 0 ] || exit 1
exit 0
