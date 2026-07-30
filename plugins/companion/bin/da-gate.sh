#!/usr/bin/env bash
# da-gate — the R78 devil's-advocate gate, extracted from `ship.sh` when it reached its 300-line
# cap (same move as ci-watch.sh / doc-lint.sh: extracted so the SUITE can exercise it directly).
#
#   da-gate.sh note "<the --da value>"     validate the finding; exit 2 on a rubber stamp
#   da-gate.sh match                       changed paths on stdin -> critical ones on stdout
#                                          exit 0 none · 1 some (printed) · 2 unusable config
#
# It cannot verify that a devil's-advocate pass actually HAPPENED — no shell check can. It makes
# skipping deliberate and auditable, which is the honest ceiling.
set -uo pipefail

# Deliberately NOT overridable by env. An earlier draft honoured $DA_PATHS_FILE, which made
# `DA_PATHS_FILE=/dev/null ship.sh land` a silent, undocumented kill switch leaving NO commit
# trailer — the exact opposite of the "skipping is deliberate and auditable" ceiling. Tests cd
# into a fixture repo instead. Path is relative: ship.sh cds to the repo root before calling.
PATHS_FILE=".companion/da-paths"

case "${1:-}" in
  note)
    da="${2-}"
    case "$da" in -*) printf 'da-gate: --da needs a finding, not a flag (%s)\n' "$da" >&2; exit 2 ;; esac
    [ -n "${da// /}" ] || { printf 'da-gate: --da needs a non-empty finding\n' >&2; exit 2; }
    # The finding is appended verbatim as a `Devil-advocate:` commit trailer, so an embedded
    # newline lets a caller forge a second trailer (Signed-off-by:, Co-Authored-By:). One line.
    case "$da" in *$'\n'*|*$'\r'*) printf 'da-gate: --da must be a single line (no newlines)\n' >&2; exit 2 ;; esac
    # RUBBER-STAMP GUARD. One word was the cheapest way to defeat the whole gate, and a stamp is
    # WORSE than no gate: it launders the decision instead of testing it (R53 anti-laundering).
    # A pass that genuinely found nothing must still say WHAT it examined. Fabricable by design —
    # this raises the floor, it does not lock the door.
    # `stamp` (ASCII-folded) is ONLY for the denylist compare. LENGTH is measured on `trimmed`,
    # which keeps non-ASCII: `tr -cd '[:alnum:] '` is byte-oriented in every locale, so a
    # substantive Japanese or Russian finding folded to "" and was refused as 0 chars. R1: this
    # ships to a wide audience, and "write your finding in English" is not a requirement we have.
    trimmed="$(printf '%s' "$da" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    stamp="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:] ' | tr -s ' ' \
            | sed -e 's/^ //' -e 's/ $//')"
    norm="$stamp"
    case "$norm" in
      clean|none|na|"n a"|ok|okay|nothing|fine|good|"all clear"|"no findings"|"no issues"|"looks good"|lgtm)
        printf 'da-gate: --da "%s" is a rubber stamp, not a finding. Say what the pass EXAMINED and what it concluded, e.g. --da "attacked the parser on empty/array input and the delete path; no defect found" (R78).\n' "$da" >&2
        exit 2 ;;
    esac
    [ "${#trimmed}" -ge 24 ] || {
      printf 'da-gate: --da needs a substantive finding (got %s chars). Name what was attacked and what came of it (R78).\n' "${#trimmed}" >&2
      exit 2; }
    exit 0 ;;

  match)
    [ -s "$PATHS_FILE" ] || exit 0                        # no file ⇒ no gate (a stranger's repo)
    # STRIP COMMENTS AND BLANKS FIRST. `grep -Ef` compiles EVERY line as a regex, so a bare
    # parenthesis in a prose comment is an INVALID regex — grep exits 2, the match comes back
    # empty, and the gate SILENTLY DOES NOT FIRE. Measured on this repo's own file while widening
    # it: a comment reading "(registering a hook)" disabled R78 entirely, with no warning.
    # This grep's STATUS is checked too. Discarding it was a fail-OPEN: grep exits 2 on an
    # unreadable file or a directory, `re` came back empty, and the gate cheerfully reported "no
    # critical paths" — measured, a bin/ change merged to main with no --da and nothing on stderr,
    # while this file's own docs claimed it failed closed.
    re="$(grep -v -e '^[[:space:]]*#' -e '^[[:space:]]*$' "$PATHS_FILE" 2>/dev/null)"; rc=$?
    [ "$rc" -ge 2 ] && exit 2
    # Strip CR. A Windows/WSL clone with core.autocrlf=true (this repo ships no .gitattributes)
    # turns every pattern into `…/\r`, which matches nothing — the ENTIRE gate silently off. This
    # is the highest-probability real-world instance of the fail-open class, and da-paths is a file
    # strangers are told to author (R1/R9).
    re="${re//$'\r'/}"
    [ -n "$re" ] && [ -n "${re//[[:space:]]/}" ] || exit 0   # comments only ⇒ no patterns ⇒ no gate
    # `$?` on the assignment, NOT PIPESTATUS: the pipeline runs in a command substitution, so the
    # parent shell never sees its PIPESTATUS and the fail-closed branch silently never fired
    # (measured: an invalid da-paths shipped at exit 0). pipefail is set above, so grep's error
    # surfaces here. A gate that fails OPEN on its own config is worse than no gate.
    hits="$(grep -E "$re" 2>/dev/null | sort -u)"; rc=$?
    [ "$rc" -ge 2 ] && exit 2
    [ -n "$hits" ] || exit 0
    printf '%s\n' "$hits"
    exit 1 ;;

  *) printf 'usage: da-gate.sh note "<finding>" | da-gate.sh match < changed-paths\n' >&2; exit 2 ;;
esac
