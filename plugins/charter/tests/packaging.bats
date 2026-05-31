#!/usr/bin/env bats
#
# Packaging guards for the charter plugin: manifest version sync and hook wiring.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
  MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
}

@test "plugin.json version matches this plugin's marketplace entry" {
  plugin_v="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
  market_v="$(jq -r '.plugins[] | select(.name=="charter") | .version' "$MARKETPLACE")"
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
