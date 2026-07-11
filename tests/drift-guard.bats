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
  : > "$REPO/docs/decisions/0001-y.md"; assert_decisions_agree; rm -rf "$REPO/docs/decisions"
  # the requirements ledger is the lowest-priority decisions match in BOTH detectors
  : > "$REPO/REQUIREMENTS.md";   assert_decisions_agree
  # ...and a dedicated DECISIONS.md still wins over the ledger, in both
  : > "$REPO/DECISIONS.md"
  local c t; c="$(charter_decisions_path "$REPO" || true)"; t="$(tq_decisions_path "$REPO" || true)"
  [ "$c" = "DECISIONS.md" ] && [ "$t" = "DECISIONS.md" ]
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

# (The hud_worklist ⇄ tq_open_worklist mirror test was removed with hud's 📋-count slot —
# the task list is a `tq report` now, not a status-line mirror. tq_open_worklist is still
# exercised in task-queue's own away/drain tests, where it's now the sole consumer.)

# The two deferral markers must stay DISJOINT: ❓ [parked] decisions (hold the gate) vs
# ⏳ [blocked] owner-action items (surfaced, not gated). A ⏳ item must never leak into the
# ❓ count and vice-versa, in either plugin — else the gate would fire on the wrong pile.
@test "parked markers: hud ❓ and ⏳ counters are disjoint" {
  . "$R/plugins/hud/lib/hud.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/sE"
  jq -n '{id:"1",subject:"❓ decide auth",status:"pending"}'       > "$CLAUDE_TQ_TASKS_DIR/sE/1.json"
  jq -n '{id:"2",subject:"❓ decide schema",status:"in_progress"}' > "$CLAUDE_TQ_TASKS_DIR/sE/2.json"
  jq -n '{id:"3",subject:"⏳ plug in the Deck",status:"pending"}'  > "$CLAUDE_TQ_TASKS_DIR/sE/3.json"
  jq -n '{id:"4",subject:"plain work",status:"pending"}'          > "$CLAUDE_TQ_TASKS_DIR/sE/4.json"
  [ "$(hud_open_questions sE)" = "2" ]   # ❓ only — ⏳ does not leak in
  [ "$(hud_blocked sE)" = "1" ]          # ⏳ only — ❓ does not leak in
  rm -rf "$CLAUDE_TQ_TASKS_DIR"
}

@test "edit-gates: hud's 🔒/🎨 readers agree with task-queue's marker locations" {
  # hud mirrors two task-queue edit-gate markers by reconstructing their path convention
  # (install boundary forbids sharing the lib). If task-queue moved a marker or renamed a
  # prefix, hud would silently miss it — so drive the REAL writers and assert hud sees them.
  . "$R/plugins/task-queue/lib/tasks.sh"
  . "$R/plugins/task-queue/lib/away.sh"
  . "$R/plugins/task-queue/lib/capture.sh"
  . "$R/plugins/hud/lib/hud.sh"
  local d; d="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$d" CLAUDE_HUD_AWAY_DIR="$d"
  # review gate (per-repo): task-queue writes it, hud must see the same file
  [ "$(hud_review_pending /a/repo)" = "0" ]
  tq_review_set /a/repo;   [ "$(hud_review_pending /a/repo)" = "1" ]
  tq_review_clear /a/repo; [ "$(hud_review_pending /a/repo)" = "0" ]
  # design gate (per-session): relocated into the shared away dir so hud can read it
  [ "$(hud_design_pending sess1)" = "0" ]
  tq_design_set sess1;   [ "$(hud_design_pending sess1)" = "1" ]
  tq_design_clear sess1; [ "$(hud_design_pending sess1)" = "0" ]
  rm -rf "$d"
}

@test "feature toggles: hud_away/hud_agent agree with task-queue's writers AND follow its dir relocation" {
  # The status line's headline slots (✈️ autopilot · 🤖 agents) are a hand-mirror of
  # task-queue's flag files across the install boundary. Two ways that silently lies,
  # both asserted here: (1) hud must read the SAME dir/encoding the real writer uses, and
  # (2) hud must CHAIN through task-queue's own relocation var — so we set ONLY the
  # CLAUDE_TQ_* dir (never CLAUDE_HUD_*) and confirm hud still sees the flag.
  . "$R/plugins/task-queue/lib/tasks.sh"
  . "$R/plugins/task-queue/lib/away.sh"
  . "$R/plugins/hud/lib/hud.sh"
  local d; d="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$d/away" CLAUDE_TQ_AGENT_DIR="$d/agent"
  unset CLAUDE_HUD_AWAY_DIR CLAUDE_HUD_AGENT_DIR CLAUDE_TQ_AGENT_MODE
  mkdir -p "$CLAUDE_TQ_AWAY_DIR" "$CLAUDE_TQ_AGENT_DIR"
  # away/autopilot: writer file → hud reads 1 (proves dir-chain + encoding agree)
  [ "$(hud_away /a/repo)" = "0" ]
  : > "$(tq_away_file /a/repo)";   [ "$(hud_away /a/repo)" = "1" ]
  rm -f "$(tq_away_file /a/repo)"; [ "$(hud_away /a/repo)" = "0" ]
  # agents: on-flag → 1; "off" tombstone → 0 (both plugins honor the tombstone the same way)
  [ "$(hud_agent /a/repo)" = "0" ]
  : > "$(tq_agent_file /a/repo)";          [ "$(hud_agent /a/repo)" = "1" ]
  printf 'off' > "$(tq_agent_file /a/repo)"; [ "$(hud_agent /a/repo)" = "0" ]
  rm -rf "$d"
}

