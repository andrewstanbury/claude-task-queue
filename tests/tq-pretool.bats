#!/usr/bin/env bats
# Pretool gate behavior + the v0.1.1 regex-anchoring fix that prevents
# destructive-substring false positives in PR body args, commit messages,
# and other quoted content.

setup() {
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  HOOK="$THIS_DIR/bin/tq-pretool.sh"
  cd "$CLAUDE_TQ_STATE_DIR"
}

teardown() {
  rm -rf "$CLAUDE_TQ_STATE_DIR"
}

# Helper: invoke the hook with a synthetic tool payload and return decision JSON
# (empty when the hook silently passes).
invoke() {
  local tool="$1"
  local cmd="$2"
  jq -nc --arg t "$tool" --arg c "$cmd" '{tool_name: $t, tool_input: {command: $c}}' \
    | bash "$HOOK"
}

@test "Read tool is silently low-risk" {
  out="$(invoke Read "")"
  [ -z "$out" ]
}

@test "destructive: rm -rf at start blocks" {
  out="$(invoke Bash 'rm -rf /tmp/foo')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "destructive: rm -rf after && still blocks (clause boundary)" {
  out="$(invoke Bash 'cd /tmp && rm -rf foo')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "destructive: rm -rf after ; still blocks" {
  out="$(invoke Bash 'cd /tmp; rm -rf foo')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "v0.1.1 fix: gh release create inside --body does NOT block" {
  out="$(invoke Bash 'gh pr create --base main --body "...gh release create v1.0.0..."')"
  [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r '.decision // ""')" != "block" ]
}

@test "v0.1.1 fix: rm -rf inside --body does NOT block" {
  out="$(invoke Bash 'git commit -m "fix: rm -rf was overly broad"')"
  [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r '.decision // ""')" != "block" ]
}

@test "v0.1.1 fix: gh pr merge in PR body text does NOT block on gh pr create" {
  out="$(invoke Bash 'gh pr create --body "Run gh pr merge after this"')"
  [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r '.decision // ""')" != "block" ]
}

@test "v0.1.1 fix: backslash escapes in quoted body do NOT trigger destructive match" {
  # Caught live during v0.1.1 release: commit -m with backslash-escaped
  # quotes around `gh release create` was matching because the char class
  # [\&;\|] treated literal backslash as a clause boundary. Fix tightened
  # the class to [&;|] only. Lock it down here.
  out="$(invoke Bash 'git commit -m "blah \"gh release create\" blah"')"
  [ -z "$out" ] || [ "$(printf '%s' "$out" | jq -r '.decision // ""')" != "block" ]
}

@test "destructive: gh pr merge at start blocks" {
  out="$(invoke Bash 'gh pr merge 24 --squash --delete-branch')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "destructive: git push --force blocks" {
  out="$(invoke Bash 'git push --force origin main')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "destructive: eas update blocks" {
  out="$(invoke Bash 'eas update --branch main')"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
}

@test "low-risk Bash: git status silent" {
  out="$(invoke Bash 'git status')"
  [ -z "$out" ]
}

@test "low-risk Bash: ls silent" {
  out="$(invoke Bash 'ls -1')"
  [ -z "$out" ]
}

@test "write op while paused blocks" {
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  tq_ensure_state
  : > "$(tq_pause_path)"
  out="$(invoke Edit "")"
  [ "$(printf '%s' "$out" | jq -r '.decision')" = "block" ]
  [[ "$(printf '%s' "$out" | jq -r '.reason')" == *"paused"* ]]
}

@test "destructive op while paused still blocks with destructive reason" {
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/queue.sh"
  tq_ensure_state
  : > "$(tq_pause_path)"
  out="$(invoke Bash 'rm -rf /tmp/x')"
  # Destructive check runs first; the reason should mention destructive,
  # not paused — that ordering matters because destructive is always-block,
  # paused is project-state.
  [[ "$(printf '%s' "$out" | jq -r '.reason')" == *"destructive"* ]]
}
