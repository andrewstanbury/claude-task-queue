#!/usr/bin/env bash
# contract-guard.sh — PreToolUse[Write|Edit]: refuse an edit that WEAKENS the recorded contract.
# Claude-Code-only by nature (MCP ships no interception primitive, R100), restored 2026-08-22 by
# owner decision after R100/Pass 3 retired it for portability.
#
# WHY IT CAME BACK. R86 says: satisfy the contract, never rewrite it — meeting a requirement is
# ordinary, changing or reversing one is the owner's, so park the delta. That has been prose since
# the retirement, and prose is skippable: I skipped it twice in a single session on this very repo.
# The portability trade was made knowingly; what it cost was the one guarantee that survives an
# author who is confident and wrong.
#
# WHAT IT BLOCKS, and the asymmetry is the whole design:
#   · ANY write to docs/needs.yaml — authoring a NEED is never the model's (R86, explicit). Needs
#     define what "useful" means, so writing your own leaves nothing to measure against.
#   · A wholesale Write to docs/requirements.yaml — a full-file replace is never a considered edit.
#   · An Edit that REMOVES a `- id: R…` entry or a `verified_by` test line. Deleting a requirement,
#     or the test that proves it, is a reversal wearing an edit's clothes.
# It does NOT block ADDING a requirement or a test reference, or editing prose in a note. Additions
# are already gated by dev/trace.sh, which fails a requirement naming no test — so the expensive,
# irreversible direction is the one guarded here, and ordinary contract work is untouched.
#
# FAILS OPEN, deliberately, and this is the opposite of secret-guard's doctrine. A missed contract
# edit costs a requirement that should have been parked — recoverable, visible in the diff, and the
# drift backstop still runs at ship. A false block costs the ability to edit the contract at all,
# which is how a guard gets switched off for good. A credential is irreversible; a yaml line is not.
#
# Per-repo opt-out: `contract=off` (R50). Read INLINE with no lib source — a guard whose dependency
# can break it is a guard that fails in the one state nobody tests.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0

in="$(cat 2>/dev/null || true)"
[ -n "$in" ] || exit 0

# ONE jq for path + both sides of the edit. `tostring` is load-bearing: `+` THROWS on a non-string
# (NotebookEdit hands an ARRAY), jq then emits nothing, and the guard exits 0 having checked nothing.
rec="$(printf '%s' "$in" | jq -r '
  ((.tool_input.file_path // "") | tostring) + "\u001f" +
  ((.tool_input.old_string // "") | tostring) + "\u001f" +
  ((.tool_input.new_string // .tool_input.content // "") | tostring) + "\u001f" +
  ((.tool_name // "") | tostring)' 2>/dev/null || true)"
[ -n "$rec" ] || exit 0
IFS=$'\x1f' read -r fp old new tool <<< "$(printf '%s' "$rec" | tr '\n' '\a')"
old="$(printf '%s' "$old" | tr '\a' '\n')"; new="$(printf '%s' "$new" | tr '\a' '\n')"

case "$fp" in
  */docs/requirements.yaml|docs/requirements.yaml) target=requirements ;;
  */docs/needs.yaml|docs/needs.yaml)               target=needs ;;
  *) exit 0 ;;
esac

# Per-repo opt-out, checked LAZILY — only once this guard is about to act.
_root="$(git -C "$(dirname "$fp")" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -n "$_root" ]; then
  _enc="$(printf '%s' "$_root" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  _ff="${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}/features/$_enc"
  grep -qs '^contract=off$' "$_ff" && exit 0
fi

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}'
  exit 0
}

if [ "$target" = needs ]; then
  deny "REFUSED: docs/needs.yaml is never yours to write (R86). A need defines what \"useful\" MEANS, so authoring your own leaves nothing to measure the work against. Park the proposal as a ❓ with the wording you would use and why, and let the owner decide. Per-repo opt-out: contract=off."
fi

# A wholesale Write to the contract is never a considered edit.
if [ "$tool" = Write ] || [ -z "$old" ]; then
  deny "REFUSED: a whole-file Write to docs/requirements.yaml replaces the recorded contract in one step (R86). Make a targeted Edit that ADDS, or park the delta as a ❓ naming the entry and what you would change. Per-repo opt-out: contract=off."
fi

# `grep -c` PRINTS the count and exits 1 when it is zero, so `|| printf 0` emitted "0\n0" and every
# comparison then errored with "integer expected" — the guard still blocked, but on a broken read.
_count() { local n; n="$(printf '%s' "$1" | grep -cE "$2" 2>/dev/null)" || true
           case "${n:-0}" in ''|*[!0-9]*) printf 0 ;; *) printf '%s' "$n" ;; esac; }
old_ids="$(_count "$old" '^- id: R')";        new_ids="$(_count "$new" '^- id: R')"
old_ver="$(_count "$old" '^    - "')";        new_ver="$(_count "$new" '^    - "')"

if [ "$new_ids" -lt "$old_ids" ]; then
  deny "REFUSED: this edit REMOVES $(( old_ids - new_ids )) requirement entr(y/ies) from docs/requirements.yaml. Deleting a requirement is a reversal, and reversals are the owner's (R86) — park it as a ❓ naming the R-ID, what it currently guarantees, and why it should go. Adding is unaffected. Per-repo opt-out: contract=off."
fi
if [ "$new_ver" -lt "$old_ver" ]; then
  deny "REFUSED: this edit REMOVES $(( old_ver - new_ver )) verified_by test reference(s) from docs/requirements.yaml. A requirement without its test still claims to be guaranteed while nothing checks it — that is the exact shape trace.sh exists to catch. If the test genuinely moved, change the reference in the SAME edit rather than dropping it. Per-repo opt-out: contract=off."
fi
exit 0
