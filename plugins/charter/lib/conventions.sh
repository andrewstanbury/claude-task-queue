#!/usr/bin/env bash
# charter — established-conventions detection (language-agnostic).
#
# Split out of lib/charter.sh (size guard); charter.sh sources this, so every
# consumer gets these helpers transitively. Read-only (install boundary): it
# inspects the project, never writes it.

set -uo pipefail

# The project's ESTABLISHED conventions, detected LANGUAGE-AGNOSTICALLY: which
# dependency MANIFEST the project uses (the file that records its actual stack), its
# source layout, and whether it already has a test surface. This primes "reuse before
# create" for ANY ecosystem — we name WHERE the conventions live and let the model
# (which already knows every framework) read them, instead of hardcoding a framework
# allowlist that only covers one ecosystem and rots. Prints a compact "label: value; …"
# summary, or nothing when there isn't enough signal (so a bare repo stays silent
# rather than guess). One detection per session — token-cheap.
charter_conventions() {
  local root="$1" parts=() man="" src="" tests="" d m
  [ -n "$root" ] || return 0

  # Dependency manifest → ecosystem label. The manifest is the source of truth for the
  # project's stack, so naming it points the model straight at what to reuse. First
  # match wins; the model reads the file for the specifics (deps, versions, scripts).
  for m in \
    "package.json:Node/JS (package.json)" \
    "Cargo.toml:Rust (Cargo.toml)" \
    "go.mod:Go (go.mod)" \
    "pyproject.toml:Python (pyproject.toml)" \
    "requirements.txt:Python (requirements.txt)" \
    "Pipfile:Python (Pipfile)" \
    "Gemfile:Ruby (Gemfile)" \
    "composer.json:PHP (composer.json)" \
    "pom.xml:Java/Maven (pom.xml)" \
    "build.gradle:JVM/Gradle (build.gradle)" \
    "build.gradle.kts:JVM/Gradle (build.gradle.kts)" \
    "pubspec.yaml:Dart/Flutter (pubspec.yaml)" \
    "mix.exs:Elixir (mix.exs)" \
    "project.godot:Godot (project.godot)" \
    "deno.json:Deno (deno.json)"; do
    [ -f "$root/${m%%:*}" ] && { man="${m#*:}"; break; }
  done
  # .NET / Xcode identify by glob, not a fixed filename. Check each glob separately —
  # `ls a.csproj *.sln` exits non-zero when only one side matches.
  [ -z "$man" ] && { ls "$root"/*.csproj >/dev/null 2>&1 || ls "$root"/*.sln >/dev/null 2>&1; } && man=".NET (*.csproj)"
  [ -z "$man" ] && ls -d "$root"/*.xcodeproj >/dev/null 2>&1 && man="Xcode project"

  # Source layout — where to reuse existing modules/patterns from.
  for d in src app lib source; do [ -d "$root/$d" ] && { src="$d/"; break; }; done

  # Test surface — a convention to follow (dir-based; language-agnostic).
  for d in tests test spec __tests__; do [ -d "$root/$d" ] && { tests="present ($d/)"; break; }; done

  [ -n "$man" ]   && parts+=("stack: $man")
  [ -n "$src" ]   && parts+=("source in $src")
  [ -n "$tests" ] && parts+=("tests: $tests")
  [ "${#parts[@]}" -gt 0 ] || return 0        # not enough signal → stay silent

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
