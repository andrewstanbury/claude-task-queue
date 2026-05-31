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
}

# Run CMD in ROOT, print a bounded tail of combined output, and return its exit
# code. Best-effort: a runner that isn't found just exits non-zero like a failure.
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
