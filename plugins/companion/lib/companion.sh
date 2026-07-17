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
# Clear the flag (single source of truth — autopilot.sh `off` and resume.sh both use this so the
# teardown can't drift). Best-effort; a missing flag is not an error.
companion_autopilot_clear() { rm -f "$(companion_autopilot_flag "${1:-}")" 2>/dev/null || true; }

# Ship-mode (R34): while autopilot is ON, the Stop hook auto-COMMITS accumulated work to a
# non-default branch (never main, never a push) so completed work is captured as reversible
# checkpoints for the owner to review + `/companion:ship-it`.
companion_ship_flag() { printf '%s/ship/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
companion_ship_on()   { [ -n "${1:-}" ] && [ -f "$(companion_ship_flag "$1")" ]; }

# Per-repo feature toggles (R50) — a single per-repo file storing only OFF overrides, one
# `<feature>=off` line each. Absence of a line ⇒ the feature's default (secret/steering
# default ON). This is the unified surface `/companion:features` writes and every enforced-core
# hook reads; env var (CLAUDE_COMPANION_SECSCAN) stays as a *global* override that wins,
# so a per-repo flag never fights CI. autopilot/ship keep their own flag files (their commands own
# that state) — `features` just reflects+delegates them, no duplicate source of truth.
# NOTE: the self-contained hook (secret-guard.sh) MUST NOT source this lib — it
# reads the file with an inline grep instead; keep that path/encoding in sync with companion_enc.
companion_feature_file()  { printf '%s/features/%s' "$(companion_state_dir)" "$(companion_enc "${1:-}")"; }
# 0 (true) only when the feature is *explicitly* turned off for this repo — fail-safe: any read
# error leaves the feature at its default (on), never silently disables an enforced gate.
companion_feature_off()   { [ -n "${2:-}" ] && grep -qs "^${1:-}=off\$" "$(companion_feature_file "$2")"; }
companion_feature_state() { companion_feature_off "${1:-}" "${2:-}" && printf off || printf on; }
# Set a feature on|off for a repo. `off` records the override line; `on` removes it (back to default).
companion_feature_set() {
  local feat="${1:-}" root="${2:-}" val="${3:-}" f; f="$(companion_feature_file "$root")"
  [ -n "$feat" ] && [ -n "$root" ] || return 1
  mkdir -p "$(dirname "$f")" 2>/dev/null || true
  local rest=""; [ -f "$f" ] && rest="$(grep -v "^${feat}=" "$f" 2>/dev/null || true)"
  { [ -n "$rest" ] && printf '%s\n' "$rest"; [ "$val" = "off" ] && printf '%s=off\n' "$feat"; } >"$f" 2>/dev/null || true
}

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
      jq -r 'select(.status=="pending" or .status=="in_progress") | "  ◻ " + (.subject // "") + (if (.done_when//"")!="" then "\n       └ done when: " + .done_when else "" end) + (if ((.notes//[])|length)>0 then "\n       └ note: " + ((.notes[-1].text)//"") elif (.description//"")!="" then "\n       └ note: " + .description else "" end)' "$f" 2>/dev/null || true
    done
  done
}
