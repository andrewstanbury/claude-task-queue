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
