#!/usr/bin/env bash
# UserPromptSubmit — capture the raw prompt (R58, the living-contract producer).
#
# The one thing a document can't do: durably record every prompt as it arrives, so the
# living-contract reflex (STEERING) and `/companion:cover` have real material to reason over —
# which requests changed what the user sees/does (UX) or a quality attribute (NFR). The
# *classification* is judgment and stays in STEERING; this hook only banks the raw text.
#
# HARD CONSTRAINT (N1 — token efficiency): this hook is a WRITE-ONLY sink. It prints NOTHING to
# stdout (no additionalContext), so it never costs a runtime token — the capture is free until
# something reads it on demand. Best-effort (R7): empty / garbage / truncated / huge / multibyte
# input must never break the prompt submission — every failure path exits 0 silently.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)" || exit 0
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh" 2>/dev/null || exit 0

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
prompt="$(printf '%s' "$in" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0                      # nothing to capture (garbage/empty stdin) → no-op

root="$(companion_root "$cwd")"
dir="$(companion_captures_dir "$root")"
mkdir -p "$dir" 2>/dev/null || exit 0
# One JSONL line, appended atomically enough for a single-writer local sink. Store the repo root
# too so a reader can confirm scope without re-decoding the dirname. `date` may be unavailable in
# some minimal shells — degrade to an empty ts rather than failing the capture.
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
jq -cn --arg ts "$ts" --arg root "$root" --arg p "$prompt" \
  '{ts:$ts, root:$root, prompt:$p}' >> "$dir/prompts.jsonl" 2>/dev/null || true
exit 0
