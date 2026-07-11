#!/usr/bin/env bash
# hud — support lib: read-only accessors for the consolidated status line.
#
# Reads ONLY existing on-disk state the other plugins already maintain (never
# their CODE — install boundary) plus the stdin payload. No project scanning.
# Every accessor degrades to empty/0 when its source is absent (e.g. a plugin
# isn't installed), so the matching status-line slot simply collapses.

set -uo pipefail

# Default paths mirror where the sibling plugins write; overridable for tests.
# Each CHAINS through the sibling's OWN relocation env var before the hardcoded
# default (the way hud_tasks_dir already does for CLAUDE_TQ_TASKS_DIR) — because the
# siblings honor these vars (tq_agent_dir/tq_away_dir read CLAUDE_TQ_*_DIR; tidy's
# verify result lives under CLAUDE_TIDY_LOG_DIR), so if the owner relocates a sibling's
# state hud must follow or the status line silently reads the wrong dir and shows a
# feature OFF while it's ON. The variance is real (2 sibling knobs, not hypothetical),
# so this is not speculative coupling — it's honesty. drift-guard.bats exercises the
# chain (it sets only the CLAUDE_TQ_* var and asserts hud still sees the flag).
hud_agent_dir()  { printf '%s' "${CLAUDE_HUD_AGENT_DIR:-${CLAUDE_TQ_AGENT_DIR:-$HOME/.claude/state/task-queue/agent}}"; }
hud_away_dir()   { printf '%s' "${CLAUDE_HUD_AWAY_DIR:-${CLAUDE_TQ_AWAY_DIR:-$HOME/.claude/state/task-queue/away}}"; }
hud_verify_dir() { printf '%s' "${CLAUDE_HUD_VERIFY_DIR:-${CLAUDE_TIDY_LOG_DIR:-$HOME/.claude/state/tidy}/verify}"; }
hud_tasks_dir()  { printf '%s' "${CLAUDE_HUD_TASKS_DIR:-${CLAUDE_TQ_TASKS_DIR:-$HOME/.claude/tasks}}"; }

