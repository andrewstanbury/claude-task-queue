#!/usr/bin/env bash
# hud — support lib: read-only accessors for the consolidated status line.
#
# Reads ONLY existing on-disk state the other plugins already maintain (never
# their CODE — install boundary) plus the stdin payload. No project scanning.
# Every accessor degrades to empty/0 when its source is absent (e.g. a plugin
# isn't installed), so the matching status-line slot simply collapses.

set -uo pipefail

# Default paths mirror where the sibling plugins write; overridable for tests.
hud_agent_dir()  { printf '%s' "${CLAUDE_HUD_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}"; }
hud_away_dir()   { printf '%s' "${CLAUDE_HUD_AWAY_DIR:-$HOME/.claude/state/task-queue/away}"; }
hud_ckpt_dir()   { printf '%s' "${CLAUDE_HUD_CKPT_DIR:-$HOME/.claude/state/task-queue/checkpoint}"; }
hud_verify_dir() { printf '%s' "${CLAUDE_HUD_VERIFY_DIR:-$HOME/.claude/state/tidy/verify}"; }
hud_tasks_dir()  { printf '%s' "${CLAUDE_HUD_TASKS_DIR:-${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}}"; }
hud_coupling_dir() { printf '%s' "${CLAUDE_HUD_COUPLING_DIR:-$HOME/.claude/state/tidy/coupling-hud}"; }

# Coupling-density trend direction for this repo — "up" when tidy's last verify saw
# import density climbing past the threshold, else "steady"/"" (empty when never
# computed / too-small repo). A cheap read of the cached marker tidy-verify writes;
# hud never computes density itself (too heavy for a per-render status line).
hud_coupling() {
  local root="$1" f
  [ -n "$root" ] || return 0
  f="$(hud_coupling_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$f" ] && cat "$f" 2>/dev/null
}

# Which safety floors are currently DISABLED — prints the friendly names of the
# anti-rework gates the owner (or Claude) has switched off via a CLAUDE_*=0 env var
# (space-separated, empty when all are on). The beacon can read "green" while a
# guard is off; this is what makes the status line an HONEST trust signal rather
# than one that quietly lies. Read-only env read — no files, no subprocess.
#
# The flag NAMES are owned by the sibling hooks (install boundary forbids sharing);
# tests/drift-guard.bats asserts each one here is still honored by its owner, so a
# rename can't silently make this marker miss a disabled floor.
hud_floors_disabled() {
  local out=""
  [ "${CLAUDE_TIDY_SECSCAN:-1}" = "0" ]         && out="$out secret-scan"
  [ "${CLAUDE_TIDY_CHECKS:-1}" = "0" ]          && out="$out tests"
  [ "${CLAUDE_TIDY_QUALITY_FLOOR:-1}" = "0" ]   && out="$out quality"
  [ "${CLAUDE_TIDY_REGRESSION_GATE:-1}" = "0" ] && out="$out regression"
  [ "${CLAUDE_CHARTER_ALIGN_GATE:-1}" = "0" ]   && out="$out alignment"
  [ "${CLAUDE_TQ_INTENT_GATE:-1}" = "0" ]       && out="$out intent-check"
  printf '%s' "${out# }"
}

# The on-demand symbol key (`/hud:legend`). The status line is a non-technical
# owner's primary trust signal but renders as bare symbols; this decodes every one
# in plain language. Static text (no stdin), so it costs nothing until invoked.
# When floors are off it names them inline, turning the abstract 🛡✗N into specifics.
hud_legend() {
  cat <<'EOF'
hud status-line key (left → right; each slot hides when it has nothing to say):

  ●            health dot — green: ok · yellow: solo mode · red: tests failing
  🤖 agent     agent-mode on (parallel subagents)
  🚶 solo      solo mode on (Claude runs autonomous; decisions parked for you)
  🧷 ckpt      crash-checkpoint armed (edits auto-snapshotted; absent = off)
  ✓/✗/⚠ tests  last test run — passed / failed / timed out
  ❓N          N open questions you still owe an answer on this session
  🔗↑          code coupling rose past its threshold at the last check
  🛡✗N         N SAFETY CHECKS DISABLED — the dot can look green while a guard is off
  ctx NN%      how full the context window is (compaction nears at 100%)
  tok ⇡in ⇣out tokens in the current context / in the last response
  $N.NN        session cost so far
  ⎇ branch     git branch · *N uncommitted · ↑N unpushed · ↓N unpulled
  Model:       the model in use
EOF
  local off; off="$(hud_floors_disabled)"
  [ -n "$off" ] && printf '\nCurrently disabled (🛡✗): %s\n' "$off"
}

