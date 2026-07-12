#!/usr/bin/env bash
# Shared helpers for the persisted per-repo autopilot flag — sourced by bin/autopilot.sh,
# the Stop hook, the ask-guard, and the status line. (One plugin, so a shared lib is fine;
# the encoding MUST be identical across all four readers, which is exactly why it lives here.)

companion_state_dir() { printf '%s' "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}"; }

# Injective encoding of a repo root into one filename component (escape % first, then /),
# so two distinct roots never collide to the same flag file.
companion_enc() { printf '%s' "${1:-}" | sed -e 's:%:%25:g' -e 's:/:%2F:g'; }

# cwd (or a path) -> repo root, git toplevel or the path itself.
companion_root() { git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${1:-$PWD}"; }

companion_autopilot_flag() { printf '%s/autopilot/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_autopilot_on()   { [ -n "${1:-}" ] && [ -f "$(companion_autopilot_flag "$1")" ]; }

# The companion's own task store (not native tasks).
companion_tasks_dir() { printf '%s' "${CLAUDE_COMPANION_TASKS_DIR:-$HOME/.claude/companion/tasks}"; }

# Open (pending/in_progress) task subjects for a repo, across every session dir whose `.root`
# stamp matches — the cross-session resume signal. One "  ◻ <subject>" line each; empty when
# none. Shared by the SessionStart hook (auto-resume) and `bin/resume.sh` (manual).
companion_open_tasks() {
  local root="$1" store d f
  store="$(companion_tasks_dir)"; [ -d "$store" ] || return 0
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    [ "$(cat "$d.root" 2>/dev/null || true)" = "$root" ] || continue
    for f in "$d"*.json; do
      [ -f "$f" ] || continue
      jq -r 'select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "")' "$f" 2>/dev/null || true
    done
  done
}

# Does this repo have ANY open parked ❓ task (for the return-review gate)? 0/1.
companion_has_parked() {
  local root="$1" store d f
  store="$(companion_tasks_dir)"; [ -d "$store" ] || return 1
  for d in "$store"/*/; do
    [ -d "$d" ] || continue
    [ "$(cat "$d.root" 2>/dev/null || true)" = "$root" ] || continue
    for f in "$d"*.json; do
      [ -f "$f" ] || continue
      jq -e 'select((.status=="pending" or .status=="in_progress") and ((.subject//"")|sub("^\\s+";"")|startswith("❓")))' "$f" >/dev/null 2>&1 && return 0
    done
  done
  return 1
}

# ---- gate state ----
# Per session (intent/design/reminded keyed by session_id; review keyed by repo root so it
# survives the session that ran autopilot). reminded-* records that the (advisory) intent→outcome
# reminder already fired this request, so it surfaces once — on the first edit — not every edit.
companion_sid_safe()      { printf '%s' "${1:-x}" | sed 's:/:-:g'; }
companion_intent_file()   { printf '%s/intent-%s'   "$(companion_state_dir)" "$(companion_sid_safe "${1:-}")"; }
companion_design_flag()   { printf '%s/design-%s'   "$(companion_state_dir)" "$(companion_sid_safe "${1:-}")"; }
companion_reminded_flag() { printf '%s/reminded-%s' "$(companion_state_dir)" "$(companion_sid_safe "${1:-}")"; }
companion_review_flag()   { printf '%s/review/%s'   "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }

# ---- detection ----
# A repo's recorded-decisions record (the ledger leads): prints a relative path or nothing.
companion_decisions_path() {
  local root="$1" f g rel
  [ -n "$root" ] || return 0
  for f in REQUIREMENTS.md docs/REQUIREMENTS.md DECISIONS.md docs/DECISIONS.md; do
    [ -f "$root/$f" ] && { printf '%s' "$f"; return 0; }
  done
  for g in "$root"/docs/adr/*.md "$root"/docs/adrs/*.md "$root"/docs/decisions/*.md; do
    [ -f "$g" ] && { rel="${g#"$root"/}"; printf '%s/' "${rel%/*}"; return 0; }
  done
}

# Does this prompt ask for a VISUAL/UI change worth previewing? Precision-tuned: an
# inherently-visual term fires alone; otherwise an appearance verb AND a UI noun. 0 yes / 1 no.
companion_looks_visual() {
  local low; low="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$low" | grep -Eq '(^|[^a-z])(layouts?|wireframes?|mock[- ]?ups?|ui|ux|user interface|design systems?|colou?r schemes?|palettes?|typograph)([^a-z]|$)' && return 0
  printf '%s' "$low" | grep -Eq '(^|[^a-z])(re-?style|re-?skin|re-?colou?r|re-?theme|re-?paint|prettif|beautif)([^a-z]|$)' && return 0
  printf '%s' "$low" | grep -Eq '(^|[^a-z])((re-?)?design|(re-?)?lay[ -]?out|reposition|rearrange|re-?align|resize|move|cent(er|re)|style|theme|skin|looks?|appearance|responsive|cleaner|prettier|sleeker|modern|spacing|visuals?|aesthetics?)([^a-z]|$)' || return 1
  printf '%s' "$low" | grep -Eq '(^|[^a-z])(buttons?|pages?|screens?|views?|forms?|modals?|dialogs?|navs?|navbars?|sidebars?|menus?|headers?|footers?|heroe?s?|banners?|cards?|dashboards?|panels?|tabs?|toolbars?|components?|widgets?|icons?|logos?|popups?|drop[- ]?downs?|tooltips?|badges?|carousels?|grids?|sections?|tables?|lists?|profiles?|settings|onboarding|checkouts?|paywalls?|drawers?|galler(y|ies)|feeds?)([^a-z]|$)'
}
