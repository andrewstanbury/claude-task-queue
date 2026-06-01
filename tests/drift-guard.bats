#!/usr/bin/env bats
#
# Cross-plugin DRIFT GUARD. The install boundary (see AGENTS.md) forbids a shared
# library, so charter's project-doc detection is duplicated by hand into hud
# (hud_qa/hud_map/hud_roadmap) and task-queue (tq_roadmap_path/tq_decisions_path).
# That duplication silently drifts (it did: hud_qa once missed QUALITY.adoc /
# docs/CLAUDE.md / the override). charter is the source of truth; this test runs
# every recognized doc layout through charter AND each mirror and asserts they
# agree — so a future change to charter's rules that a mirror doesn't match fails
# CI. Cheaper than a runtime inventory (zero runtime code, no staleness).
#
# This is a repo-level test (sources libs from multiple plugins); it runs in the
# dev/CI repo where all plugins coexist, NOT at install time — so it doesn't
# violate the runtime install boundary.

setup() {
  R="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$R/plugins/charter/lib/charter.sh"
  . "$R/plugins/hud/lib/hud.sh"
  . "$R/plugins/task-queue/lib/project.sh"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"
}
teardown() { rm -rf "$(dirname "$REPO")"; }

# charter "documented"/path-present  <=>  consumer boolean (1/0)
present() { [ "$1" = documented ] || { [ -n "$1" ] && [ "$1" != missing ]; }; }

# `|| true` on each call: the path detectors return non-zero when a doc isn't
# found (empty output is the real signal), which is harmless in production but
# trips bats' ERR trap on a bare assignment.
assert_qa_agree() {   # charter_qa_status (documented/missing) vs hud_qa (1/0)
  local c h; c="$(charter_qa_status "$REPO" || true)"; h="$(hud_qa "$REPO" || true)"
  if present "$c"; then [ "$h" = 1 ]; else [ "$h" = 0 ]; fi
}
assert_map_agree() {
  local c h; c="$(charter_map_path "$REPO" || true)"; h="$(hud_map "$REPO" || true)"
  if [ -n "$c" ]; then [ "$h" = 1 ]; else [ "$h" = 0 ]; fi
}
assert_roadmap_agree() {
  local c h t
  c="$(charter_roadmap_path "$REPO" || true)"; h="$(hud_roadmap "$REPO" || true)"; t="$(tq_roadmap_path "$REPO" || true)"
  if [ -n "$c" ]; then [ "$h" = 1 ] && [ -n "$t" ]; else [ "$h" = 0 ] && [ -z "$t" ]; fi
}
assert_decisions_agree() {   # charter vs task-queue (hud has no decisions slot)
  local c t; c="$(charter_decisions_path "$REPO" || true)"; t="$(tq_decisions_path "$REPO" || true)"
  if [ -n "$c" ]; then [ -n "$t" ]; else [ -z "$t" ]; fi
}

@test "QA detection: hud_qa matches charter across every recognized layout" {
  assert_qa_agree                                    # none → both missing
  : > "$REPO/QUALITY.md";        assert_qa_agree; rm "$REPO/QUALITY.md"
  : > "$REPO/QUALITY.adoc";      assert_qa_agree; rm "$REPO/QUALITY.adoc"   # the original drift
  mkdir -p "$REPO/docs"
  : > "$REPO/docs/QUALITY.md";   assert_qa_agree; rm "$REPO/docs/QUALITY.md"
  printf '# m\n## Non-functional requirements\n' > "$REPO/docs/CLAUDE.md"; assert_qa_agree; rm "$REPO/docs/CLAUDE.md"
  printf '# m\nquality attribute: x\n' > "$REPO/README.md"; assert_qa_agree; rm "$REPO/README.md"
}

@test "QA detection: the CLAUDE_CHARTER_QA_FILE override agrees too" {
  export CLAUDE_CHARTER_QA_FILE="nfr.md"
  assert_qa_agree                                    # override set, file absent → missing
  : > "$REPO/nfr.md"; assert_qa_agree                # present → both documented
}

@test "map detection: hud_map matches charter across every recognized layout" {
  assert_map_agree
  mkdir -p "$REPO/docs"
  : > "$REPO/docs/MAP.md";        assert_map_agree; rm "$REPO/docs/MAP.md"
  : > "$REPO/MAP.md";             assert_map_agree; rm "$REPO/MAP.md"
  : > "$REPO/docs/ARCHITECTURE.md"; assert_map_agree; rm "$REPO/docs/ARCHITECTURE.md"
  : > "$REPO/ARCHITECTURE.md";    assert_map_agree; rm "$REPO/ARCHITECTURE.md"
}

@test "roadmap detection: hud_roadmap + tq_roadmap_path match charter" {
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
