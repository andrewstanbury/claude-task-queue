#!/usr/bin/env bash
# SessionStart — the things a document can't do itself:
#   1. Put STEERING.md (the working agreement) in context once per session.
#   2. Re-surface THIS repo's still-open tasks from an earlier session (cross-session resume).
#   3. Surface the repo's own LESSONS.md (accumulated gotchas) if it has one (R30·d7).
# The companion owns its task store (no native tasks); each session dir is stamped with its
# repo root (`.root`), so scoping needs no native transcript. `/companion:resume` re-runs the
# resume half on demand. Read-only, best-effort: any failure injects nothing, never breaks startup.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"; while [ -L "$SELF" ]; do SELF="$(readlink "$SELF")"; done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
src="$(printf '%s' "$in" | jq -r '.source // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"

# SessionStart fires on startup/resume AND after a context compaction (source=compact) — so this
# hook IS the post-compaction re-anchor (R30·d2). On compact it re-injects the live queue (each
# task's done-when) + LESSONS — the real cross-compaction memory — but NOT the whole ~2.4k-token
# STEERING (R32): the agreement from session start still applies and the summarizer largely
# preserves it, so re-pasting static prose every compaction was the biggest repeatable token waste.
if [ "$src" = "compact" ]; then
  msg="Your context was just compacted. Re-anchor from your LIVE task queue (each task's done-when is its acceptance test) and this repo's lessons below — resume from the queue, not from memory. The working agreement injected at session start still applies (not re-pasted here, to save tokens)."$'\n\n'
else
  msg="Read the working agreement below — it governs how you queue, decide, and keep this repo clean for the whole session."$'\n\n'
  [ -f "$PLUGIN_DIR/STEERING.md" ] && msg="$msg$(cat "$PLUGIN_DIR/STEERING.md")"
fi
carry="$(companion_open_tasks "$root")"
[ -n "$carry" ] && msg="$msg"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"

# This repo's accumulated gotchas (R30·d7) — model-maintained; first match wins.
for lf in "$root/docs/LESSONS.md" "$root/LESSONS.md" "$root/.companion/LESSONS.md"; do
  [ -f "$lf" ] || continue
  msg="$msg"$'\n\n'"── This repo's LESSONS (accumulated gotchas — heed them, and append new ones as you learn them) ──"$'\n'"$(cat "$lf")"
  break
done

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
