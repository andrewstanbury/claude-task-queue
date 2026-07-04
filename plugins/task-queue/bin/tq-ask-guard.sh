#!/usr/bin/env bash
# PreToolUse(AskUserQuestion) guard — make away/solo's "never ask" MECHANICAL.
#
# Away-mode tells the model not to block on an absent owner, but on its own that's
# advisory: the model can still call AskUserQuestion and pause the whole session
# waiting for someone who isn't at the keyboard. This hook makes it real — while
# away is ON for the repo, it DENIES the AskUserQuestion call and feeds back
# "decide-if-reversible, else PARK as ❓", so the queue keeps moving. Silent no-op
# when away is OFF (normal asking works) or when disabled (CLAUDE_TQ_AWAY_ASK_GUARD=0).
#
# Best-effort: any internal error degrades to "allow" — a companion must never break
# the action it hooks. Wired by hooks/hooks.json as a PreToolUse matcher.

set -uo pipefail
allow() { exit 0; }                                   # let the AskUserQuestion proceed
[ "${CLAUDE_TQ_AWAY_ASK_GUARD:-1}" = "0" ] && allow

# Resolve symlinks so a relocated/PATH-installed entrypoint still finds lib/.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"
set +e   # tasks.sh enables `set -e`; this hook is best-effort — never break the call.

input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
cwd=""
[ -n "$input" ] && cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"

tq_is_away "$root" || allow                           # owner present → asking is fine

jq -cn --arg r "🚶 Away-mode is ON — the owner is away and can't answer, so this question is blocked to keep the queue moving. Don't ask. Instead: if the choice is REVERSIBLE and low-risk, pick the best option yourself (say which, in one line) and proceed; if it GENUINELY needs the owner — a design/visual call, an ambiguous fork, or anything irreversible/externally-binding — PARK it as a '❓ [parked] <the question — with your recommendation>' task and move on to other queue work. It re-surfaces for the owner when they return." \
  '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
