#!/usr/bin/env bats
#
# Cross-plugin DRIFT GUARD. The install boundary (see AGENTS.md) forbids a shared
# library, so charter's project-doc detection is duplicated by hand into
# task-queue (tq_roadmap_path / tq_decisions_path — the capture nudge weighs new
# work against the roadmap and recorded decisions). That duplication silently
# drifts; charter is the source of truth, so this test runs every recognized doc
# layout through charter AND each mirror and asserts they agree — a future change
# to charter's rules a mirror doesn't match fails CI. Cheaper than a runtime
# inventory (zero runtime code, no staleness).
#
# (hud used to mirror charter's QA/map/roadmap detection for a docs-health slot;
# that slot was removed, so those mirrors — the heaviest drift risk — are gone.)
#
# This is a repo-level test (sources libs from multiple plugins); it runs in the
# dev/CI repo where all plugins coexist, NOT at install time — so it doesn't
# violate the runtime install boundary.

setup() {
  R="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$R/plugins/charter/lib/charter.sh"
  . "$R/plugins/task-queue/lib/project.sh"
  # tidy mirrors charter's scar-tissue detector (tidy_hotspots) for its regression
  # gate — sourced here so the guard below can assert byte-identical output.
  . "$R/plugins/tidy/lib/tidy.sh"
  . "$R/plugins/tidy/lib/coverage.sh"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"
}
teardown() { rm -rf "$(dirname "$REPO")"; }

# `|| true` on each call: the path detectors return non-zero when a doc isn't
# found (empty output is the real signal), which is harmless in production but
# trips bats' ERR trap on a bare assignment.
assert_roadmap_agree() {   # charter_roadmap_path vs tq_roadmap_path
  local c t; c="$(charter_roadmap_path "$REPO" || true)"; t="$(tq_roadmap_path "$REPO" || true)"
  if [ -n "$c" ]; then [ -n "$t" ]; else [ -z "$t" ]; fi
}
assert_decisions_agree() {   # charter vs task-queue
  local c t; c="$(charter_decisions_path "$REPO" || true)"; t="$(tq_decisions_path "$REPO" || true)"
  if [ -n "$c" ]; then [ -n "$t" ]; else [ -z "$t" ]; fi
}

@test "roadmap detection: tq_roadmap_path matches charter across every layout" {
  assert_roadmap_agree
  mkdir -p "$REPO/docs"
  : > "$REPO/docs/ROADMAP.md";  assert_roadmap_agree; rm "$REPO/docs/ROADMAP.md"
  : > "$REPO/ROADMAP.md";       assert_roadmap_agree; rm "$REPO/ROADMAP.md"
  : > "$REPO/docs/BACKLOG.md";  assert_roadmap_agree; rm "$REPO/docs/BACKLOG.md"
  : > "$REPO/BACKLOG.md";       assert_roadmap_agree; rm "$REPO/BACKLOG.md"
}

@test "decisions detection: tq_decisions_path matches charter" {
  assert_decisions_agree
  : > "$REPO/DECISIONS.md";      assert_decisions_agree; rm "$REPO/DECISIONS.md"
  mkdir -p "$REPO/docs/adr"
  : > "$REPO/docs/adr/0001-x.md"; assert_decisions_agree; rm -rf "$REPO/docs/adr"
  mkdir -p "$REPO/docs/decisions"
  : > "$REPO/docs/decisions/0001-y.md"; assert_decisions_agree
}

@test "hotspots detection: tidy_hotspots is byte-identical to charter_hotspots" {
  git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  # mixed history: a scar file (fixes) + a healthy file (no fixes) + a deleted file.
  echo a > "$REPO/scar.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "feat: add scar"
  echo b > "$REPO/scar.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "fix: scar bug"
  echo c > "$REPO/scar.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "fix: scar regression"
  for i in 1 2 3; do echo "$i" > "$REPO/active.txt"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m "feat: extend $i"; done
  local c t
  c="$(charter_hotspots "$REPO" 5 || true)"
  t="$(tidy_hotspots "$REPO" 5 || true)"
  [ "$c" = "$t" ]
  [ -n "$c" ]                                  # guard the guard: there IS a hotspot to compare
}

@test "open-questions: hud_open_questions count agrees with task-queue's tq_open_questions" {
  . "$R/plugins/task-queue/lib/tasks.sh"
  . "$R/plugins/hud/lib/hud.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/sD"
  jq -n '{id:"1",subject:"❓ one",status:"pending"}'        > "$CLAUDE_TQ_TASKS_DIR/sD/1.json"
  jq -n '{id:"2",subject:"❓ two",status:"in_progress"}'    > "$CLAUDE_TQ_TASKS_DIR/sD/2.json"
  jq -n '{id:"3",subject:"plain work",status:"pending"}'   > "$CLAUDE_TQ_TASKS_DIR/sD/3.json"
  jq -n '{id:"4",subject:"❓ done",status:"completed"}'     > "$CLAUDE_TQ_TASKS_DIR/sD/4.json"
  local hud_n tq_n
  hud_n="$(hud_open_questions sD)"
  tq_n="$(tq_open_questions sD | grep -c .)"
  [ "$hud_n" = "$tq_n" ]
  [ "$hud_n" = "2" ]
  rm -rf "$CLAUDE_TQ_TASKS_DIR"
}

@test "disabled-floor marker: every flag hud checks is still honored by a sibling" {
  # hud's 🛡✗ marker reads the floors' CLAUDE_*=0 disable flags by name (install
  # boundary forbids importing them). If a sibling renamed its flag, the marker would
  # silently miss that disabled floor — so assert each name hud lists is still gated
  # on by some sibling hook/lib (its owner). The flag names are the source of truth in
  # the siblings; this guards hud's hand-copied list against drift.
  local flags f
  # The floor flags are written ${NAME:-1} (default-on); the CLAUDE_HUD_* dir vars use
  # a path default, so this pattern selects exactly the disable flags, not those.
  flags="$(grep -oE 'CLAUDE_[A-Z_]+:-1\}' "$R/plugins/hud/lib/hud.sh" | sed 's/:-1}//' | sort -u)"
  [ -n "$flags" ]                                  # guard the guard: hud does reference flags
  for f in $flags; do
    grep -rqE "\\\$\{$f:-1\}" "$R/plugins/tidy/bin" "$R/plugins/tidy/lib" \
      "$R/plugins/charter/bin" "$R/plugins/task-queue/bin" \
      || { echo "hud checks $f but no sibling honors it as \${$f:-1}"; false; }
  done
}

@test "README plugin versions match the marketplace (can't silently drift)" {
  local readme="$R/README.md" market="$R/.claude-plugin/marketplace.json" p mv rv
  for p in task-queue tidy charter hud; do
    mv="$(jq -r --arg n "$p" '.plugins[]|select(.name==$n)|.version' "$market")"
    rv="$(grep -E "^\| \*\*$p\*\* \|" "$readme" | sed -E 's/^\| \*\*[a-z-]+\*\* \| *([0-9.]+) *\|.*/\1/')"
    [ -n "$mv" ]
    [ "$rv" = "$mv" ] || { echo "README $p=$rv but marketplace=$mv"; false; }
  done
}
