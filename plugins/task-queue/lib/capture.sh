#!/usr/bin/env bash
# capture — heuristics for the UserPromptSubmit capture nudge (bin/tq-capture.sh).
#
# Kept out of tasks.sh so the core stays small and loadable; this is sourced
# only by the capture hook. Depends on tq_tasks_dir() from tasks.sh.

# Count this session's OPEN (pending/in_progress) tasks. Completed files can
# linger on disk (see CONTRACT.md), so filter by status, not file presence.
tq_open_count() {
  local sid="$1" dir f n=0
  [ -n "$sid" ] || { printf '0'; return 0; }
  dir="$(tq_tasks_dir)/$sid"
  [ -d "$dir" ] || { printf '0'; return 0; }
  for f in "$dir"/*.json; do
    [ -f "$f" ] || continue
    jq -e '.status=="pending" or .status=="in_progress"' "$f" >/dev/null 2>&1 && n=$((n + 1))
  done
  printf '%s' "$n"
}

# Conservative heuristic: does this prompt look like multi-step work worth
# queuing? Errs toward NOT firing — a false nudge is noise, but a miss is
# harmless (the SessionStart policy still covers capture). Returns 0 yes / 1 no.
tq_looks_multistep() {
  local p="$1" low n=0 v
  [ "$(printf '%s' "$p" | wc -w)" -ge 8 ] || return 1      # too short to be multi-step
  low="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    *" and then "*|*" then "*|*", then "*|*" also "*|*" after that "*) return 0 ;;
  esac
  printf '%s' "$p" | grep -qE '(^|[[:space:]])([0-9]+[.)]|[-*][[:space:]])' && return 0  # list markers
  for v in add fix implement refactor build create update remove rename migrate \
           write test wire integrate support handle setup configure; do
    case "$low" in *"$v "*) n=$((n + 1)) ;; esac
  done
  [ "$n" -ge 2 ]                                            # 2+ action verbs → multi-step
}
