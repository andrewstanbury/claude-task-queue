#!/usr/bin/env bash
# PreToolUse[AskUserQuestion] — while autopilot is ON, DENY the question. Autopilot means keep
# going without stopping (R36); asking = stopping, so the model must decide-if-reversible-mechanic
# or PARK the decision/design choice as a `❓` task instead. This makes autopilot's "don't stop to
# ask" mechanical, not advisory. Silent (allow) when autopilot is off. Best-effort: degrades to allow.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(companion_root "$cwd")"
companion_autopilot_on "$root" || exit 0

# Same denial either way (asking = stopping), but the GUIDANCE differs by mode (R59). Default:
# park every decision. Decisive: auto-pick your recommended option for REVERSIBLE decisions
# (taste included — overrides R33) and record it; park/block ONLY the irreversible-critical.
if companion_decisive_on "$root"; then
  reason="Autopilot is ON + DECISIVE mode (R59) — keep going, do not stop to ask. For any REVERSIBLE decision, incl. design/wording/direction: DECIDE it yourself — pick your own recommended option (the one you'd have marked (Recommended)), RECORD it with a breadcrumb (\`tq note <id> \"decided: <pick> + one-line why\"\`, or a fresh \`tq add\` for the chosen task), and proceed. Do NOT park a reversible decision — the audit trail (your recorded picks) is the safety net, walked later by /companion:review. PARK (❓) or BLOCK (⏳) ONLY when the action is IRREVERSIBLE, externally-binding, or data-destructive (a push, a delete, spending money, anything you can't cleanly undo) — those still carry the FULL option payload in the subject: \`tq add \"❓ [parked] <choice> — options: A) …(cost) B) …(cost); rec:<pick>+why\"\` — and, because in THIS mode a park is irreversible by definition, it must NEVER carry the \`rev:\` marker (R77); that marker is what sweep mode acts on, and an irreversible park must stay for the owner. When unsure whether it's reversible, treat it as irreversible and park."
else
  reason="Autopilot is ON — keep going, do not stop to ask (asking = stopping; the owner may be present and adding tasks). Decide it yourself ONLY if it is a reversible, taste-neutral mechanic (record the call). A visual/design/direction/wording choice belongs to the owner — PARK it even if it is reversible (do NOT pick for them). Park with the FULL payload you would have asked live, not a thin guess — it all goes in the subject (the parked-pile review, /companion:review, reads it back via \`tq list\`): \`tq add \"❓ [parked] rev: <the choice> — options: A) … (cost) B) … (cost) C) … (cost); rec: <your pick> + why\"\` (or \`⏳ [blocked] <owner-only action>\`), then move on. The \`rev:\` marker is LOAD-BEARING (R77): it means *reversible, but the call is yours* — a taste/design/wording/direction choice you could cleanly undo. Write it ONLY when that is true. An IRREVERSIBLE, externally-binding or destructive park (a push, a delete, spending money) must NOT carry \`rev:\` — omit it, or use \`⏳\`. Sweep mode acts on \`rev:\` parks and nothing else, so a wrong marker is the one mistake that lets an unattended run decide something it must not. A \`❓\` with a one-line guess instead of the options makes the later review a rubber-stamp — carry the 2–4 options + each cost + your recommendation. The owner reviews parked items whenever they check in."
fi

# AUTO-PARK THE INTERCEPTED QUESTION (owner-asked 2026-08-01). Denying alone made the block a dead
# end: the guard is enforced, but the parking that is supposed to follow it was advisory — exactly
# the advisory-vs-enforced gap this plugin exists to close. The hook already HAS the payload, so it
# can write a real park carrying the actual options rather than leaving a thin guess to be
# reconstructed from memory.
#
# NEVER writes the `rev:` marker. `rev:` means "reversible, but the call is yours" and is what
# sweep mode acts on (R77); this hook cannot know whether a choice is reversible, and a wrong
# marker is the single mistake that lets an unattended run decide something it must not. Omitting
# it means the park is treated as irreversible and is never swept — the safe direction.
#
# Best-effort throughout: if anything here fails the denial still goes out unchanged. A guard that
# breaks the session because its convenience feature broke is worse than one that just denies.
parked_id=""
sid="$(printf '%s' "$in" | jq -r '.session_id // empty' 2>/dev/null || true)"
subject="$(printf '%s' "$in" | jq -r '
  (.tool_input.questions // []) | if length == 0 then empty else
  ("❓ [parked] " + (.[0].question // "a decision"))
  + " — options: " + ([ .[0].options[]? | (.label // "") + (if (.description//"")!="" then " (" + (.description|.[0:80]) + ")" else "" end) ] | join(" · "))
  + "; rec: " + ((.[0].options[0].label // "the first option"))
  + (if length > 1 then " [+" + ((length-1)|tostring) + " more question(s) in the same ask]" else "" end)
  end' 2>/dev/null | head -c 900 | tr -d '\n\r' || true)"
if [ -n "$subject" ] && [ -n "$sid" ]; then
  # Do not stack duplicates: a retried question would otherwise park itself again on every attempt.
  # DEDUP BY RAW GREP, not `tq list`. `list` renders every task through jq, which put an O(store)
  # jq pass on a hook that fires on every question — measured 2825ms against a 400-task store,
  # breaching the R81 stall cap of 1500ms. A fixed-string grep over the session's own JSON files
  # is the same answer for ~1/100th of the cost, and stays inside this session's directory.
  _store="$(companion_tasks_dir)/$sid"
  # ABSOLUTE path to tq, resolved BEFORE the cd. $SELF is relative whenever the hook is invoked by a
  # relative path, so `$(dirname "$SELF")/tq` silently stopped resolving the moment this started
  # cd-ing into the payload's repo — tq never ran, no task was written, and the model was still told
  # its question had been parked. A silent no-op behind a success message is the worst outcome here.
  _tq="$(cd "$(dirname "$SELF")" 2>/dev/null && pwd)/tq"
  _dup=0; grep -qsF "${subject:0:120}" "$_store"/*.json 2>/dev/null && _dup=1
  if [ "$_dup" -eq 0 ] && [ -x "$_tq" ]; then
    parked_id="$( ( cd "$root" 2>/dev/null && CLAUDE_COMPANION_SESSION_ID="$sid" "$_tq" add "$subject" 2>/dev/null ) \
                 | sed -n 's/^added #\([0-9][0-9]*\).*/\1/p' | head -1 || true)"
  fi
fi
if [ -z "$parked_id" ] && [ "${_dup:-0}" -eq 1 ]; then
  # ALREADY in the queue from an earlier denial. Saying nothing sent the model off to park it a
  # second time by hand, which is the duplicate the dedup exists to prevent.
  reason="ALREADY PARKED — this exact question is already on the queue as a ❓ from an earlier attempt. Do NOT re-ask and do NOT add it again. Move on to other work; /companion:review will walk it. ${reason}"
fi
if [ -n "$parked_id" ]; then
  reason="ALREADY PARKED FOR YOU as task #${parked_id} — the question you just asked has been written to the queue with its options and your recommendation, so nothing is lost and you do not need to re-park it. Do NOT re-ask and do NOT re-add it. Keep going with the rest of the work; /companion:review will walk it (it asks the whole pile at once and resumes autopilot afterwards, R83). NOTE: the auto-park deliberately omits the \`rev:\` marker, so it is treated as IRREVERSIBLE and will never be swept — if this choice is in fact reversible and safe for sweep mode to apply, re-add it yourself with \`rev:\`. ${reason}"
fi

jq -cn --arg r "$reason" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
