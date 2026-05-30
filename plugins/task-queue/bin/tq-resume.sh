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

# Trimmed standing policy (re-injected on each fresh SessionStart, so kept lean).
POLICY='[task-queue] Your native task list IS the live work queue. Capture multi-step work with TaskCreate (skip trivial/chat) before starting, work it in dependency order (honor blockedBy), and advance as you finish — without draining the backlog unprompted.'

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
pause_cmd="bash \"$PLUGIN_DIR/bin/tq-pause.sh\""

# Source-aware: inject the full block on a fresh context (startup / clear / and
# any unknown source — the safe default), but only a lean one-line re-anchor on
# compact / resume, where the model already saw the policy this session. The
# pause command rides along in both so natural-language pause survives a compact.
case "$src" in
  compact|resume) lean=1 ;;
  *)              lean=0 ;;
esac

if [ "$lean" -eq 1 ]; then
  ctx="[task-queue] (reminder) native task list = live queue: capture work with TaskCreate, work in dependency order, advance as you finish. Pause/resume on request: $pause_cmd on|off."
else
  pause_hint="Pause/resume auto-advance on request: $pause_cmd on|off (per repo, persists)."
  orient_hint="Learned something durable about this project's layout or conventions? Record it in CLAUDE.md so future sessions skip re-exploring (saves tokens over time)."
  ctx="$POLICY"$'\n\n'"$pause_hint"$'\n\n'"$orient_hint"
  resume="$(tq_resume_context "$root" "$sid" 2>/dev/null || true)"
  [ -n "$resume" ] && ctx="$ctx"$'\n\n'"$resume"
fi

# State signals — always shown, regardless of source.
paused=0
if tq_is_paused "$root"; then
  paused=1
  ctx="$ctx"$'\n\n'"⏸ Auto-advance is PAUSED for this repo — completing a task won't surface the next until you resume ($pause_cmd off)."
fi
drift=0
if [ "$(tq_schema_status 2>/dev/null || true)" = "drift" ]; then
  drift=1
  ctx="$ctx"$'\n\n'"⚠️ [task-queue] The native task store no longer matches the expected schema — Claude Code may have changed it; carry-over/advance may be degraded. Run $PLUGIN_DIR/bin/tq-doctor.sh (see CONTRACT.md)."
fi

tq_log "session-start" \
  "src=${src:-?} mode=$( [ "$lean" -eq 1 ] && printf 'lean' || printf 'full' )$( [ "$paused" -eq 1 ] && printf ', paused' )$( [ "$drift" -eq 1 ] && printf ', DRIFT' )" \
  "$sid"

# Emit as SessionStart additionalContext.
jq -cn --arg c "$ctx" \
  '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
