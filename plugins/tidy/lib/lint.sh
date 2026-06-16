#!/usr/bin/env bash
# tidy — multi-stack edit-time linters beyond Go/web. Surfaces the PROJECT's own
# linter findings for a touched file, findings-only (no auto-fix — that can change
# behavior), silent unless the tool is actually present. Sourced by
# bin/tidy-touch.sh alongside lib/tidy.sh (which provides tidy_have).
#
# Scope boundary: edit-time linting is only for tools that are genuinely FAST and
# FILE-SCOPED (ruff, shellcheck). Crate-/whole-project tools (clippy, project-wide
# mypy) stay with the verification floor (the Stop hook runs the project's own
# checks) — the fastest loop that can catch a class of problem owns it, and a
# slow whole-project linter doesn't belong on the edit path.

set -uo pipefail

# Each handler prints "0\t<findings>" (changed=0, so bin/tidy-touch.sh renders it
# as a lint block exactly like the web handler) or nothing.

# Resolve a Python CLI for the touched file: prefer a project virtualenv
# (.venv/venv walking up from the file), else PATH. Prints the path, or nothing.
tidy_py_bin() {
  local file="$1" tool="$2" dir v
  dir="$(cd "$(dirname "$file")" 2>/dev/null && pwd)" || return 1
  while [ -n "$dir" ] && [ "$dir" != "/" ]; do
    for v in .venv venv; do
      [ -x "$dir/$v/bin/$tool" ] && { printf '%s' "$dir/$v/bin/$tool"; return 0; }
    done
    dir="$(dirname "$dir")"
  done
  command -v "$tool" 2>/dev/null
}

# Python: surface the project's ruff findings for the touched file. ruff is the
# fast, file-scoped modern standard; exit 1 = violations, 0 = clean, 2+ = config
# error/crash (treated as no-op). No `--fix` — report only.
tidy_handle_python() {
  local file="$1" bin
  case "$file" in *.py) ;; *) return 0 ;; esac
  bin="$(tidy_py_bin "$file" ruff)" || return 0
  [ -n "$bin" ] || return 0
  tidy_run_linter python ruff "$file" "$bin" check "$file"
}

# Shell: surface shellcheck findings for the touched script (the same linter this
# repo gates with). File-scoped and fast; exit 1 = issues, 0 = clean.
tidy_handle_shell() {
  local file="$1"
  case "$file" in *.sh|*.bash) ;; *) return 0 ;; esac
  tidy_have shellcheck || return 0
  tidy_run_linter shell shellcheck "$file" shellcheck -x "$file"
}
