#!/usr/bin/env bash
# SessionStart hook — prime the session's task queue. The whole plugin.
#
# Does two cheap things ONCE per session (no per-prompt cost):
#   1. Policy — tell the model to treat its native task list as the live work
#      queue: capture described work with TaskCreate, work it in dependency
#      order, batch related tasks, stay inline, advance without draining. Said
#      once here, this governs the whole session — far cheaper than re-injecting
#      every turn, and Claude Code's own task nudges reinforce it.
#   2. Resume — surface this repo's still-open tasks from earlier sessions so the
#      model re-adopts them into the (otherwise empty) native list.
#
# Read-only: it never writes the native store. The model owns the tasks; we only
# read them and state the policy. Claude Code renders the resulting task list as
# the visible queue in the CLI — we add no UI of our own.
#
# Wired by hooks/hooks.json on SessionStart; invoked as
# "${CLAUDE_PLUGIN_ROOT}/bin/tq-resume.sh" with CLAUDE_TQ_STATE_DIR pointed at
# "${CLAUDE_PLUGIN_DATA}" so the root cache survives plugin updates.

set -euo pipefail

# Resolve symlinks so a relocated/PATH-installed entrypoint still finds lib/.
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in
    /*) SELF="$link" ;;
    *)  SELF="$(dirname "$SELF")/$link" ;;
  esac
done
THIS_DIR="$(cd "$(dirname "$SELF")" && pwd)"
PLUGIN_DIR="$(cd "$THIS_DIR/.." && pwd)"
# shellcheck source=../lib/tasks.sh
. "$PLUGIN_DIR/lib/tasks.sh"
# shellcheck source=../lib/project.sh
. "$PLUGIN_DIR/lib/project.sh"
# shellcheck source=../lib/away.sh
. "$PLUGIN_DIR/lib/away.sh"
# shellcheck source=../lib/signals.sh
. "$PLUGIN_DIR/lib/signals.sh"

# Trimmed standing policy (re-injected on each fresh SessionStart, so kept lean).
# This is the FULL procedure + critique posture, stated ONCE per session — the
# per-prompt capture hook re-anchors to it on the default path instead of
# re-injecting it every turn (the split-loop-from-interrupt model, 2026-06-27).
POLICY='[task-queue] Your native task list IS the live work queue, and substantive prompts run the interpret→decompose→queue loop: read the request in one plain line, break it into concrete tasks in dependency order (smallest blast-radius first, mark parallel-vs-inline, flag any high-fan-in step), TaskCreate them, and work them in order (honor blockedBy) — advancing as you finish, without draining the backlog unprompted. While a task is in_progress, keep a one-line progress breadcrumb in its description (TaskUpdate: what is done, what is next) so a crash resumes it mid-task, not from the top. RUN IN AUTO by default: queue the work and proceed. Only PAUSE for sign-off via AskUserQuestion when there is real signal — the change is CONSEQUENTIAL (irreversible/externally binding), VISUAL/design (show it first), ARCHITECTURALLY SIGNIFICANT (a structural/design choice, a new dependency or seam, a data-model or interface change) or resting on an ASSUMPTION you would otherwise make silently, genuinely AMBIGUOUS, HIGH BLAST-RADIUS, or you would RECOMMEND AGAINST it; otherwise just do the work. For the architectural/assumption case, do as the design-preview does: PRESENT a recommended approach plus 2-3 meaningfully different alternatives via AskUserQuestion and let the owner pick — YOU decide when this fires from having read the prompt (a keyword cannot judge blast radius). EVALUATE before executing — steelman the ask, then challenge it RUTHLESSLY: flag any contradiction with recorded constraints or the owner'"'"'s own earlier requests, and any over-engineering; recommend against part or all — including the prompt in front of you — when that is your honest read. When a better option means retiring a prior requirement or recorded decision, PROPOSE it as a visible trade-off — name what it would retire so the owner picks knowingly — never silently override. Be SELECTIVE — object only on real signal; manufactured pushback trains rubber-stamping. Trivial prompts: just do them. Open questions: when you end a turn with a question the user should answer but might move on without (an offer, a clarification, a decision left to them), TaskCreate it as "❓ <the question>" so it is not lost; mark it completed once they answer or explicitly drop it. When you re-raise a parked ❓ for the owner to decide — including reviewing the pile after autopilot — present it the design-preview way: a blocking AskUserQuestion offering 2-3 concrete options with your recommended one first, not an open prose question.'

# SessionStart hands us JSON on stdin: { session_id, cwd, source, ... }.
input=""
[ -t 0 ] || input="$(cat 2>/dev/null || true)"
sid=""; cwd=""; src=""
if [ -n "$input" ]; then
  sid="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
  src="$(printf '%s' "$input" | jq -r '.source // empty' 2>/dev/null || true)"
fi
[ -n "$cwd" ] || cwd="$PWD"
root="$(tq_root_for_cwd "$cwd")"
# Modes are per-repo slash commands (/task-queue:autopilot|agents|restore|status);
# `autopilot` is the merged autonomous mode (was away + pause). These bare
# invocations are what the model runs when the owner asks in plain language ("keep
# going while I'm gone"); they take on|off (the commands themselves pass `toggle`).
solo_cmd="bash \"$PLUGIN_DIR/bin/tq-away.sh\""
agent_cmd="bash \"$PLUGIN_DIR/bin/tq-agent.sh\""

# Source-aware: inject the full block on a fresh context (startup / clear / and
# any unknown source — the safe default), but only a lean one-line re-anchor on
# compact / resume, where the model already saw the policy this session. The
# solo command rides along in both so natural-language "go solo" survives a compact.
case "$src" in
  compact|resume) lean=1 ;;
  *)              lean=0 ;;
esac

if [ "$lean" -eq 1 ]; then
  ctx="[task-queue] (reminder) native task list = live queue: substantive work → interpret→present→approve (sign-off via AskUserQuestion) before TaskCreate, then work in dependency order and advance as you finish. When the owner steps away, go solo (run autonomous, no approval checkpoint, park decisions): $solo_cmd on|off."
elif tq_policy_documented "$root"; then
  # Quiet mode: the standing policy lives in this project's CLAUDE.md (always
  # loaded), so re-anchor in one line — but still surface state below (carryover,
  # hydration, solo/drift), which is not policy and must not be suppressed.
  ctx="[task-queue] (policy in CLAUDE.md) native task list = live queue; go solo (autonomous, park decisions) when the owner steps away: $solo_cmd on|off."
  resume="$(tq_resume_context "$root" "$sid" 2>/dev/null || true)"
  [ -n "$resume" ] && ctx="$ctx"$'\n\n'"$resume"
  roadmap="$(tq_roadmap_path "$root" 2>/dev/null || true)"
  [ -n "$roadmap" ] && ctx="$ctx"$'\n\n'"[task-queue] Backlog at $roadmap — adopt its open items into your task list with TaskCreate; reflect finished work back."
else
  pause_hint="Modes are per-repo slash commands: /task-queue:autopilot (owner steps away — run fully autonomous, auto-continue the queue, block asking, PARK anything needing them), /task-queue:agents (fan independent tasks to parallel subagents, opt-in), /task-queue:resume (pick up where an earlier session left off — reinstate its open tasks), /task-queue:status (what's on + open work). Run a mode directly if needed: $solo_cmd on|off, $agent_cmd on|off. Natural language works too."
  # Bootstrap nudge: once the policy is recorded in CLAUDE.md, this goes lean.
  tip="Tip: record this standing policy in your CLAUDE.md and mark it with \"claude-companion\" — then this nudge re-anchors in one line each session instead of repeating in full."
  # Orientation/project-knowledge nudges live in the charter plugin (know-the-project),
  # so they're not duplicated here.
  ctx="$POLICY"$'\n\n'"$pause_hint"$'\n\n'"$tip"
  resume="$(tq_resume_context "$root" "$sid" 2>/dev/null || true)"
  [ -n "$resume" ] && ctx="$ctx"$'\n\n'"$resume"
  # Hydrate the live queue from the repo's committed backlog (charter surfaces it
  # for project-knowledge; here it's the orchestration action: pull its open
  # items into the native task list). Full context only — token-light.
  roadmap="$(tq_roadmap_path "$root" 2>/dev/null || true)"
  [ -n "$roadmap" ] && ctx="$ctx"$'\n\n'"[task-queue] This repo has a committed backlog at $roadmap — adopt its open (Now/Next) items into your task list with TaskCreate so the live queue reflects the shared backlog, and reflect finished work back to it as you go."
fi

# State signals — the per-repo mode banners (drift/agent/solo), assembled in
# lib/signals.sh and appended after the policy/resume text. Always shown regardless
# of source (they're state, not policy, so a compact/resume must not suppress them).
signals="$(tq_state_signals "$root" "$solo_cmd" "$agent_cmd")"
[ -n "$signals" ] && ctx="$ctx"$'\n\n'"$signals"

# Emit as SessionStart additionalContext.
jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
