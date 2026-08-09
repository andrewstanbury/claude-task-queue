#!/usr/bin/env bash
# SessionStart — reinstated in R100/Pass 6, owner-decided (docs/adr/README.md R105): the owner
# watched a model ignore or subvert plugin instructions it never actually had guaranteed in
# context, and picked "guaranteed context delivery" back over "advisory only, on request." This
# hook is the one thing a document can't do itself — put it in context whether or not the model
# remembers to ask for it.
#
# Content is NOT duplicated here: companion_resume_report (lib/resume-report.sh) is the single
# source of truth, shared with resume.sh's manual pull, so the two paths cannot drift on what
# "the resume content" means. This hook adds only what's specific to being a HOOK: the JSON
# envelope, the compact-vs-fresh-start branch, and — deliberately — no autopilot-clearing side
# effect. An automatic session start must never silently disarm a persisted "keep draining" intent
# (only an owner-invoked /companion:resume triages that away); a compaction mid-run doing so would
# break the exact unattended workflow autopilot exists for.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"
# shellcheck source=../lib/resume-report.sh
. "$PLUGIN_DIR/lib/resume-report.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
src="$(printf '%s' "$in" | jq -r '.source // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"

# SessionStart fires on startup/resume AND after a context compaction (source=compact) — so this
# hook is also the post-compaction re-anchor. On compact, re-inject the live queue (each task's
# done-when is its own acceptance test) + LESSONS, but NOT the full STEERING core (~8KB, R69): the
# agreement from session start still applies and the summarizer largely preserves it, so re-pasting
# static prose every compaction is the single biggest repeatable token waste this hook could cause.
# What IS re-stated inline is the POSTURE — recommendation-first options AND the unconditional
# closing-honesty rule — because that is the half that decays first under summarization.
if [ "$src" = "compact" ]; then
  if companion_feature_off steering "$root"; then
    msg="Your context was just compacted. Re-anchor from your LIVE task queue (each task's done-when is its acceptance test) and this repo's lessons below — resume from the queue, not from memory."
  else
    msg="Your context was just compacted. Re-anchor from your LIVE task queue (each task's done-when is its acceptance test) and this repo's lessons below — resume from the queue, not from memory. The working agreement injected at session start still applies (not re-pasted here, to save tokens) — including its core move, which the summarizer must not drop: a decision-shaped request (choose / redesign / compare / evaluate / \"what do you recommend\") is owed recommendation-first options — 2-4 genuinely different, each with its cost, your pick first and marked, plus the brutal-honest read — never a flat one-opinion answer (R49). And the half that decays first: the honest read belongs ON the recommendation — its cost, what you would regret, what argues against it — never as a verdict tacked onto every reply, and never aimed at the owner: if they supplied the fix, that is YOUR miss (R80b)."
  fi
else
  # Fresh session start: the full STEERING core — no autopilot clear (see header comment).
  was_armed=0; companion_autopilot_on "$root" && was_armed=1
  steering_block="$(companion_resume_steering "$root" "$PLUGIN_DIR" "$was_armed")"
  # steering=off (R50): NO preamble either — telling the model to "read the working agreement
  # below" when there IS none below (steering_block empty) is exactly the printed-surface
  # carelessness R69 exists to prevent.
  if [ -n "$steering_block" ]; then
    msg="Read the working agreement below — it governs how you queue, decide, and keep this repo clean for the whole session."$'\n\n'"$steering_block"
  else
    msg=""
  fi
fi
# Everything past this point is IDENTICAL for compact and fresh (R93's own reasoning: a
# compaction is a state clear, exactly what "arrives unasked" exists to survive) — carried tasks,
# the version-lag warning, LESSONS, out-of-band changes, and rework, all cheap, all zero-cost when
# empty. Only the STEERING-core-vs-short-message decision above differs by source.
msg="$msg$(companion_resume_report "$root" "$PLUGIN_DIR")"

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