# Count of OPEN QUESTIONS the user still owes an answer on this session — native
# tasks whose subject starts with "❓", pending/in_progress, deduped by subject.
# Read-only mirror of task-queue's tq_open_questions (install boundary forbids
# sharing the lib; drift-guard.bats keeps the two in agreement). Prints a number.
hud_open_questions() {
  local sid="$1" tdir f c
  [ -n "$sid" ] || { printf '0'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  [ -d "$tdir" ] || { printf '0'; return 0; }
  c="$(for f in "$tdir"/*.json; do
        [ -f "$f" ] || continue
        jq -r 'select((.status=="pending" or .status=="in_progress")
                      and ((.subject // "") | startswith("❓"))) | (.subject // "")' "$f" 2>/dev/null
      done | awk 'NF && !seen[$0]++' | grep -c .)"
  printf '%s' "${c:-0}"
}

# Humanize a token count for the status line: <1000 verbatim, thousands as N.Nk,
# millions as N.NM (integer-only — no bc, so it's safe in a per-render path). Empty
# or non-numeric input prints nothing, so the matching slot collapses.
hud_human_tokens() {
  local n="$1"
  case "$n" in ''|*[!0-9]*) return 0 ;; esac
  if [ "$n" -lt 1000 ]; then printf '%s' "$n"
  elif [ "$n" -lt 1000000 ]; then printf '%s.%sk' "$((n/1000))" "$(((n%1000)/100))"
  else printf '%s.%sM' "$((n/1000000))" "$(((n%1000000)/100000))"
  fi
}

# Is task-queue agent-mode ON for this repo? prints 1 / 0. (Same per-repo flag
# scheme as away; read-only mirror across the install boundary.)
hud_agent() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_agent_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# Is solo mode ON for this repo? prints 1 / 0. Solo (formerly away; it also folded in
# the old pause) is the most consequential mode — Claude runs autonomous + parks
# decisions — so it MUST be visible in the status line, and it colors the health
# beacon yellow. Reads task-queue's away flag. (Same per-repo flag scheme as agent;
# read-only mirror across the install boundary.)
hud_away() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_away_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# Is the crash checkpoint ARMED for this repo? prints 1 / 0. (Same per-repo flag
# scheme as away/agent; read-only mirror across the install boundary.)
hud_checkpoint() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_ckpt_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# The verification floor's last outcome for this session: "pass" | "fail" |
# "timeout" | "" (never run / unknown). Read-only mirror of the marker
# tidy-verify.sh writes — the single highest-value signal for a non-technical
# owner ("are the tests passing?").
hud_verify() {
  local sid="$1" f
  [ -n "$sid" ] || return 0
  f="$(hud_verify_dir)/result-$(printf '%s' "$sid" | sed 's:/:-:g')"
  [ -f "$f" ] && { cat "$f" 2>/dev/null || true; }
}

# How many uncommitted files in the working tree (porcelain count), or "" outside
# a git repo. The branch slot already shells to git, so this is cheap context for
# "you have unsaved work" while vibe-coding.
hud_dirty() {
  local cwd="$1" n
  git -C "$cwd" rev-parse >/dev/null 2>&1 || return 0
  n="$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c .)"
  [ "$n" -gt 0 ] && printf '%s' "$n"
}

# Commits HEAD is ahead / behind its upstream — i.e. unpushed work (ahead) and
# unpulled work (behind). Prints "<ahead> <behind>" or empty when there's no
# upstream (nothing to compare). One cheap rev-list over the symmetric range; the
# branch slot already shells to git, so this is the "you have unpushed commits"
# companion to the dirty-file count's "you have uncommitted changes".
hud_ahead_behind() {
  local cwd="$1" out behind ahead
  git -C "$cwd" rev-parse '@{upstream}' >/dev/null 2>&1 || return 0
  out="$(git -C "$cwd" rev-list --count --left-right '@{upstream}...HEAD' 2>/dev/null)" || return 0
  [ -n "$out" ] || return 0
  # rev-list --left-right prints "<behind>\t<ahead>" (left = upstream-only commits).
  read -r behind ahead <<< "$out"
  printf '%s %s' "${ahead:-0}" "${behind:-0}"
}

# Current git branch for a dir (short SHA when detached), or empty.
hud_branch() {
  local cwd="$1" b
  b="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [ "$b" = "HEAD" ] && b="@$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null || true)"
  printf '%s' "$b"
}
