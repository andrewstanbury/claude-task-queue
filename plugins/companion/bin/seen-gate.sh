#!/usr/bin/env bash
# seen-gate — validates `tq done --seen "<evidence>"`: what was actually EXERCISED, and in which
# running thing. Extracted into its own file for the same reason da-gate.sh was — so the suite can
# drive it directly, and so `tq` stays under its 300-line cap.
#
#   seen-gate.sh check "<the --seen value>"   exit 0 accepted · 2 rubber stamp (with a reason)
#
# WHY THIS EXISTS. The recorded failure (owner, 2026-08-10) is an agent declaring completion at the
# boundary of what it could observe from a shell, when the owner's experience of the work lived one
# layer further out: a fix written, tested, committed and reported done that was never deployed; a
# route move proved by a typecheck that cannot see string-typed router paths; an approval gate whose
# refuse path was proved and whose accept path was declared untestable while `pty.openpty()` was
# available the whole time; and a bundle server three days stale while code and API were inspected
# instead. Every check run was real. None was the check that mattered.
#
# NAMED LIMIT, stated where it is enforced. This cannot verify that anything was observed — no shell
# check can, which is the same ceiling R28 names and da-gate.sh states about its own pass. It is
# FABRICABLE BY DESIGN: it raises the floor, it does not lock the door. What it actually buys is
# that the claim must be WRITTEN, in the owner's terms, at the moment of closing — where the gap
# between "tests pass" and "I opened it" becomes legible to a human reading `tq list`.
#
# GENERIC (R9). The denylist below is plain-English SELF-REFERENTIAL COMPLETION TALK — "it builds",
# "tests pass" — never an ecosystem, language or framework allowlist. Nothing here knows what a
# bundle server, a simulator or a staging URL is; recognising those is the model's job, not a
# hardcoded table's. That is also this gate's honest weakness: it can tell that evidence is thin,
# never that it is about the right layer.
set -uo pipefail

case "${1:-}" in
  check)
    seen="${2-}"
    case "$seen" in -*) printf 'seen-gate: --seen needs evidence, not a flag (%s)\n' "$seen" >&2; exit 2 ;; esac
    [ -n "${seen// /}" ] || { printf 'seen-gate: --seen needs a non-empty observation\n' >&2; exit 2; }
    # One line. The value is echoed back inside `tq list`/`report` output, which is line-oriented;
    # an embedded newline lets a value forge what looks like a second task row. Same reasoning as
    # da-gate.sh's commit-trailer guard, different consumer.
    case "$seen" in *$'\n'*|*$'\r'*)
      printf 'seen-gate: --seen must be a single line (no newlines)\n' >&2; exit 2 ;; esac

    # `stamp` (ASCII-folded) is ONLY for the denylist compare. LENGTH is measured on `trimmed`,
    # which keeps non-ASCII. This is da-gate.sh's recorded bug, not a hypothetical: `tr -cd
    # '[:alnum:] '` is byte-oriented in every locale, so a substantive Japanese or Russian
    # observation folds to "" and would be refused as 0 chars. R1 — this ships to a wide audience,
    # and "describe what you saw in English" is not a requirement we have.
    trimmed="$(printf '%s' "$seen" | tr -s '[:space:]' ' ' | sed -e 's/^ //' -e 's/ $//')"
    stamp="$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]' | tr -cd '[:alnum:] ' | tr -s ' ' \
            | sed -e 's/^ //' -e 's/ $//')"

    # SELF-REFERENTIAL COMPLETION TALK — the agent reporting on its own layer instead of the
    # owner's. Every one of these is a TRUE statement that answers the wrong question.
    case "$stamp" in
      done|ok|okay|fine|good|yes|na|"n a"|none|works|"it works"|working|verified|checked|tested|\
      passes|passed|"tests pass"|"test passes"|"tests passing"|"all tests pass"|"the tests pass"|\
      compiles|"it compiles"|builds|"it builds"|"build passes"|typechecks|"type checks"|\
      "typecheck passes"|lint|"lint passes"|green|"ci green"|"all green"|"ci passes"|lgtm|\
      committed|"committed it"|pushed|"merged it"|merged|shipped|"no errors"|"no issues")
        printf 'seen-gate: --seen "%s" reports YOUR layer, not the owner'"'"'s. Name what you EXERCISED and in WHICH RUNNING THING, e.g. --seen "opened the review screen in Expo Go on the device; the media thumbnails loaded". A passing test is not an observation of the deployed thing.\n' "$seen" >&2
        exit 2 ;;
    esac

    # A floor, matched to da-gate.sh's. Long enough that "ran it" cannot pass, short enough that a
    # genuine one-clause observation is not bullied into padding.
    [ "${#trimmed}" -ge 24 ] || {
      printf 'seen-gate: --seen needs a substantive observation (got %s chars). Say what you exercised and where it was running (R28 ceiling: this gate cannot check that you did — it only makes the claim visible).\n' "${#trimmed}" >&2
      exit 2; }
    exit 0 ;;

  *)
    printf 'seen-gate: usage: seen-gate.sh check "<what was exercised, in which running thing>"\n' >&2
    exit 2 ;;
esac
