#!/usr/bin/env bash
# PreToolUse[Write|Edit|NotebookEdit] — the ONE enforced content gate: block a write that would
# land a hardcoded credential before it reaches disk. Native permissions scan bash *commands*, not
# file *content*, and a committed key is irreversible — so this earns a real block (exit 2). Covers
# every content-writing tool: Write/Edit (.content/.new_string) AND NotebookEdit (.new_source) — a
# tool the gate must not leave a hole for (R43).
# Everything else the companion does is steering prose (STEERING.md), never a block.
# Best-effort: any parse issue fails OPEN (allow). Disable with CLAUDE_COMPANION_SECSCAN=0.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
[ "${CLAUDE_COMPANION_SECSCAN:-1}" = "0" ] && exit 0

in="$(cat 2>/dev/null || true)"; [ -n "$in" ] || exit 0
# ONE jq for both fields — this used to be THREE (content, file_path, then file_path AGAIN), on a
# hook that blocks EVERY Write/Edit (R81: 57ms/11 spawns per edit, ~1.2s on a 20-edit turn).
# Path on the first line, content after it: content may contain anything including newlines, so it
# has to come last and be taken verbatim. A path containing a newline was never supported here.
# `tostring` is LOAD-BEARING, not tidiness: `+` THROWS on a non-string, jq then emits nothing, and
# the gate exited 0 — a real credential straight through. NotebookEdit hands `.new_source` as an
# ARRAY of lines, which is exactly that case, and it is the tool R43 added this gate to cover.
# Measured before the fix: {"new_source":["AKIA…"]} → old exit 2 (blocked), new exit 0 (allowed).
rec="$(printf '%s' "$in" | jq -r '((.tool_input.file_path // "") | tostring) + "\n" +
  ((.tool_input.content // .tool_input.new_string // .tool_input.new_source // "") | tostring)' 2>/dev/null || true)"
# Split on the FIRST newline only if there IS one. `$( )` strips the trailing newline, so an empty
# content left `rec` with no separator at all and `${rec#*$'\n'}` returned the PATH unchanged —
# which the scanner then read as content. Measured: an Edit clearing text under a directory named
# /tmp/AKIA…/ was BLOCKED (exit 2), a false block breaking the triggering action (R7/R68) in the one
# gate whose whole doctrine is "false blocks are ~0", and it made the empty-content exit below dead.
case "$rec" in
  *$'\n'*) fp="${rec%%$'\n'*}"; content="${rec#*$'\n'}" ;;
  *)       fp="$rec";           content="" ;;
esac
path="${fp:-the file}"
[ -n "$content" ] || exit 0

# Per-repo `secret` toggle (R50) — inline read, NO lib source: this gate stays self-contained so a
# broken dependency can never make it fail open. Fail-safe: only an explicit `secret=off` in THIS
# repo's feature file disables it; any read error leaves the gate active. Keep path/encoding in sync
# with lib companion_feature_file. (Global CLAUDE_COMPANION_SECSCAN=0 above still wins for CI.)
# Checked LAZILY — only when this gate is about to act. It previously cost 4 spawns (dirname, git,
# sed, grep) on every single edit to read a flag that is almost never set; deferring it changes the
# ORDER only, never the outcome: a disabled gate still exits 0 silently on exactly the same inputs.
gate_off() {
  [ -n "$fp" ] || return 1
  local gr
  gr="$(git -C "$(dirname "$fp")" rev-parse --show-toplevel 2>/dev/null || true)"
  [ -n "$gr" ] || return 1
  grep -qs '^secret=off$' \
    "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}/features/$(printf '%s' "$gr" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
}

# Prefix-anchored credential shapes (AWS / GitHub / Slack / Stripe / Google / private key),
# plus a placeholder-filtered generic "SECRET = '…'". High precision so false blocks are ~0.
anchored='AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'
generic='(api[_-]?key|secret|password|token)[[:space:]]*[:=][[:space:]]*['"'"'"][A-Za-z0-9_/+.-]{12,}['"'"'"]'
placeholder='(your|example|placeholder|xxx+|<[a-z]|changeme|dummy|redacted|test[_-]?(key|token|secret))'

# Anchored vendor key shapes are near-zero false-positive → BLOCK (exit 2), the one sanctioned
# edit-breaker. The generic NAME="value" heuristic is lower-confidence and would break legitimate
# writes (`password_hint = "remember the dog"`, doc fixtures), so it only WARNS (R32) — blocking
# must fire only on evidence that's virtually never a false positive.
if printf '%s' "$content" | grep -qE "$anchored"; then
  gate_off && exit 0
  echo "BLOCKED: $path contains what looks like a real credential (a recognised key prefix). Move it to an env var or secret store — a committed key is irreversible. (CLAUDE_COMPANION_SECSCAN=0 overrides.)" >&2
  exit 2
fi
if printf '%s' "$content" | grep -qiE "$generic" && ! printf '%s' "$content" | grep -qiE "$placeholder"; then
  gate_off && exit 0
  echo "WARNING (not blocked): $path has a possible hardcoded secret (a name=value literal). If it's real, move it to an env var or secret store — the write proceeds regardless." >&2
fi
exit 0
