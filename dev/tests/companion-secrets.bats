#!/usr/bin/env bats
#
# THE CREDENTIAL SCANNER - check-secrets and its fail-safe behaviour.
# Split out of companion-core.bats 2026-08-16 (audit); test names are unchanged.

load helper

@test "check-secrets: BLOCKs a real AWS key (exit 2) — advisory only, R100/Pass 3" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
}

@test "check-secrets: a generic name=value literal WARNS but does not block (exit 0) — R32" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ 'password = "hunter2primetime"' "$GUARD"
  [ "$status" -eq 0 ]                          # heuristic never had veto power; still doesn't
  [[ "$output" == *"WARN"* ]]                 # but it does warn
}

@test "check-secrets: allows a placeholder (exit 0)" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/c.py' _ 'API_KEY = "your-key-here"' "$GUARD"
  [ "$status" -eq 0 ]
}

@test "check-secrets: allows ordinary code (exit 0)" {
  run bash -c 'printf "%s" "$1" | "$2" --path /x/a.py' _ 'def add(a,b): return a+b' "$GUARD"
  [ "$status" -eq 0 ]
}

@test "check-secrets: disabled via CLAUDE_COMPANION_SECSCAN=0" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  run bash -c 'printf "%s" "$1" | CLAUDE_COMPANION_SECSCAN=0 "$2" --path /x/c.py' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 0 ]
}

# ---- per-repo feature toggles (R50): one unified surface, scoped per repo ----

@test "check-secrets: honors a per-repo secret=off flag — ALLOWS there but still BLOCKS elsewhere (isolated, R50/R54)" {
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo other; repo="$(_tmpd)"; other="$(_tmpd)"
  git -C "$repo" init -q; git -C "$other" init -q
  _feature_off secret "$repo"
  # off in $repo → allowed
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$repo"
  [ "$status" -eq 0 ]
  # still on in $other → blocked (no cross-repo bleed)
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$other"
  [ "$status" -eq 2 ]
  rm -rf "$repo" "$other"
}

@test "check-secrets FAIL-SAFE: a flag file that isn't exactly 'secret=off' still BLOCKS (R50/R54 never-fails-open)" {
  # Invariant (invisible to the user): only an exact ^secret=off$ line disables; corruption/typo -> still BLOCKS.
  local k="AKIA""ABCDEFGHIJKLMNOP"
  local repo; repo="$(_tmpd)"; git -C "$repo" init -q
  _feature_off secret "$repo"                                      # writes the flag at the enc path
  local flag; flag="$(find "${CLAUDE_COMPANION_STATE_DIR:?}/features" -type f 2>/dev/null | head -1)"
  [ -n "$flag" ]
  printf 'secret=off_typo\ngarbage\n' > "$flag"                     # NOT the exact ^secret=off$ line
  run bash -c 'printf "%s" "$1" | "$2" --path "$3/c.py"' _ "API_KEY = \"$k\"" "$GUARD" "$repo"
  [ "$status" -eq 2 ]                                               # fail-safe: corrupt flag -> still BLOCKS
  rm -rf "$repo"
}

@test "check-secrets is self-contained: sources no lib (R50/R54 never-fails-open via a dependency)" {
  # Even advisory, it should not depend on lib/companion.sh — a broken dependency should not make
  # a verdict silently vanish.
  run grep -nE '^[[:space:]]*(\.|source)[[:space:]]+.*companion\.sh' "$GUARD"
  [ "$status" -ne 0 ]
}

@test "check-secrets: blocks non-AWS anchored keys too — GH/Slack/Stripe/Google/PEM (R56 — INVARIANTS claim)" {
  # INVARIANTS.md claims six-vendor coverage but only AKIA was ever exercised. Construct each shape
  # at runtime (never a literal key in this file) so gitleaks doesn't flag the test itself.
  local pad; pad="$(printf 'a%.0s' $(seq 40))"                         # 40 alnum, ≥ each prefix's min run
  local ghp="ghp""_$pad" xox="xox""b-$pad" sk="sk_""live_$pad"
  local aiza="AIza$(printf 'a%.0s' $(seq 35))" pem="-----BEGIN ""PRIVATE KEY-----"
  for k in "$ghp" "$xox" "$sk" "$aiza" "$pem"; do
    run bash -c 'printf "%s" "$1" | "$2" --path /x/c.txt' _ "SECRET=\"$k\"" "$GUARD"
    [ "$status" -eq 2 ]                        # every recognised vendor shape blocks (exit 2), not just AWS
  done
}

# ---- decisions surfaced + recorded by /companion:docs (R41; renamed from document 2026-07-22) ----

@test "check-secrets: tool-agnostic by construction — scans whatever text it's given, notebook-sourced or not (R43)" {
  # The old gate had to specifically extract .new_source to cover NotebookEdit, because Claude Code
  # dispatched it the same PreToolUse hook as every other content tool. That dispatch is gone
  # (R100/Pass 3) — there is no more tool_input to parse, just text on stdin — so "does it cover
  # every content-writing tool" is moot BY DESIGN now, not by extra code: whatever text a notebook
  # cell's source becomes, once it's the argument, is indistinguishable from any other text.
  local k="AKIA""ABCDEFGHIJKLMNOP"                          # split so THIS file isn't a secret
  run bash -c 'printf "%s" "$1" | "$2" --path /x/n.ipynb' _ "API_KEY = \"$k\"" "$GUARD"
  [ "$status" -eq 2 ]
  [[ "$output" == *"BLOCK"* ]]
  run bash -c 'printf "%s" "$1" | "$2" --path /x/n.ipynb' _ "print(1+1)" "$GUARD"
  [ "$status" -eq 0 ]                                       # a clean cell still passes
}

@test "check-secrets: EMPTY content never scans the FILE PATH as content (no false block)" {
  # The old gate concatenated path+content into one newline-joined stdin blob and split on the
  # FIRST newline — with no content there was no newline, so the path itself became the scanned
  # text, and an Edit clearing a file under a directory literally named AKIA… was BLOCKED. That
  # coupling can't happen here BY STRUCTURE (R100/Pass 3): path arrives via --path, content only
  # ever via stdin, two separate channels, never joined into one string to mis-split. Kept as a
  # regression guard in case a future "simplify" re-couples them.
  local k="AKIA""ABCDEFGHIJKLMNOP"        # split so THIS file isn't itself a secret
  run bash -c 'printf "%s" "$1" | "$2" --path "/tmp/$3/notes.txt"' _ "" "$GUARD" "$k"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
