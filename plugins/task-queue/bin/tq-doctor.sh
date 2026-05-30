#!/usr/bin/env bash
# tq-doctor — a manual, read-only health check.
#
# Validates the assumptions in CONTRACT.md (what this plugin depends on from
# Claude Code's internals) and shows the tail of the activity log. Run it by
# hand when carry-over or auto-advance stops working — it turns "mysteriously
# silent" into "this CONTRACT assumption no longer holds."
#
#   bash bin/tq-doctor.sh
#
# Read-only: it inspects, it never writes the task store. Exits non-zero only on
# a hard FAIL (something that stops the plugin from functioning at all).

set -uo pipefail   # not -e: we want every check to run and report, not abort

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

fails=0
warns=0
pass() { printf '  [PASS] %s\n' "$1"; }
warn() { printf '  [WARN] %s\n' "$1"; warns=$((warns + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; fails=$((fails + 1)); }

printf 'tq-doctor — claude-task-queue health check\n\n'

# 1. Hard requirements --------------------------------------------------------
printf 'Requirements\n'
if command -v jq >/dev/null 2>&1; then pass "jq present ($(jq --version 2>/dev/null))"
else fail "jq not found on PATH — the plugin cannot function without it"; fi
if [ "${BASH_VERSINFO[0]:-0}" -ge 4 ]; then pass "bash ${BASH_VERSINFO[0]}.x"
else warn "bash ${BASH_VERSINFO[0]:-?} — Bash 4+ recommended"; fi

# 2. Claude Code internals we read (see CONTRACT.md) --------------------------
printf '\nClaude Code internals (CONTRACT.md)\n'
tasks_dir="$(tq_tasks_dir)"
if [ -d "$tasks_dir" ]; then pass "task store: $tasks_dir"
else warn "task store not found at $tasks_dir (none created yet, or layout changed)"; fi

projects_dir="$(tq_projects_dir)"
if [ -d "$projects_dir" ]; then pass "transcripts: $projects_dir"
else warn "transcripts dir not found at $projects_dir — cross-session resume can't map sessions to repos"; fi

# Schema canary: sample task files and confirm the fields we rely on exist.
sample=0; bad=""
if [ -d "$tasks_dir" ]; then
  for f in "$tasks_dir"/*/*.json; do
    [ -f "$f" ] || continue
    sample=$((sample + 1))
    if ! jq -e 'has("id") and has("status")' "$f" >/dev/null 2>&1; then bad="$f"; break; fi
    [ "$sample" -ge 25 ] && break    # a sample is enough; don't scan thousands
  done
fi
if [ -n "$bad" ]; then fail "task schema changed — $bad lacks expected id/status fields"
elif [ "$sample" -gt 0 ]; then pass "task schema OK (sampled $sample file(s): id + status present)"
else warn "no task files to sample yet — schema unverified"; fi

# 3. Plugin wiring ------------------------------------------------------------
printf '\nPlugin wiring\n'
if jq -e . "$PLUGIN_DIR/hooks/hooks.json" >/dev/null 2>&1; then
  pass "hooks.json is valid JSON"
  while IFS= read -r cmd; do
    rel="$(printf '%s' "$cmd" | grep -oE 'bin/[A-Za-z0-9_-]+\.sh' || true)"
    [ -n "$rel" ] || continue
    if [ -x "$PLUGIN_DIR/$rel" ]; then pass "hook script present: $rel"
    else fail "hook script missing or not executable: $rel"; fi
  done < <(jq -r '.hooks[][].hooks[].command' "$PLUGIN_DIR/hooks/hooks.json" 2>/dev/null)
else
  fail "hooks.json is missing or invalid JSON"
fi

# 4. Activity log -------------------------------------------------------------
printf '\nActivity log\n'
logf="$(tq_log_file)"
if [ "${CLAUDE_TQ_LOG_DISABLED:-}" ]; then warn "logging disabled (CLAUDE_TQ_LOG_DISABLED set)"
elif [ -f "$logf" ]; then
  pass "log: $logf"
  printf '  last entries:\n'
  tail -n 15 "$logf" 2>/dev/null | sed 's/^/    /'
else
  warn "no log yet at $logf (written once a hook fires in a real session)"
fi

# Summary ---------------------------------------------------------------------
printf '\n%d pass-with-warnings issue(s), %d failure(s).\n' "$warns" "$fails"
if [ "$fails" -gt 0 ]; then
  printf 'FAIL — see [FAIL] lines above; cross-check against CONTRACT.md.\n'
  exit 1
fi
printf 'OK — core assumptions hold.\n'