@test "worktree root: hud and tq_root_for_cwd both normalize a linked worktree to the primary" {
  # A per-repo flag is keyed by root. In a linked worktree --show-toplevel is the WORKTREE
  # path, so a flag set from the main checkout would be invisible there → status line lies.
  # Both resolvers now fold a worktree back to its primary; assert they (a) normalize and
  # (b) agree — hud-status.sh inlines the identical git-common-dir resolution.
  . "$R/plugins/task-queue/lib/tasks.sh"
  git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  echo x > "$REPO/f"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m init
  local wt="$REPO/wt" gcd hud_root tq_root
  git -C "$REPO" worktree add -q "$wt" -b feat
  tq_root="$(tq_root_for_cwd "$wt")"
  # hud-status.sh's inline resolution (kept byte-aligned with the block there):
  gcd="$(git -C "$wt" rev-parse --git-common-dir 2>/dev/null || true)"
  hud_root="$(cd "$wt" 2>/dev/null && cd "$(dirname "$gcd")" 2>/dev/null && pwd)"
  [ "$tq_root" != "$wt" ]          # normalized AWAY from the worktree path
  [ "$hud_root" = "$tq_root" ]     # and the two resolvers converge — the whole point
}

@test "submodule root: hud and tq_root_for_cwd resolve a submodule to its OWN toplevel, not .git/modules" {
  # A submodule's git-common-dir is <super>/.git/modules/<name>; its parent lands inside
  # .git and is SHARED across sibling submodules — so without the guard, every submodule of
  # a superproject collides to one bogus flag key. Both resolvers must fall back to the
  # submodule's own --show-toplevel, and agree (hud-status.sh inlines the same resolution).
  . "$R/plugins/task-queue/lib/tasks.sh"
  local st; st="$(mktemp -d)"; local sub="$st/sub"; mkdir -p "$sub"
  git -C "$sub" init -q; git -C "$sub" config user.email t@t; git -C "$sub" config user.name t
  echo a > "$sub/a"; git -C "$sub" add -A; git -C "$sub" commit -q -m init
  git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
  echo b > "$REPO/b"; git -C "$REPO" add -A; git -C "$REPO" commit -q -m init
  git -C "$REPO" -c protocol.file.allow=always submodule add -q "$sub" mod
  local subwt tq_root gcd hud_root
  subwt="$(cd "$REPO/mod" && pwd)"
  tq_root="$(tq_root_for_cwd "$subwt")"
  # hud-status.sh's inline resolution (kept byte-aligned with the block there):
  gcd="$(git -C "$subwt" rev-parse --git-common-dir 2>/dev/null || true)"
  hud_root="$(cd "$subwt" 2>/dev/null && cd "$(dirname "$gcd")" 2>/dev/null && pwd)"
  case "$hud_root" in */.git|*/.git/*) hud_root="" ;; esac
  [ -n "$hud_root" ] || hud_root="$(git -C "$subwt" rev-parse --show-toplevel 2>/dev/null || true)"
  [ "$tq_root" = "$subwt" ]         # the submodule's own working root, NOT …/.git/modules
  [ "$hud_root" = "$tq_root" ]      # and the two resolvers converge
  rm -rf "$st"
}

@test "counter whitespace: an indented ❓/⏳ subject still counts, and hud agrees with task-queue" {
  # task-queue's marker predicates strip leading whitespace before matching (a stray space
  # must not flip a parked item into "work"); hud's counters didn't, so an indented " ❓ …"
  # counted in task-queue but not hud. Guard the two against re-drifting on that strip.
  . "$R/plugins/task-queue/lib/tasks.sh"
  . "$R/plugins/hud/lib/hud.sh"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/sW"
  jq -n '{id:"1",subject:"  ❓ indented decide",status:"pending"}'    > "$CLAUDE_TQ_TASKS_DIR/sW/1.json"
  jq -n '{id:"2",subject:"❓ flush decide",status:"pending"}'         > "$CLAUDE_TQ_TASKS_DIR/sW/2.json"
  jq -n '{id:"3",subject:"   ⏳ indented blocked",status:"pending"}'  > "$CLAUDE_TQ_TASKS_DIR/sW/3.json"
  [ "$(hud_open_questions sW)" = "2" ]
  [ "$(tq_open_questions sW | grep -c .)" = "2" ]      # both readers agree, indent included
  [ "$(hud_blocked sW)" = "1" ]
  rm -rf "$CLAUDE_TQ_TASKS_DIR"
}

@test "flag encoding: previously-colliding roots get DISTINCT keys, and hud mirrors it" {
  # The old '/'→'-' scheme was not injective: /a/foo-bar and /a/foo/bar both encoded to
  # '-a-foo-bar', so two unrelated repos SHARED autopilot/agent/review state. tq_enc_root
  # percent-encodes '/' so they diverge; hud_enc_root must mirror it byte-for-byte.
  . "$R/plugins/task-queue/lib/tasks.sh"
  . "$R/plugins/task-queue/lib/away.sh"
  . "$R/plugins/hud/lib/hud.sh"
  [ "$(tq_enc_root /a/foo-bar)" != "$(tq_enc_root /a/foo/bar)" ]      # no longer collide
  [ "$(tq_enc_root /a/foo/bar)" = "$(hud_enc_root /a/foo/bar)" ]      # both plugins agree
  # end to end: away flag set for one root must NOT show as on for the colliding root
  local d; d="$(mktemp -d)"
  export CLAUDE_TQ_AWAY_DIR="$d" CLAUDE_HUD_AWAY_DIR="$d"
  : > "$(tq_away_file /a/foo-bar)"
  [ "$(hud_away /a/foo-bar)" = "1" ]      # the repo we set
  [ "$(hud_away /a/foo/bar)" = "0" ]      # the once-colliding repo is unaffected
  rm -rf "$d"
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
