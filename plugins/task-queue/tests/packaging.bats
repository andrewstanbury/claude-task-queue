#!/usr/bin/env bats
#
# Packaging guards: cheap, deterministic checks on the shipped artifact itself
# (manifests + hook wiring). These prevent classes of breakage that the logic
# tests in tasks.bats can't see — e.g. the version drifting between the two
# manifests, or a hooks.json entry pointing at a script that doesn't exist.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"      # this plugin's root
  REPO_ROOT="$(cd "$ROOT/../.." && pwd)"           # monorepo root: plugins/<name>/ -> repo
  MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
}

@test "plugin.json version matches this plugin's marketplace entry" {
  plugin_v="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
  market_v="$(jq -r '.plugins[] | select(.name=="task-queue") | .version' "$MARKETPLACE")"
  [ -n "$plugin_v" ]
  [ "$plugin_v" = "$market_v" ]
}

@test "all shipped JSON is valid" {
  run jq empty "$ROOT/.claude-plugin/plugin.json" ; [ "$status" -eq 0 ]
  run jq empty "$ROOT/hooks/hooks.json"           ; [ "$status" -eq 0 ]
  run jq empty "$MARKETPLACE"                      ; [ "$status" -eq 0 ]
}

@test "every script referenced in hooks.json exists and is executable" {
  local cmds rel
  cmds="$(jq -r '.hooks[][].hooks[].command' "$ROOT/hooks/hooks.json")"
  [ -n "$cmds" ]
  while IFS= read -r cmd; do
    rel="$(printf '%s' "$cmd" | grep -oE 'bin/[A-Za-z0-9_-]+\.sh' || true)"
    [ -n "$rel" ] || continue
    [ -f "$ROOT/$rel" ]
    [ -x "$ROOT/$rel" ]
  done <<< "$cmds"
}

@test "every bin script a slash command invokes exists and is executable" {
  local f rel found=0
  for f in "$ROOT"/commands/*.md; do
    [ -f "$f" ] || continue
    found=1
    rel="$(grep -oE 'bin/[A-Za-z0-9_-]+\.sh' "$f" | head -n1 || true)"
    [ -n "$rel" ] || { echo "command $f references no bin script"; false; }
    [ -f "$ROOT/$rel" ] || { echo "$f -> $rel missing"; false; }
    [ -x "$ROOT/$rel" ] || { echo "$f -> $rel not executable"; false; }
  done
  [ "$found" -eq 1 ]        # guard the guard: commands/ actually has files
}
