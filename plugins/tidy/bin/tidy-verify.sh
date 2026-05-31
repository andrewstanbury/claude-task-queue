#!/usr/bin/env bash
# Stop hook — the verification floor. When Claude finishes, if the working tree
# has changes and the project has a discoverable test command, run it; if it
# FAILS, block the stop and feed the failure back so Claude fixes it — nothing is
# "done" until the suite is green. This is the safety net a non-technical owner
# can't produce themselves.
#
# Bounded so it can never loop forever: at most CLAUDE_TIDY_VERIFY_MAX (default 3)
# forced fix cycles per session, then it lets the stop through with a visible
# warning. Disable entirely with CLAUDE_TIDY_CHECKS=0. Best-effort: any internal
# error degrades to "allow the stop".

set -uo pipefail

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tidy.sh
. "$PLUGIN_DIR/lib/tidy.sh"
# shellcheck source=../lib/checks.sh
. "$PLUGIN_DIR/lib/checks.sh"

allow() { exit 0; }                                   # let the stop proceed

[ "${CLAUDE_TIDY_CHECKS:-1}" = "0" ] && allow

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""; sid=""
if [ -n "$input" ]; then
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"

# Resolve the repo root (git top, else walk, else cwd).
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$root" ]; then
  d="$cwd"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/.git" ] && { root="$d"; break; }
    d="$(dirname "$d")"
  done
  [ -n "$root" ] || root="$cwd"
fi

# Only verify when there's something to verify: a dirty working tree. A clean
# repo (or a pure-conversation turn) means no changes → nothing to run.
if git -C "$root" rev-parse >/dev/null 2>&1; then
  [ -z "$(git -C "$root" status --porcelain 2>/dev/null)" ] && allow
fi

cmd="$(tidy_test_command "$root" 2>/dev/null || true)"
[ -n "$cmd" ] || allow                                # no discoverable tests → silent

# Per-session state: the attempt counter and the last-green tree fingerprint.
cdir="$(tidy_log_dir)/verify"
key="$(printf '%s' "${sid:-nosession}" | sed 's:/:-:g')"
cfile="$cdir/$key"
hfile="$cdir/hash-$key"

# Throttle: if the tree is byte-for-byte what it was at the last GREEN verify,
# nothing changed since — skip the (possibly slow) run. (A failed/timeout verify
# clears the fingerprint, so we never skip past red tests.)
cur="$(tidy_tree_hash "$root" 2>/dev/null || true)"
if [ -n "$cur" ] && [ -f "$hfile" ] && [ "$(cat "$hfile" 2>/dev/null || true)" = "$cur" ]; then
  tidy_log verify "skip unchanged"
  allow
fi

out="$(tidy_run_checks "$root" "$cmd" 2>/dev/null)"; rc=$?

if [ "$rc" -eq 0 ]; then
  rm -f "$cfile" 2>/dev/null || true                  # green → reset counter
  if [ -n "$cur" ]; then { mkdir -p "$cdir" 2>/dev/null && printf '%s' "$cur" > "$hfile"; } 2>/dev/null || true; fi
  tidy_log verify "pass cmd=$cmd"
  allow
fi

rm -f "$hfile" 2>/dev/null || true                    # not green → drop the stale pass-fingerprint

if [ "$rc" -eq 124 ]; then                            # timed out — can't verify; don't loop on it
  rm -f "$cfile" 2>/dev/null || true
  tidy_log verify "timeout cmd=$cmd"
  jq -cn --arg m "⚠️ Tests timed out (> ${CLAUDE_TIDY_VERIFY_TIMEOUT:-180}s, \`$cmd\`) — couldn't verify this change; run them manually if needed." \
    '{systemMessage: $m}'
  exit 0
fi

max="${CLAUDE_TIDY_VERIFY_MAX:-3}"
count=0
[ -f "$cfile" ] && count="$(cat "$cfile" 2>/dev/null || printf 0)"
count="${count//[^0-9]/}"; [ -n "$count" ] || count=0

if [ "$count" -ge "$max" ]; then
  rm -f "$cfile" 2>/dev/null || true                  # gave it enough tries
  tidy_log verify "give-up cmd=$cmd attempts=$count"
  jq -cn --arg m "⚠️ Tests are still failing after $count fix attempts ($cmd) — this needs attention before the change is trusted." \
    '{systemMessage: $m}'
  exit 0
fi

{ mkdir -p "$cdir" 2>/dev/null && printf '%s' "$((count + 1))" > "$cfile"; } 2>/dev/null || true
tidy_log verify "block cmd=$cmd attempt=$((count + 1))"
jq -cn --arg r "The project's tests are failing after your change — nothing is done until they're green. Run \`$cmd\`, read the failure, and fix it:"$'\n\n'"$out" \
  '{decision: "block", reason: $r}'
