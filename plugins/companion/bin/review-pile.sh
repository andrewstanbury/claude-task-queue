#!/usr/bin/env bash
# review-pile.sh — THE PILE THAT NEEDS THE OWNER, classified. Extracted from commands/review.md
# 2026-08-22 so a non-Claude client can reach the capability at all (adr R100's portability thesis).
#
# WHAT MOVED AND WHAT DID NOT. `/companion:review` was prose + logic in one file. The LOGIC is
# "which items need the owner, and what shape is each one" — that is here, and any MCP client can
# call it. The PRESENTATION is the arrow-key menu, which is Claude-Code-only and stays in the
# command. Same split the owner asked for: capability portable, interface native.
#
# Classification drives how a caller must ask, and getting it wrong is the failure this encodes:
#   blocked      ⏳ an owner ACTION in the world. Not a recommendation to accept — never sweep it.
#   decompose    ❓ carrying `decompose:` (R65). Carries QUESTIONS, not options: interview, do not
#                offer a menu, because options invented without the missing context are premature.
#   options-rec  ❓ carrying `rec:` — a real pick exists, so it is eligible for a batch accept.
#   options      ❓ with no `rec:` — a menu is owed, and a batch accept would be a rubber stamp.
#
# Output is one TSV row per item: <class>\t<id>\t<subject>. Empty output means the pile is clear,
# which is a clean no-op and the common case — never a reason to manufacture questions.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "review-pile: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "${REVIEW_ROOT:-$PWD}")"
f=""; declare -a files=()
while IFS= read -r -d '' f; do [ -n "$f" ] && files+=("$f"); done < <(companion_task_files "$root")
[ "${#files[@]}" -gt 0 ] || exit 0

# One jq over the scoped set — same batch-then-fallback shape the renderer uses, because jq aborts
# at the first unparseable file and one torn write must not empty the owner's decision pile.
PROG='select(.status=="pending" or .status=="in_progress")
  | ((.subject//"") | sub("^\\s+";"")) as $s
  | select(($s|startswith("❓")) or ($s|startswith("⏳")))
  | (if   ($s|startswith("⏳"))            then "blocked"
     elif ($s|contains("decompose:"))     then "decompose"
     elif ($s|contains("rec:"))           then "options-rec"
     else                                      "options" end) as $c
  | $c + "\t" + (.id|tostring) + "\t" + ($s|gsub("[\t\n\r]";" "))'
if out="$(jq -r "$PROG" "${files[@]}" 2>/dev/null)"; then
  [ -n "$out" ] && printf '%s\n' "$out"
  exit 0
fi
for f in "${files[@]}"; do
  [ -f "$f" ] || continue
  jq -r "$PROG" "$f" 2>/dev/null || true
done
