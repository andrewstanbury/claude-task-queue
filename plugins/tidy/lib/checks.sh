#!/usr/bin/env bash
# tidy — project-checks library: discover and run the project's OWN tests.
#
# The verification floor: rather than reimplement per-language tooling, we run
# what the project already declares, so a non-technical owner gets the one signal
# they can trust — "the tests pass" — without lifting a finger. Read-only except
# it executes the project's test command (tests should be side-effect-free).
# Sourced by bin/tidy-verify.sh (the Stop hook).

set -uo pipefail

# Echo the project's test command (runnable via `sh -c`), or nothing. Prefers
# what the project declares; only returns a command whose runner is installed, so
# a missing toolchain degrades to silence rather than a spurious failure.
tidy_test_command() {
  local root="$1" t
  # Explicit override wins (for projects whose test command we can't infer).
  [ -n "${CLAUDE_TIDY_TEST_CMD:-}" ] && { printf '%s' "$CLAUDE_TIDY_TEST_CMD"; return 0; }
  [ -d "$root" ] || return 0
  if [ -f "$root/package.json" ] && command -v npm >/dev/null 2>&1; then
    t="$(jq -r '.scripts.test // empty' "$root/package.json" 2>/dev/null || true)"
    case "$t" in
      ""|*"no test specified"*) ;;                 # placeholder / absent → skip
      *) printf 'npm test --silent'; return 0 ;;
    esac
  fi
  if [ -f "$root/go.mod" ] && command -v go >/dev/null 2>&1; then
    printf 'go test ./...'; return 0
  fi
  if [ -f "$root/Cargo.toml" ] && command -v cargo >/dev/null 2>&1; then
    printf 'cargo test'; return 0
  fi
  if command -v pytest >/dev/null 2>&1 \
     && { [ -f "$root/pyproject.toml" ] || [ -f "$root/pytest.ini" ] || [ -f "$root/tox.ini" ] || [ -d "$root/tests" ]; }; then
    printf 'pytest -q'; return 0
  fi
  if [ -f "$root/Makefile" ] && command -v make >/dev/null 2>&1 \
     && grep -qE '^test:' "$root/Makefile" 2>/dev/null; then
    printf 'make test'; return 0
  fi
  # Make-free fallback: a conventional root check/test script (covers repos like
  # this one that gate with ./check.sh, and anything without a package manifest).
  local s
  for s in check.sh test.sh scripts/test scripts/test.sh; do
    [ -x "$root/$s" ] && { printf './%s' "$s"; return 0; }
  done
}

# Run CMD in ROOT, print a bounded tail of combined output, and return its exit
# code. Best-effort: a runner that isn't found just exits non-zero like a failure.
# A content fingerprint of the working-tree changes (tracked diff vs HEAD +
# untracked file contents). Lets the Stop hook skip a re-run when nothing has
# changed since the last green verify. Empty outside a git repo (no throttle there).
tidy_tree_hash() {
  local root="$1" f
  git -C "$root" rev-parse >/dev/null 2>&1 || return 0
  {
    git -C "$root" diff HEAD 2>/dev/null
    git -C "$root" ls-files --others --exclude-standard 2>/dev/null \
      | while IFS= read -r f; do cksum "$root/$f" 2>/dev/null; done
  } | cksum | awk '{print $1"-"$2}'
}

# Bounded so a slow/hanging test command can never stall Claude Code's turn
# completion. `timeout` exit 124 propagates so the caller can treat it as "could
# not verify" rather than a failure to loop on. CLAUDE_TIDY_VERIFY_TIMEOUT secs
# (default 180); if `timeout` isn't installed, runs unbounded (best-effort).
tidy_run_checks() {
  local root="$1" cmd="$2" out rc t="${CLAUDE_TIDY_VERIFY_TIMEOUT:-180}"
  if command -v timeout >/dev/null 2>&1; then
    out="$(cd "$root" 2>/dev/null && timeout "$t" sh -c "$cmd" 2>&1)"; rc=$?
  else
    out="$(cd "$root" 2>/dev/null && sh -c "$cmd" 2>&1)"; rc=$?
  fi
  printf '%s' "$out" | tail -n 30
  return "$rc"
}

# Detect a CONFIGURED Python type-checker and echo its quality gate
# ("typecheck<TAB><cmd>"), or nothing. Needs BOTH a project config (so we honor the
# project's own intent, not a blanket check) AND the tool on PATH — detect-and-run,
# matching tidy_test_command's pytest discovery; installs nothing. mypy, else
# pyright. This is the Python arm of the quality floor (no package.json needed).
tidy_py_typecheck_gate() {
  local root="$1"
  if command -v mypy >/dev/null 2>&1 \
     && { [ -f "$root/mypy.ini" ] \
          || grep -q '^\[tool\.mypy\]' "$root/pyproject.toml" 2>/dev/null \
          || grep -q '^\[mypy\]' "$root/setup.cfg" 2>/dev/null; }; then
    printf 'typecheck\tmypy .\n'; return 0
  fi
  if command -v pyright >/dev/null 2>&1 \
     && { [ -f "$root/pyrightconfig.json" ] \
          || grep -q '^\[tool\.pyright\]' "$root/pyproject.toml" 2>/dev/null; }; then
    printf 'typecheck\tpyright\n'; return 0
  fi
}

# Discover the project's OWN declared quality gates beyond its test command —
# typecheck, a11y/perf, and architecture (dependency rules) — from package.json
# scripts (npm/pnpm/yarn) AND a configured Python type-checker (mypy/pyright, no
# package.json needed). The verification floor runs these so the bar the PROJECT
# already set is enforced, without inventing or installing anything (detect-and-run,
# like tidy_test_command). Prints "label<TAB>command" per gate.
# CLAUDE_TIDY_QUALITY_CMD overrides with a single synthetic gate (manual/testing).
# Empty when disabled, or with no recognised gate.
tidy_quality_commands() {
  local root="$1" pm pkg s label
  [ "${CLAUDE_TIDY_QUALITY_FLOOR:-1}" = "0" ] && return 0
  if [ -n "${CLAUDE_TIDY_QUALITY_CMD:-}" ]; then
    printf 'quality\t%s\n' "$CLAUDE_TIDY_QUALITY_CMD"; return 0
  fi
  tidy_py_typecheck_gate "$root"                 # Python arm (works without package.json)
  pkg="$root/package.json"; [ -f "$pkg" ] || return 0
  pm=npm
  [ -f "$root/pnpm-lock.yaml" ] && pm=pnpm
  [ -f "$root/yarn.lock" ] && pm=yarn
  while IFS= read -r s; do
    case "$s" in
      typecheck|type-check|tsc|types)                         label=typecheck ;;
      a11y|test:a11y|lighthouse|lhci|test:lighthouse)         label='a11y/perf' ;;
      depcruise|dependency-cruiser|deps:check|arch|arch:check|boundaries) label=architecture ;;
      *) continue ;;
    esac
    printf '%s\t%s run %s\n' "$label" "$pm" "$s"
  done < <(jq -r '.scripts // {} | keys[]' "$pkg" 2>/dev/null)
}
