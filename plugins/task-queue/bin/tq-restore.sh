#!/usr/bin/env bash
# tq-restore — on-demand "put me back where I was", backing /task-queue:resume.
#
# The SessionStart hook (tq-resume.sh) already re-surfaces earlier tasks on every
# start. This is the MANUAL twin that does it again on request — for after a
# crash-and-relaunch, or when the startup note got compacted away — plus one honest
# line about the one thing a slash command CANNOT do: reload the conversation itself
# (that is `claude --resume` at launch, a harness feature no plugin can reach). Two
# cheap, read-only steps:
#   1. Rehydrate open tasks carried over from earlier sessions in this repo.
#   2. Point at `claude --resume` for the conversation transcript itself.
#
# Plain text out (like tq-status.sh backs /status) — the /resume command relays it.
# Read-only over ~/.claude/tasks; writes nothing.

set -uo pipefail

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
# shellcheck source=../lib/resume.sh
. "$PLUGIN_DIR/lib/resume.sh"
set +e   # tasks.sh enables `set -e`; this is a best-effort readout — never abort mid-report.

root="$(tq_root_for_cwd "$PWD")"

# 1. Tasks — the same carryover the SessionStart hook surfaces, on demand. Empty sid
# (a command has no hook stdin to read session_id from) → include every recent
# session for this repo; re-adding any already-live task is idempotent.
printf '\n== Carried-over tasks ==\n'
resume="$(tq_resume_context "$root" "" 2>/dev/null || true)"
if [ -n "$resume" ]; then
  printf '%s\n' "$resume"
else
  printf 'No open tasks carry over from earlier sessions in this repo.\n'
fi

# 2. Conversation — the honest limit. Don't let the command imply it restored context.
printf '\n== Conversation ==\n'
printf 'This command cannot reload the previous conversation — a slash command runs inside the current session. To bring back the earlier transcript, relaunch Claude Code with: claude --resume\n'
