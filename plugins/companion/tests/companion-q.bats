#!/usr/bin/env bats
# The Claude-only queue (bin/q) — append-only JSONL, committed, repo-identity. Redesign D1/D2.
# Proves: event-log replay → state, and cross-machine resume via plain git (no export/import/.root).

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"; Q="$ROOT/bin/q"
  REPO="$(mktemp -d)"; git -C "$REPO" init -q
  git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
}
teardown() { rm -rf "$REPO"; }
q() { ( cd "$REPO" && "$Q" "$@" ); }

@test "q: add returns id; state shows it open with its acceptance" {
  run q add "build widget" --acc "renders"
  [ "$status" -eq 0 ]; [ "$output" = "1" ]                 # first id is 1
  run q state
  [[ "$output" == *"open   #1 build widget {acc: renders}"* ]]
}

@test "q: start→doing carries the latest note; done→done count; replay is from the log" {
  q add "a" >/dev/null; q start 1 >/dev/null; q note 1 "halfway" >/dev/null
  run q state
  [[ "$output" == *"doing  #1 a [halfway]"* ]]
  q done 1 >/dev/null
  run q state
  [[ "$output" == *"done   1"* ]]; [[ "$output" != *"doing"* ]]   # terminal → count only
}

@test "q: park and block defer to the human (parked/blocked lines)" {
  q add "pick palette" >/dev/null; q park 1 "warm vs cool? A|B (rec A)" >/dev/null
  q add "needs key" >/dev/null;    q block 2 "owner sets API key" >/dev/null
  run q state
  [[ "$output" == *"parked #1 warm vs cool? A|B (rec A)"* ]]
  [[ "$output" == *"blocked #2 owner sets API key"* ]]
}

@test "q: the store is repo-local JSONL (no machine store, no session id, no .root)" {
  q add "x" >/dev/null
  [ -f "$REPO/.companion/queue.jsonl" ]                    # lives IN the repo
  [ ! -e "$REPO/.companion/.root" ]                        # no path stamp
  run bash -c "cat '$REPO/.companion/queue.jsonl' | jq -e '.t==\"add\" and .id==1'"
  [ "$status" -eq 0 ]                                      # one append-only event line
}

@test "q: cross-machine resume is just git — commit + clone to a DIFFERENT path, state is identical" {
  q add "carry me" --acc "survives the hop" >/dev/null; q start 1 >/dev/null; q note 1 "mid" >/dev/null
  git -C "$REPO" add .companion/queue.jsonl && git -C "$REPO" commit -qm queue
  here="$(q state)"
  local CLONE; CLONE="$(mktemp -d)/at-a-different-path"; git clone -q "$REPO" "$CLONE"
  there="$( cd "$CLONE" && "$Q" state )"                   # no export, no import, no re-stamp
  [ "$here" = "$there" ]                                   # same queue, byte-for-byte
  [[ "$there" == *"doing  #1 carry me {acc: survives the hop} [mid]"* ]]
  rm -rf "$(dirname "$CLONE")"
}
