#!/usr/bin/env bats
#
# Packaging guards for the hud plugin: version sync, valid JSON, and the
# status-line script. hud has no hooks (it's a statusLine, not hook-driven).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  REPO_ROOT="$(cd "$ROOT/../.." && pwd)"
  MARKETPLACE="$REPO_ROOT/.claude-plugin/marketplace.json"
}

@test "plugin.json version matches this plugin's marketplace entry" {
  plugin_v="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
  market_v="$(jq -r '.plugins[] | select(.name=="hud") | .version' "$MARKETPLACE")"
  [ -n "$plugin_v" ]
  [ "$plugin_v" = "$market_v" ]
}

@test "all shipped JSON is valid" {
  run jq empty "$ROOT/.claude-plugin/plugin.json" ; [ "$status" -eq 0 ]
  run jq empty "$MARKETPLACE"                      ; [ "$status" -eq 0 ]
}

@test "the status-line script exists and is executable" {
  [ -f "$ROOT/bin/hud-status.sh" ]
  [ -x "$ROOT/bin/hud-status.sh" ]
}
