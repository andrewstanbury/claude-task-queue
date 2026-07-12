#!/usr/bin/env bash
# PreCompact — fires just before the context is summarized (R30·d2). The `tq` queue is the model's
# memory ACROSS a compaction (it persists in the store), so nudge it to freshen the in-progress
# task's breadcrumb + done-when NOW, while the detail is still in context. The re-anchor on the far
# side is session-start.sh (SessionStart[source=compact]), which re-injects STEERING + the live
# queue — that's the reliable half; this is a best-effort freshen-nudge. Non-blocking (R7): if the
# host doesn't surface PreCompact context, this is a harmless no-op.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
jq -cn '{hookSpecificOutput:{hookEventName:"PreCompact",additionalContext:"Context is about to compact — your `tq` queue is your memory across it. Before the detail is summarized away, make sure the in-progress task'"'"'s breadcrumb and its done-when are current in the queue; you will resume from the queue afterward, not from what is about to be lost."}}'
