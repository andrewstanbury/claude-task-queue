#!/usr/bin/env bash
# secret-guard.sh — PreToolUse[Write|Edit|NotebookEdit]: refuse a write that would put a real
# credential into a file. Claude-Code-only by nature (MCP ships no interception primitive, R100),
# restored 2026-08-22 by owner decision after R100/Pass 3 retired it for portability.
#
# THIS IS THE ONE GATE THAT FAILS CLOSED, and the asymmetry is deliberate. Everywhere else in this
# plugin a guard that cannot read its input allows the action, because a false block costs more than
# a missed check. Here it is reversed: a committed key is IRREVERSIBLE — rotation, audit, possibly
# disclosure — while a false block costs one retry. So an unreadable payload blocks.
#
# ITS OWN HISTORY IS WHY THE TESTS CAME FIRST. Two measured defects, both found by a devil's-advocate
# pass and both silent:
#   · FAILED OPEN on non-string content. jq's `+` THROWS on an array, jq emitted nothing, the gate
#     exited 0 — and NotebookEdit hands `new_source` as an ARRAY of lines. A real AWS key went
#     straight through the gate added to cover that tool. `tostring` below is load-bearing.
#   · FALSE-BLOCKED an empty edit by scanning the file PATH as content, because `${rec#*\n}`
#     returns the path unchanged when there is no newline to strip.
#
# BLOCK vs WARN. Anchored vendor prefixes (AWS/GitHub/Slack/Stripe/Google/private key) are
# near-zero-false-positive, so they earn the block. The generic `NAME = "value"` heuristic would
# break legitimate writes (`password_hint = "the dog's name"`, doc fixtures), so it only WARNS —
# blocking must fire only on evidence that is virtually never wrong.
#
# Self-contained: no lib source, so a broken dependency can never make a credential gate fail open.
# The pattern below is therefore a COPY of companion_secret_re, and a test asserts the two are
# byte-identical — the copy is allowed, the drift is what is guarded.
set -uo pipefail
[ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && exit 0
command -v jq >/dev/null 2>&1 || exit 0

in="$(cat 2>/dev/null || true)"
[ -n "$in" ] || exit 0

deny() {
  jq -cn --arg r "$1" '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$r}}' 2>/dev/null \
    || printf '%s\n' "$1" >&2
  exit 0
}

# ONE jq for path + content, separated by US (\u001f) rather than a newline: content may contain
# anything, including newlines, and splitting on the first newline is what once handed the PATH back
# as content. `tostring` is the array/object/number fix — without it `+` throws and this emits
# nothing at all.
rec="$(printf '%s' "$in" | jq -r '((.tool_input.file_path // "") | tostring) + "\u001f" +
  ((.tool_input.content // .tool_input.new_string // .tool_input.new_source // "") | tostring)' 2>/dev/null || true)"
if [ -z "$rec" ]; then
  # Could not read the payload at all. FAIL CLOSED — see the header. A gate that cannot see the
  # content must not certify it.
  deny "REFUSED: the credential gate could not read this write's content, so it cannot certify there is no key in it. This gate fails CLOSED on purpose — a committed credential is irreversible. Retry, or set CLAUDE_COMPANION_SECSCAN=0 if you accept the risk."
fi
path="${rec%%$'\x1f'*}"; content="${rec#*$'\x1f'}"
[ "$content" = "$rec" ] && content=""     # no separator ⇒ genuinely empty content, NOT the path
[ -n "$content" ] || exit 0                # an empty edit has nothing to scan

anchored='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
generic='(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_/+.-]{12,}['"'"'"]'
placeholder='(your|example|placeholder|xxx+|<[a-z]|changeme|dummy|redacted|test[_-]?(key|token|secret))'

if printf '%s' "$content" | grep -qE "$anchored"; then
  deny "REFUSED: ${path:-this file} contains what looks like a REAL credential (a recognised vendor key prefix). Move it to an env var or a secret store — a committed key is irreversible, and rotating one is far more expensive than this retry. Override for this session with CLAUDE_COMPANION_SECSCAN=0."
fi
if printf '%s' "$content" | grep -qiE "$generic" && ! printf '%s' "$content" | grep -qiE "$placeholder"; then
  printf 'WARNING (not blocked): %s has a possible hardcoded secret (a name=value literal). If it is real, move it to an env var — the write proceeds regardless.\n' "${path:-this file}" >&2
fi
exit 0