# Injective encoding of a repo ROOT into one filename component — a read-only MIRROR of
# task-queue's tq_enc_root (install boundary forbids sharing it), so hud reads the exact
# flag files task-queue writes. Percent-encodes '/' (escaping '%' first) so distinct roots
# never collide. MUST stay byte-identical to tq_enc_root; drift-guard.bats asserts it. Only
# the root-keyed flags (away/agent/review) use this; sid-keyed markers (design/verify) can't
# collide (a session id has no '/') and stay '/'→'-'.
hud_enc_root() { local r="${1:-}"; r="${r//%/%25}"; printf '%s' "${r//\//%2F}"; }

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
  [ -f "$(hud_away_dir)/review-$(hud_enc_root "$root")" ] && printf '1' || printf '0'
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
  [ -f "$(hud_away_dir)/design-${sid//\//-}" ] && printf '1' || printf '0'
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
  📋 N ▸ task  N open tasks in the live queue (non-parked work) · ▸ names the one in progress
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
  local sid="$1" tdir files
  [ -n "$sid" ] || { printf '0'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  files=("$tdir"/*.json); [ -e "${files[0]}" ] || { printf '0'; return 0; }  # no store / empty glob
  # ONE jq slurp over the whole session — the render runs every second, so a jq
  # PER FILE (×3 counters × N tasks) was the dominant per-render cost. Same result:
  # distinct ❓ subjects among pending/in_progress.
  jq -rs '[.[] | select((.status=="pending" or .status=="in_progress")
            and ((.subject // "") | sub("^\\s+";"") | startswith("❓")))
          | (.subject // "") | select(. != "")] | unique | length' "${files[@]}" 2>/dev/null || printf '0'
}

# Count of items BLOCKED on a manual owner action this session — native tasks whose
# subject starts with "⏳", pending/in_progress, deduped by subject. Disjoint from
# hud_open_questions (❓ decisions): a ⏳ item waits on the owner to DO something (a
# device, an external/paid service, an owner-only step), not to decide. Read-only mirror
# of task-queue's ⏳ convention; drift-guard.bats keeps the two prefixes disjoint. Prints a number.
hud_blocked() {
  local sid="$1" tdir files
  [ -n "$sid" ] || { printf '0'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  files=("$tdir"/*.json); [ -e "${files[0]}" ] || { printf '0'; return 0; }
  jq -rs '[.[] | select((.status=="pending" or .status=="in_progress")
            and ((.subject // "") | sub("^\\s+";"") | startswith("⏳")))
          | (.subject // "") | select(. != "")] | unique | length' "${files[@]}" 2>/dev/null || printf '0'
}

# Open, non-parked WORK in this session's live queue — the read-only mirror of
# task-queue's tq_open_worklist: pending/in_progress tasks that are NOT deferred
# (neither a ❓ [parked] decision nor a ⏳ [blocked] owner-action — those have their
# own badges, so excluding them keeps the three buckets disjoint instead of one total
# counted three ways). ONE scan of the session's files — the per-second render can't
# afford more — printing TWO lines: (1) the count, deduped by subject; (2) the subject
# of the CURRENT in_progress task (first found), empty when nothing is running. The
# native Task tools populate the store, so a model with them gated off has an empty
# store and this collapses to "0" (the slot then disappears). Prints "0" + a blank line
# for no session / no store.
hud_worklist() {
  local sid="$1" tdir files
  [ -n "$sid" ] || { printf '0\n\n'; return 0; }
  tdir="$(hud_tasks_dir)/$sid"
  files=("$tdir"/*.json); [ -e "${files[0]}" ] || { printf '0\n\n'; return 0; }
  # ONE jq slurp (per-second render path): $n = distinct non-deferred open subjects,
  # $cur = the current in_progress one (first in file order), empty when none.
  jq -rs '[.[] | select((.status=="pending" or .status=="in_progress")
              and (((.subject // "") | sub("^\\s+";"") | (startswith("❓") or startswith("⏳"))) | not))] as $w
          | ([$w[] | (.subject // "") | select(. != "")] | unique | length) as $n
          | ([$w[] | select(.status=="in_progress") | (.subject // "") | select(. != "")] | .[0] // "") as $cur
          | "\($n)\n\($cur)"' "${files[@]}" 2>/dev/null || printf '0\n\n'
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
  flag="$(hud_agent_dir)/$(hud_enc_root "$root")"
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
  flag="$(hud_away_dir)/$(hud_enc_root "$root")"
  [ -f "$flag" ] && printf '1' || printf '0'
}

# The verification floor's last outcome for this session: "pass" | "fail" |
# "timeout" | "" (never run / unknown). Read-only mirror of the marker
# tidy-verify.sh writes — the single highest-value signal for a non-technical
# owner ("are the tests passing?").
hud_verify() {
  local sid="$1" f
  [ -n "$sid" ] || return 0
  f="$(hud_verify_dir)/result-${sid//\//-}"
  [ -f "$f" ] && { cat "$f" 2>/dev/null || true; }
}

# The whole branch slot in ONE git read: prints "<branch>\t<dirty>\t<ahead>\t<behind>",
# empty outside a repo. This replaces four separate per-render git forks — branch
# (rev-parse --abbrev-ref), dirty (status --porcelain), and the ahead/behind pair
# (rev-parse @{upstream} + rev-list) — with a single `git status --porcelain=v2 --branch`,
# whose header lines already carry branch.head + branch.ab, and whose entry lines ARE the
# dirty set. On the per-render hot path that's the biggest fork saving after dropping the
# animated beacon. Fields: dirty = count of changed/untracked entries (empty when clean,
# matching the old grep -c); ahead/behind come from `# branch.ab +A -B` (empty with no
# upstream); a detached HEAD prints @<short-sha> from branch.oid, as hud_branch used to.
hud_git() {
  local cwd="$1" line branch="" dirty=0 ahead="" behind="" oid="" a b
  while IFS= read -r line; do
    case "$line" in
      '# branch.head '*) branch="${line#\# branch.head }" ;;
      '# branch.oid '*)  oid="${line#\# branch.oid }" ;;
      '# branch.ab '*)   read -r a b <<< "${line#\# branch.ab }"; ahead="${a#+}"; behind="${b#-}" ;;
      '#'*) : ;;                       # other headers (upstream) — ignore
      ?*)   dirty=$((dirty + 1)) ;;    # any non-header line is one changed/untracked entry
    esac
  done < <(git -C "$cwd" status --porcelain=v2 --branch 2>/dev/null)
  [ -n "$branch" ] || return 0         # not a repo / git failed → empty slot
  [ "$branch" = "(detached)" ] && branch="@${oid:0:7}"
  [ "$dirty" -eq 0 ] && dirty=""
  printf '%s\t%s\t%s\t%s' "$branch" "$dirty" "$ahead" "$behind"
}
