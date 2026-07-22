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

# R68: redact obvious credentials/PII BEFORE the prompt hits disk — this store is plaintext at
# rest, and a pasted key/SSN must not persist. Anchored, generic patterns only (R9 — the same
# philosophy as secret-guard: vendor-anchored keys + unambiguous shapes, no ecosystem allowlists).
# Portable ERE (no \b — BSD sed lacks it); best-effort: sed failure → keep the original (R7).
red="$(printf '%s' "$prompt" | sed -E \
  -e 's/AKIA[A-Z0-9]{16}/[REDACTED:key]/g' \
  -e 's/-----BEGIN[A-Z ]*PRIVATE KEY-----/[REDACTED:private-key]/g' \
  -e 's/gh[pousr]_[A-Za-z0-9]{20,}/[REDACTED:token]/g' \
  -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/[REDACTED:token]/g' \
  -e 's/sk-[A-Za-z0-9_-]{24,}/[REDACTED:token]/g' \
  -e 's/(^|[^0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}($|[^0-9])/\1[REDACTED:ssn]\2/g' \
  -e 's/(^|[^0-9])[0-9]{4}([- ][0-9]{4}){3}($|[^0-9])/\1[REDACTED:card]\2/g' \
  2>/dev/null)" || red=""
[ -n "$red" ] && prompt="$red"

# R68: bounded store — rotate at ~1MB, keep exactly one previous generation (the R58 follow-up:
# an unbounded plaintext prompt log is a liability, not a feature). Failure → append anyway (R7).
f="$dir/prompts.jsonl"
sz=0
[ -f "$f" ] && sz="$(wc -c < "$f" 2>/dev/null || echo 0)"
case "$sz" in ''|*[!0-9]*) sz=0 ;; esac
[ "$sz" -gt 1048576 ] && { mv -f "$f" "$f.1" 2>/dev/null || true; }
# One JSONL line, appended atomically enough for a single-writer local sink. Store the repo root
# too so a reader can confirm scope without re-decoding the dirname. `date` may be unavailable in
# some minimal shells — degrade to an empty ts rather than failing the capture.
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
jq -cn --arg ts "$ts" --arg root "$root" --arg p "$prompt" \
  '{ts:$ts, root:$root, prompt:$p}' >> "$dir/prompts.jsonl" 2>/dev/null || true
exit 0
