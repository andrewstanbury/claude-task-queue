#!/usr/bin/env bash
# task-queue — open-decisions ledger: so a question the model asks can't be
# silently lost when the user is typing ahead / queuing prompts.
#
# Claude Code has no way to force the user to answer (no hook can block typing),
# and a queued prompt is delivered as the next turn — burying a question. The
# robust fix: persist the open decisions and (a) re-inject them every turn via a
# UserPromptSubmit hook so the model keeps re-surfacing them, (b) alert the user
# via a Notification hook when the model goes idle with one open. The model logs
# a decision with bin/tq-ask.sh when it asks, and resolves it on an answer.
#
# Keyed by repo root (like pause/agent flags) so the model's CLI calls (which
# know only $PWD) and the hooks (which get cwd from the payload) hit the same
# ledger — and an open decision survives a restart. Read/written only under the
# plugin's own state dir; never touches the project.

set -uo pipefail

tq_decisions_dir()  { printf '%s' "${CLAUDE_TQ_DECISIONS_DIR:-$HOME/.claude/state/task-queue/decisions}"; }
tq_decisions_file() { printf '%s/%s.jsonl' "$(tq_decisions_dir)" "$(printf '%s' "$1" | sed 's:/:-:g')"; }

# Append an open decision for repo root $1: question $2, recommended option $3.
# Prints the new id. Best-effort; never fails the caller.
tq_decision_add() {
  local root="$1" q="$2" rec="${3:-}" f id ts
  [ -n "$root" ] && [ -n "$q" ] || return 0
  f="$(tq_decisions_file "$root")"
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  # id = max existing numeric id + 1 (stable across appends within a repo).
  # Parse line-by-line with `jq -R 'fromjson?'` so a single corrupt/half-written
  # line (e.g. from a crash mid-append) is skipped rather than collapsing the
  # whole slurp to 0 — which would reuse id 1 and let `resolve 1` delete the wrong
  # decision, defeating the "never lose a question" guarantee.
  id=1
  if [ -f "$f" ]; then
    local max; max="$(jq -R 'fromjson? | .id | tonumber?' "$f" 2>/dev/null | sort -n | tail -1)"
    [ -n "$max" ] && id=$(( max + 1 ))
  fi
  ts="$(date '+%Y-%m-%dT%H:%M:%S%z' 2>/dev/null || printf '?')"
  jq -cn --arg id "$id" --arg q "$q" --arg rec "$rec" --arg ts "$ts" \
    '{id:$id, q:$q, rec:$rec, ts:$ts}' >> "$f" 2>/dev/null || true
  printf '%s' "$id"
}

# Resolve (remove) decision id $2 for root $1, or "all" to clear them.
tq_decision_resolve() {
  local root="$1" id="${2:-}" f tmp
  [ -n "$root" ] && [ -n "$id" ] || return 0
  f="$(tq_decisions_file "$root")"
  [ -f "$f" ] || return 0
  if [ "$id" = "all" ]; then rm -f "$f" 2>/dev/null || true; return 0; fi
  tmp="$f.tmp"
  if jq -c --arg id "$id" 'select(.id != $id)' "$f" > "$tmp" 2>/dev/null; then
    if [ -s "$tmp" ]; then mv "$tmp" "$f"; else rm -f "$tmp" "$f"; fi
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

# Emit open decisions for root $1 as "id<TAB>question<TAB>recommended" lines.
tq_decision_list() {
  local root="$1" f
  [ -n "$root" ] || return 0
  f="$(tq_decisions_file "$root")"
  [ -f "$f" ] || return 0
  jq -r '[.id, .q, (.rec // "")] | @tsv' "$f" 2>/dev/null || true
}

# Count of open decisions for root $1. (`grep -c .` already prints 0 on no match;
# `|| true` just swallows its exit-1 so pipefail callers don't trip.)
tq_decision_count() {
  local n; n="$(tq_decision_list "$1" 2>/dev/null | grep -c . || true)"
  printf '%s' "${n:-0}"
}
