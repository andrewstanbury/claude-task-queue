#!/usr/bin/env bash
# tidy — edit-time secret floor. Scans the content an Edit/Write/MultiEdit is about
# to write for hardcoded credentials and BLOCKS before it lands (bin/tidy-presecret.sh
# exits non-zero on a hit). Pure regex, no external tool — so it protects a
# non-technical owner's project, which won't have gitleaks installed.
#
# Why this exists (the one concept imported from claude-governance, a separate system): native
# `auto`-mode + the linters scan bash COMMANDS and code STYLE, but nothing scans the
# file CONTENT an agent writes for committed secrets. A leaked key is exactly the
# irreversible harm the owner can't catch themselves. Kept deliberately narrow and
# prefix-anchored: a false positive here BLOCKS real work, so precision beats recall.
#
# Scope boundary: secrets only (highest value, lowest false-positive). TLS-off / eval
# / SQL-injection patterns from that spec are intentionally NOT here yet — they're fuzzier
# and would block legitimate edits. Sourced by bin/tidy-presecret.sh.

set -uo pipefail

# Files we must NOT scan: markdown (docs describe secret SHAPES — e.g. an AKIA
# example — and would self-trip) and test/fixture trees (they synthesize
# secret-shaped strings on purpose). Returns 0 (=exclude) when the path is exempt.
tidy_secscan_excluded() {
  case "$1" in
    *.md|*.markdown)               return 0 ;;
    */tests/*|*/test/*|*/fixtures/*|*/testdata/*) return 0 ;;
    *_test.*|*.test.*|*.spec.*|*.bats)            return 0 ;;
    *) return 1 ;;
  esac
}

# High-confidence, prefix-anchored credential shapes. Each is specific enough that a
# match is almost certainly a real secret, not a coincidence. ERE for grep -E.
# shellcheck disable=SC2016  # single-quoted regexes are intentional, not expansions
tidy_secscan_high_patterns() {
  printf '%s\n' \
    'AKIA[0-9A-Z]{16}' \
    '(ghp|gho|ghu|ghs|ghr)_[0-9A-Za-z]{36}' \
    'github_pat_[0-9A-Za-z_]{40,}' \
    'xox[abprs]-[0-9A-Za-z]{10,}' \
    '(sk|rk)_live_[0-9A-Za-z]{16,}' \
    'AIza[0-9A-Za-z_-]{35}' \
    '-----BEGIN [A-Z ]*PRIVATE KEY-----'
}

# A quoted value that's an obvious placeholder, not a real secret — keep the generic
# keyword pattern from blocking these. Case-insensitive substring check.
tidy_secscan_is_placeholder() {
  printf '%s' "$1" | grep -qiE 'xxx|changeme|change-me|example|placeholder|your[_-]|redacted|dummy|sample|fake|secret_?key_?here|<[^>]+>|\$\{|\$\(|process\.env|os\.environ|getenv'
}

# Scan TEXT (the content about to be written). Prints a short, REDACTED reason on the
# first hit (label + the offending line number, never the literal) and returns 0;
# prints nothing and returns 1 when clean. file_path only labels the message.
tidy_secscan_text() {
  local text="$1" file="${2:-}" pat line
  [ -n "$text" ] || return 1

  # 1) High-confidence prefixes — any match blocks.
  while IFS= read -r pat; do
    line="$(printf '%s\n' "$text" | grep -nE -- "$pat" | head -n1 | cut -d: -f1)"
    if [ -n "$line" ]; then
      printf 'hardcoded secret (credential-shaped literal) at line %s of %s' "$line" "${file:-the new content}"
      return 0
    fi
  done < <(tidy_secscan_high_patterns)

  # 2) Generic keyword = long-quoted-literal, minus obvious placeholders.
  local hit
  hit="$(printf '%s\n' "$text" | grep -niE '(api[_-]?key|secret|passwd|password|access[_-]?token|auth[_-]?token)["'"'"' ]*[:=][ ]*["'"'"'][^"'"'"']{16,}["'"'"']' | head -n1)"
  if [ -n "$hit" ]; then
    line="${hit%%:*}"
    # Extract just the quoted value to placeholder-check it.
    local val
    val="$(printf '%s' "$hit" | grep -oiE '["'"'"'][^"'"'"']{16,}["'"'"']' | head -n1)"
    if ! tidy_secscan_is_placeholder "$val"; then
      printf 'hardcoded credential assignment at line %s of %s' "$line" "${file:-the new content}"
      return 0
    fi
  fi
  return 1
}
