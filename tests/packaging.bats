#!/usr/bin/env bats
#
# Packaging guards: cheap, deterministic checks on the shipped artifact itself
# (manifests + hook wiring). These prevent classes of breakage that the logic
# tests in tasks.bats can't see — e.g. the version drifting between the two
# manifests, or a hooks.json entry pointing at a script that doesn't exist.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
}

@test "plugin.json and marketplace.json declare the same version" {
  plugin_v="$(jq -r '.version' "$ROOT/.claude-plugin/plugin.json")"
  market_v="$(jq -r '.plugins[] | select(.name=="task-queue") | .version' \
                "$ROOT/.claude-plugin/marketplace.json")"
  [ -n "$plugin_v" ]
  [ "$plugin_v" = "$market_v" ]
}

@test "all shipped JSON is valid" {
  for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json; do
    run jq empty "$ROOT/$f"
    [ "$status" -eq 0 ]
  done
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
