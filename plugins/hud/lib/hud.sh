#!/usr/bin/env bash
# hud — support lib: read-only accessors for the consolidated status line.
#
# Reads ONLY existing on-disk state the other plugins already maintain (never
# their CODE — install boundary) plus the stdin payload. No project scanning.
# Every accessor degrades to empty/0 when its source is absent (e.g. a plugin
# isn't installed), so the matching status-line slot simply collapses.

set -uo pipefail

# Default paths mirror where the sibling plugins write; overridable for tests.
# These three deliberately DON'T chain through the sibling's own env var (the way
# hud_tasks_dir chains CLAUDE_TQ_TASKS_DIR below): the agent/away/verify dirs aren't
# relocatable today, so adding that chain would be speculative coupling — no seam
# until something actually varies. (CLAUDE_TQ_TASKS_DIR is a real, existing knob.)
hud_agent_dir()  { printf '%s' "${CLAUDE_HUD_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}"; }
hud_away_dir()   { printf '%s' "${CLAUDE_HUD_AWAY_DIR:-$HOME/.claude/state/task-queue/away}"; }
hud_verify_dir() { printf '%s' "${CLAUDE_HUD_VERIFY_DIR:-$HOME/.claude/state/tidy/verify}"; }
hud_tasks_dir()  { printf '%s' "${CLAUDE_HUD_TASKS_DIR:-${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}}"; }

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
  [ "${CLAUDE_CHARTER_ALIGN_GATE:-1}" = "0" ]   && out="$out alignment"
  [ "${CLAUDE_TQ_INTENT_GATE:-1}" = "0" ]       && out="$out intent-check"
  printf '%s' "${out# }"
}

# Is task-queue's RETURN-REVIEW gate armed for this repo? prints 1 / 0. When autopilot
# turns off with parked ❓ decisions, tq-away.sh writes a review-<root> marker in the
# shared away dir and the PreToolUse guard blocks edits until the ❓ pile clears — so the
# status line shows 🔒 to explain WHY edits are being denied. Read-only mirror of
# task-queue's tq_review_pending (install boundary forbids sharing the lib;
# drift-guard.bats keeps the path/prefix in agreement). Same root-encoding as hud_away.
hud_review_pending() {
  local root="$1"
  [ -n "$root" ] || { printf '0'; return 0; }
  [ -f "$(hud_away_dir)/review-$(printf '%s' "$root" | sed 's:/:-:g')" ] && printf '1' || printf '0'
}

# Is a DESIGN-PREVIEW pending for this session? prints 1 / 0. On a visual/design prompt
# task-queue arms a design-<sid> marker (relocated into the shared away dir so hud can
# see it) and the PreToolUse guard blocks edits until a wireframe preview is shown; the
# status line shows 🎨 while it's pending. Read-only mirror of tq_design_pending
# (drift-guard.bats keeps them in agreement). Short-lived — cleared the moment the
# preview AskUserQuestion fires, so it flashes briefly rather than lingering.
hud_design_pending() {
  local sid="$1"
  [ -n "$sid" ] || { printf '0'; return 0; }
  [ -f "$(hud_away_dir)/design-$(printf '%s' "$sid" | sed 's:/:-:g')" ] && printf '1' || printf '0'
}

# The on-demand symbol key (`/hud:legend`). The status line is a non-technical
# owner's primary trust signal but renders as bare symbols; this decodes every one
# in plain language. Static text (no stdin), so it costs nothing until invoked.
# When floors are off it names them inline, turning the abstract 🛡✗N into specifics.
hud_legend() {
  cat <<'EOF'
hud status-line key (left → right; the feature-status slot is always shown, the rest hide when empty):

  ⠋ (spinning) health beacon — dots orbit the cell · green: ok · yellow: autopilot on · red: tests failing
  ✈️ autopilot  on = I keep working on my own while you're away; off = normal review loop
  🤖 agents     on = big jobs split across parallel helpers; off = I work inline
               (green = on, grey = off; on a no-color terminal the word on/off is spelled out)
  <model>      the model in use (shown without a label to save space)
  ✓/✗/⚠ tests  last test run — passed / failed / timed out
  ❓N          N parked decisions / open questions awaiting your call this session
  ⏳N          N items blocked on a manual action from you (device / external / owner-only step)
  🔒          review gate armed — editing is paused until you clear the ❓ decisions above
  🎨          design preview pending — I'll show a wireframe before building a visual change
  🛡           all safety checks ON — you're protected (shown whenever every floor is enabled)
  🛡✗N         N SAFETY CHECKS DISABLED — the dot can look green while a guard is off
  ⇡in ⇣out     tokens in the current context / in the last response
  ⎇ branch     git branch · *N uncommitted · ↑N unpushed · ↓N unpulled
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

# Count of items BLOCKED on a manual owner action this session — native tasks whose
# subject starts with "⏳", pending/in_progress, deduped by subject. Disjoint from
# hud_open_questions (❓ decisions): a ⏳ item waits on the owner to DO something (a
# device, an external/paid service, an owner-only step), not to decide. Read-only mirror
# of task-queue's ⏳ convention; drift-guard.bats keeps the two prefixes disjoint. Prints a number.
hud_blocked() {
  local sid="$1" tdir f c
  [ -n "$sid" ] || { printf '0'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  [ -d "$tdir" ] || { printf '0'; return 0; }
  c="$(for f in "$tdir"/*.json; do
        [ -f "$f" ] || continue
        jq -r 'select((.status=="pending" or .status=="in_progress")
                      and ((.subject // "") | startswith("⏳"))) | (.subject // "")' "$f" 2>/dev/null
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

# Is task-queue agent-mode ON for this repo? prints 1 / 0. Honors the per-repo flag
# (content "off" = a tombstone) and the CLAUDE_TQ_AGENT_MODE global default, so the
# status line stays honest when the owner enables it everywhere via settings env.
# (Read-only mirror across the install boundary — mirrors tq_is_agent_mode.)
hud_agent() {
  local root="$1" flag
  [ -n "$root" ] || { printf '0'; return 0; }
  flag="$(hud_agent_dir)/$(printf '%s' "$root" | sed 's:/:-:g')"
  if [ -f "$flag" ]; then
    [ "$(cat "$flag" 2>/dev/null || true)" != "off" ] && printf '1' || printf '0'
    return 0
  fi
  case "${CLAUDE_TQ_AGENT_MODE:-}" in on|1) printf '1' ;; *) printf '0' ;; esac
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
