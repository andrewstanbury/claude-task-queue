#!/usr/bin/env bash
# Shared helpers for the persisted per-repo autopilot flag + the companion task store — sourced by
# bin/autopilot.sh, the Stop hook, the ask-guard, session-start/resume, and the status line. (One
# plugin, so a shared lib is fine; the encoding MUST be identical across readers — that's why it
# lives here.)

companion_state_dir() { printf '%s' "${CLAUDE_COMPANION_STATE_DIR:-$HOME/.claude/companion}"; }

# Injective encoding of a repo root into one filename component (escape % first, then /),
# so two distinct roots never collide to the same flag file.
companion_enc() { printf '%s' "${1:-}" | sed -e 's:%:%25:g' -e 's:/:%2F:g'; }

# cwd (or a path) -> repo root, git toplevel or the path itself.
companion_root() { git -C "${1:-$PWD}" rev-parse --show-toplevel 2>/dev/null || printf '%s' "${1:-$PWD}"; }

companion_autopilot_flag() { printf '%s/autopilot/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_autopilot_on()   { [ -n "${1:-}" ] && [ -f "$(companion_autopilot_flag "$1")" ]; }

# Ship-mode (R34): while autopilot is ON, the Stop hook auto-COMMITS accumulated work to a
# non-default branch (never main, never a push) so completed work is captured as reversible
# checkpoints for the owner to review + `/companion:ship-it`.
companion_ship_flag() { printf '%s/ship/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_ship_on()   { [ -n "${1:-}" ] && [ -f "$(companion_ship_flag "$1")" ]; }

# The high-confidence, vendor-anchored credential shapes (~zero false positive). Ship-mode greps
# a staged diff against this before committing, so it never bakes a real key into a checkpoint.
# NOTE: `bin/secret-guard.sh` keeps its OWN inline copy on purpose (the enforced gate stays
# self-contained — no `lib` dependency that could make it fail open). Keep the two in sync.
companion_secret_re() { printf '%s' 'AKIA[0-9A-Z]{16}|gh[pousr]_[A-Za-z0-9]{36,}|xox[baprs]-[0-9A-Za-z-]{10,}|sk_live_[0-9A-Za-z]{16,}|AIza[0-9A-Za-z_-]{35}|-----BEGIN [A-Z ]*PRIVATE KEY-----'; }

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
      jq -r 'select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "") + (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end)' "$f" 2>/dev/null || true
    done
  done
}
