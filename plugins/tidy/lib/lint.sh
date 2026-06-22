#!/usr/bin/env bash
# tidy — multi-stack edit-time linters beyond Go/web. Surfaces the PROJECT's own
# linter findings for a touched file; for Python it ALSO applies the behavior-
# preserving formatter (ruff format / black) like the Go handler. No behavior-
# changing auto-fix (no eslint/ruff `--fix`), silent unless the tool is actually
# present. Sourced by bin/tidy-touch.sh alongside lib/tidy.sh (provides tidy_have).
#
# Scope boundary: edit-time linting is only for tools that are genuinely FAST and
# FILE-SCOPED (ruff, shellcheck). Slow whole-project type-checkers (clippy, mypy,
# pyright) aren't run on the edit path, and tidy does NOT reach for them on its
# own — they run only if the PROJECT declares one as its own check (its test
# command / a package.json quality script), which the Stop verification floor then
# executes. The fastest loop that can catch a class of problem owns it.

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

# Python: auto-format the touched file (behavior-preserving, like gofmt) AND
# surface ruff findings for it. Format prefers project-local `ruff format`, else
# `black`; lint is `ruff check` (no `--fix` — that can change behavior). Both are
# detect-and-run (silent when absent). Prints "<changed>\t<lintfindings>" (the
# go/web handler shape) or nothing. ruff check: exit 1 = violations, 0 = clean,
# 2+ = config error/crash (treated as no-op).
tidy_handle_python() {
  local file="$1" rbin bbin changed=0 before after lint=""
  case "$file" in *.py) ;; *) return 0 ;; esac
  rbin="$(tidy_py_bin "$file" ruff)"
  bbin="$(tidy_py_bin "$file" black)"

  # Format pass — behavior-preserving, so auto-applied. ruff format preferred.
  if [ -n "$rbin" ] || [ -n "$bbin" ]; then
    before="$(tidy_hash "$file")"
    if [ -n "$rbin" ]; then "$rbin" format "$file" >/dev/null 2>&1 || true
    else                    "$bbin" "$file"        >/dev/null 2>&1 || true
    fi
    after="$(tidy_hash "$file")"
    [ "$before" != "$after" ] && changed=1
  fi

  # Lint findings via ruff check; strip tidy_run_linter's "0\t" so we emit our own
  # changed flag.
  if [ -n "$rbin" ]; then
    lint="$(tidy_run_linter python ruff "$file" "$rbin" check "$file")"
    lint="${lint#0$'\t'}"
  fi

  [ "$changed" -eq 0 ] && [ -z "$lint" ] && return 0
  printf '%s\t%s' "$changed" "$lint"
}

# Shell: surface shellcheck findings for the touched script (the same linter this
# repo gates with). File-scoped and fast; exit 1 = issues, 0 = clean.
tidy_handle_shell() {
  local file="$1"
  case "$file" in *.sh|*.bash) ;; *) return 0 ;; esac
  tidy_have shellcheck || return 0
  tidy_run_linter shell shellcheck "$file" shellcheck -x "$file"
}
