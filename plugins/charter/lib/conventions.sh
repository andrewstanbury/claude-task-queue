#!/usr/bin/env bash
# charter — established-conventions detection.
#
# Split out of lib/charter.sh (size guard); charter.sh sources this, so every
# consumer gets these helpers transitively. Read-only (install boundary): it
# inspects the project, never writes it.

set -uo pipefail

# The project's ESTABLISHED conventions — the existing component library, styling
# system, state approach, components directory, and test framework. This is what
# lets new work REUSE what's there instead of introducing a parallel pattern the
# owner has to clean up later; charter surfaces it (see charter-standard.sh) so
# "reuse before create" is concrete (names the actual library), not just a slogan.
#
# Detection only: package.json deps + a few config files/dirs. Focused on the
# UI/web surface where "don't reinvent the component library" actually bites;
# prints a compact "Label: value; …" summary, or nothing when there isn't enough
# signal (so non-web projects stay silent rather than guess). One detection per
# session — token-cheap.
charter_conventions() {
  local root="$1" pkg parts=() ui="" style="" state="" tests="" comps="" d
  [ -n "$root" ] || return 0
  pkg="$root/package.json"
  _has() { [ -f "$pkg" ] && grep -qiE "\"$1\"[[:space:]]*:" "$pkg" 2>/dev/null; }

  # UI / component library (the headline convention).
  [ -f "$root/components.json" ]            && ui="shadcn/ui"
  [ -z "$ui" ] && _has '@mui/material'      && ui="MUI"
  [ -z "$ui" ] && _has '@chakra-ui/react'   && ui="Chakra UI"
  [ -z "$ui" ] && _has 'antd'               && ui="Ant Design"
  [ -z "$ui" ] && _has '@mantine/core'      && ui="Mantine"
  [ -z "$ui" ] && _has '@radix-ui/.*'       && ui="Radix UI"
  [ -z "$ui" ] && _has 'react-bootstrap'    && ui="React-Bootstrap"
  [ -z "$ui" ] && _has 'bootstrap'          && ui="Bootstrap"
  [ -z "$ui" ] && _has 'vuetify'            && ui="Vuetify"

  # Styling system.
  { [ -f "$root/tailwind.config.js" ] || [ -f "$root/tailwind.config.ts" ] || \
    [ -f "$root/tailwind.config.cjs" ] || [ -f "$root/tailwind.config.mjs" ] || _has 'tailwindcss'; } \
                                            && style="Tailwind"
  [ -z "$style" ] && _has 'styled-components' && style="styled-components"
  [ -z "$style" ] && _has '@emotion/react'  && style="Emotion"
  [ -z "$style" ] && _has 'sass'            && style="Sass"

  # State management.
  _has '@reduxjs/toolkit' && state="Redux Toolkit"
  [ -z "$state" ] && _has 'redux'           && state="Redux"
  [ -z "$state" ] && _has 'zustand'         && state="Zustand"
  [ -z "$state" ] && _has 'jotai'           && state="Jotai"
  [ -z "$state" ] && _has 'mobx'            && state="MobX"
  [ -z "$state" ] && _has 'pinia'           && state="Pinia"
  [ -z "$state" ] && { _has '@tanstack/react-query' || _has 'react-query'; } && state="TanStack Query"

  # Test framework.
  _has 'vitest' && tests="Vitest"
  [ -z "$tests" ] && _has 'jest'            && tests="Jest"
  [ -z "$tests" ] && { _has '@playwright/test' || _has 'playwright'; } && tests="Playwright"
  [ -z "$tests" ] && _has 'cypress'         && tests="Cypress"

  # Components directory (where to reuse from).
  for d in src/components app/components components src/lib/components lib/components; do
    [ -d "$root/$d" ] && { comps="$d/"; break; }
  done

  unset -f _has 2>/dev/null || true
  [ -n "$ui" ]    && parts+=("UI: $ui")
  [ -n "$comps" ] && parts+=("components in $comps")
  [ -n "$style" ] && parts+=("styling: $style")
  [ -n "$state" ] && parts+=("state: $state")
  [ -n "$tests" ] && parts+=("tests: $tests")
  [ "${#parts[@]}" -gt 0 ] || return 0       # not enough signal → stay silent

  local out="" p
  for p in "${parts[@]}"; do [ -z "$out" ] && out="$p" || out="$out; $p"; done
  printf '%s' "$out"
}

# "documented" if the project records its conventions (a CONVENTIONS doc, or a
# Conventions section in the map/manual/decisions), else "missing". Once recorded
# they live in docs Claude already reads, so charter stops surfacing them.
charter_conventions_status() {
  local root="$1" f
  [ -n "$root" ] || { printf 'missing'; return 0; }
  for f in CONVENTIONS.md docs/CONVENTIONS.md; do
    [ -f "$root/$f" ] && { printf 'documented'; return 0; }
  done
  for f in CLAUDE.md AGENTS.md docs/CLAUDE.md docs/MAP.md MAP.md DECISIONS.md docs/DECISIONS.md; do
    [ -f "$root/$f" ] && grep -qiE '^#+[[:space:]]*conventions?[[:space:]]*$|established conventions' "$root/$f" 2>/dev/null \
      && { printf 'documented'; return 0; }
  done
  printf 'missing'
}
