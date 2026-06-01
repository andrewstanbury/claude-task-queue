#!/usr/bin/env bats
#
# Tests for the charter plugin: the quality-attributes gate + source-aware
# SessionStart nudge, and charter-doctor. Faked via a temp git repo and
# CLAUDE_CHARTER_* overrides.

setup() {
  ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  STANDARD="$ROOT/bin/charter-standard.sh"
  DOCTOR="$ROOT/bin/charter-doctor.sh"
  REPO="$(mktemp -d)/proj"; mkdir -p "$REPO"; git -C "$REPO" init -q
  export CLAUDE_CHARTER_LOG_DIR="$(mktemp -d)"
}

teardown() { rm -rf "$(dirname "$REPO")" "$CLAUDE_CHARTER_LOG_DIR"; }

run_standard() {
  local src="${1:-startup}" json
  json="$(jq -nc --arg c "$REPO" --arg s "$src" '{cwd:$c, source:$s}')"
  printf '%s' "$json" | "$STANDARD" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null || true
}

@test "non-web project: QA is not a baseline nudge; it scales up by complexity" {
  run run_standard startup                        # bare non-web repo
  [[ "$output" == *"Generate the missing baseline docs"* ]]
  [[ "$output" == *"Document proportionally to complexity"* ]]
  [[ "$output" == *"quality-attribute targets"* ]]   # mentioned as scale-up, not demanded
  [[ "$output" != *"no documented quality attributes"* ]]
}

@test "lean reminder on compact when QA is missing" {
  run run_standard compact
  [[ "$output" == *"(reminder)"* ]]
  [[ "$output" != *"no documented quality attributes"* ]]
}

@test "QA documented: appears in the consult brief (startup)" {
  printf '# Quality Attributes\n- perf: p95 < 200ms\n' > "$REPO/QUALITY.md"
  run run_standard startup
  [[ "$output" == *"consult as relevant"* ]]
  [[ "$output" == *"quality attributes"* ]]
}

@test "silent on compact when QA is documented" {
  printf '# Quality Attributes\n' > "$REPO/QUALITY.md"
  run run_standard compact
  [ -z "$output" ]
}

@test "orientation points at the project map on a fresh context" {
  run run_standard startup                      # QA + map missing
  [[ "$output" == *"docs/MAP.md"* ]]
  [[ "$output" == *"re-scanning"* ]]
  printf '# Quality Attributes\n' > "$REPO/QUALITY.md"
  run run_standard startup                      # QA documented, map still missing
  [[ "$output" == *"docs/MAP.md"* ]]
}

@test "omits orientation/map nudge in lean mode (token-light)" {
  run run_standard compact                      # QA missing → lean reminder only
  [[ "$output" != *"MAP.md"* ]]
  [[ "$output" != *"re-scanning"* ]]
}

@test "qa-status: missing, then documented via QUALITY.md / CLAUDE.md section (ADRs do NOT count)" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  : > "$REPO/QUALITY.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "documented" ]

  rm "$REPO/QUALITY.md"; mkdir -p "$REPO/docs/adr"; : > "$REPO/docs/adr/0001-x.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]                       # ADRs are decisions, not QA (untangled)

  rm -rf "$REPO/docs"; printf '## Non-functional requirements\n' > "$REPO/CLAUDE.md"
  run bash -c "$src"' charter_qa_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "documented" ]
}

@test "doctor reports QA status (missing then documented)" {
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"not documented"* ]]
  : > "$REPO/QUALITY.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"quality attributes are documented"* ]]
}

@test "roadmap-status: missing, then present via docs/ROADMAP.md" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_roadmap_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  mkdir -p "$REPO/docs"; : > "$REPO/docs/ROADMAP.md"
  run bash -c "$src"' charter_roadmap_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]

  run bash -c "$src"' charter_roadmap_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "docs/ROADMAP.md" ]
}

@test "nudges to generate a roadmap/backlog file when missing (startup)" {
  run run_standard startup
  [[ "$output" == *"docs/ROADMAP.md"* ]]
  [[ "$output" == *"backlog"* ]]
  [[ "$output" == *"Now/Next/Later"* ]]   # baseline gap, generated from the codebase/git
}

@test "surfaces the roadmap in the consult brief when present (startup)" {
  mkdir -p "$REPO/docs"; printf '# Roadmap\n## Next\n- ship it\n' > "$REPO/docs/ROADMAP.md"
  run run_standard startup
  [[ "$output" == *"docs/ROADMAP.md"* ]]
  [[ "$output" == *"consult as relevant"* ]]
  [[ "$output" == *"backlog"* ]]
}

@test "omits the roadmap nudge in lean mode (token-light)" {
  run run_standard compact                      # QA + roadmap missing → lean QA reminder only
  [[ "$output" != *"ROADMAP.md"* ]]
  [[ "$output" != *"backlog"* ]]
}

@test "doctor reports roadmap status (missing then present)" {
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"no roadmap/backlog file"* ]]
  mkdir -p "$REPO/docs"; : > "$REPO/docs/ROADMAP.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"docs/ROADMAP.md"* ]]
}

@test "map-status: missing, then present via docs/MAP.md (and ARCHITECTURE.md)" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_map_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  mkdir -p "$REPO/docs"; : > "$REPO/docs/MAP.md"
  run bash -c "$src"' charter_map_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]
  run bash -c "$src"' charter_map_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "docs/MAP.md" ]

  rm "$REPO/docs/MAP.md"; : > "$REPO/ARCHITECTURE.md"   # recognise an existing convention
  run bash -c "$src"' charter_map_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]
}

@test "nudges to generate a project map from the codebase when missing (startup)" {
  run run_standard startup
  [[ "$output" == *"docs/MAP.md"* ]]
  [[ "$output" == *"file"*"responsibility"* ]]   # file->responsibility index
}

@test "consults the existing map (no generate) when present (startup)" {
  printf '# Architecture\n- bin/ — entrypoints\n' > "$REPO/ARCHITECTURE.md"
  run run_standard startup
  [[ "$output" == *"ARCHITECTURE.md"* ]]
  [[ "$output" == *"consult as relevant"* ]]
  [[ "$output" != *"project map (docs/MAP.md)"* ]]   # not in the baseline gap list
}

@test "doctor reports project-map status (missing then present)" {
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"no project map"* ]]
  : > "$REPO/ARCHITECTURE.md"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"ARCHITECTURE.md"* ]]
}

@test "is-web: no by default; web via index.html / package.json dep; env override wins" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_is_web "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "no" ]

  : > "$REPO/index.html"
  run bash -c "$src"' charter_is_web "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "web" ]

  rm "$REPO/index.html"; printf '{"dependencies":{"react":"^18.0.0"}}\n' > "$REPO/package.json"
  run bash -c "$src"' charter_is_web "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "web" ]

  CLAUDE_CHARTER_WEB=0 run bash -c "$src"' charter_is_web "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "no" ]                           # override forces non-web

  rm "$REPO/package.json"
  CLAUDE_CHARTER_WEB=1 run bash -c "$src"' charter_is_web "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "web" ]                          # override forces web
}

@test "web project + missing QA: nudge bakes in Lighthouse-aligned defaults (startup)" {
  : > "$REPO/index.html"
  run run_standard startup
  [[ "$output" == *"web project"* ]]
  [[ "$output" == *"Core Web Vitals"* ]]
  [[ "$output" == *"progressive enhancement"* ]]
  [[ "$output" == *"print"* ]]
  [[ "$output" == *"reuse existing before creating"* ]]   # components-by-default principle
}

@test "non-web project: no web QA specifics in the brief" {
  run run_standard startup
  [[ "$output" != *"progressive enhancement"* ]]
  [[ "$output" != *"Core Web Vitals"* ]]
}

@test "CLAUDE_CHARTER_WEB=0 suppresses the web QA gap even with index.html" {
  : > "$REPO/index.html"
  CLAUDE_CHARTER_WEB=0 run run_standard startup
  [[ "$output" != *"progressive enhancement"* ]]
  [[ "$output" != *"Core Web Vitals"* ]]
}

@test "doctor flags a web project's best-practice defaults" {
  printf '{"dependencies":{"vue":"^3.0.0"}}\n' > "$REPO/package.json"
  run bash -c 'cd "$1" && bash "$2"' _ "$REPO" "$DOCTOR"
  [[ "$output" == *"web project"* ]]
}

@test "decisions-status: missing, then present via DECISIONS.md / docs/adr/" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_decisions_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  printf '# Decisions\n' > "$REPO/DECISIONS.md"
  run bash -c "$src"' charter_decisions_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]
  run bash -c "$src"' charter_decisions_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "DECISIONS.md" ]

  rm "$REPO/DECISIONS.md"; mkdir -p "$REPO/docs/adr"; : > "$REPO/docs/adr/0001-x.md"
  run bash -c "$src"' charter_decisions_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "docs/adr/" ]
}

@test "decisions: scale-up mention when missing (not demanded), consult when present" {
  run run_standard startup
  [[ "$output" == *"capture the evident decisions (DECISIONS.md/ADRs)"* ]]  # scale-up, not a gap nag
  [[ "$output" != *"No decision record"* ]]
  [[ "$output" != *"alignment anchor"* ]]               # no anchor when there are no decisions
  printf '# Decisions\n- chose X over Y\n' > "$REPO/DECISIONS.md"
  run run_standard startup
  [[ "$output" == *"consult as relevant"* ]]
  [[ "$output" == *"decisions"* ]]
}

@test "decisions are the alignment anchor: present brief says consult before reversing" {
  printf '# Decisions\n- chose X over Y\n' > "$REPO/DECISIONS.md"
  run run_standard startup
  [[ "$output" == *"alignment anchor"* ]]
  [[ "$output" == *"reverse or contradict"* ]]
}

@test "alignment anchor is dropped under the claude-companion quiet marker" {
  # decisions present + marker -> the consult brief (incl. the anchor) goes quiet,
  # the standing policy lives in CLAUDE.md instead.
  printf '# Decisions\n- chose X over Y\n' > "$REPO/DECISIONS.md"
  printf '%s\n' '<!-- claude-companion -->' > "$REPO/CLAUDE.md"
  printf '# MAP\n' > "$REPO/docs/MAP.md" 2>/dev/null || { mkdir -p "$REPO/docs"; printf '# MAP\n' > "$REPO/docs/MAP.md"; }
  printf '# ROADMAP\n' > "$REPO/docs/ROADMAP.md"
  run run_standard startup
  [[ "$output" != *"alignment anchor"* ]]
}

@test "quiet mode: claude-companion marker drops the consult brief, keeps baseline gaps" {
  # baseline present + marker -> charter is silent
  mkdir -p "$REPO/docs"; : > "$REPO/docs/ROADMAP.md"; : > "$REPO/docs/MAP.md"
  printf '# CLAUDE.md\nsummary <!-- claude-companion -->\n' > "$REPO/CLAUDE.md"
  run run_standard startup
  [ -z "$output" ]                                 # baseline present + marked → silent

  # remove the map only -> the map baseline gap survives; the consult brief stays dropped
  rm "$REPO/docs/MAP.md"
  run run_standard startup
  [[ "$output" == *"project map (docs/MAP.md)"* ]]  # baseline gap kept
  [[ "$output" != *"consult as relevant"* ]]        # consult brief dropped (marked)
}

@test "bootstrap tip points at the claude-companion marker when unmarked but docs exist" {
  : > "$REPO/QUALITY.md"
  run run_standard startup
  [[ "$output" == *"claude-companion"* ]]
}

@test "recent-commits: returns non-merge commit subjects newest-first" {
  printf 'x\n' > "$REPO/a"; git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "first subject"
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_recent_commits "$2" 5' bash "$ROOT" "$REPO"
  [[ "$output" == *"first subject"* ]]
}

@test "roadmap reconcile: surfaces recently-merged commits when a roadmap is present" {
  mkdir -p "$REPO/docs"; printf '# Roadmap\n' > "$REPO/docs/ROADMAP.md"
  git -C "$REPO" add -A
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q -m "feat: do the thing"
  run run_standard startup
  [[ "$output" == *"recent commits"* ]]
  [[ "$output" == *"do the thing"* ]]
}

@test "roadmap reconcile: no reconcile line in a repo with no commits" {
  mkdir -p "$REPO/docs"; printf '# Roadmap\n' > "$REPO/docs/ROADMAP.md"
  run run_standard startup                      # REPO inited but no commits
  [[ "$output" != *"Reconcile the backlog"* ]]
}

@test "stack-status: missing, then present via STACK.md / a Stack heading" {
  src='. "$1/lib/charter.sh";'
  run bash -c "$src"' charter_stack_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "missing" ]

  printf '# Stack\n- Go 1.22\n' > "$REPO/STACK.md"
  run bash -c "$src"' charter_stack_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]
  run bash -c "$src"' charter_stack_path "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "STACK.md" ]

  rm "$REPO/STACK.md"; printf '# Manual\n## Tech Stack\n- Next.js\n' > "$REPO/CLAUDE.md"
  run bash -c "$src"' charter_stack_status "$2"' bash "$ROOT" "$REPO"
  [ "$output" = "present" ]
}

@test "stack: scale-up mention when missing (not demanded), consult when present" {
  run run_standard startup
  [[ "$output" == *"stack notes (STACK.md)"* ]]   # mentioned as scale-up, not a gap nag
  [[ "$output" != *"No stack notes"* ]]
  printf '# Stack\n- Go 1.22\n' > "$REPO/STACK.md"
  run run_standard startup
  [[ "$output" == *"consult as relevant"* ]]
  [[ "$output" == *"stack"* ]]
}

@test "SessionStart output is valid JSON with the SessionStart event name" {
  json="$(jq -nc --arg c "$REPO" '{cwd:$c, source:"startup"}')"
  run bash -c 'printf "%s" "$1" | "$2" | jq -r .hookSpecificOutput.hookEventName' _ "$json" "$STANDARD"
  [ "$output" = "SessionStart" ]
}

@test "prune: bounds the activity log (no cruft)" {
  seq 1 2500 > "$CLAUDE_CHARTER_LOG_DIR/activity.log"
  run bash -c '. "$1/lib/charter.sh"; charter_prune_log' _ "$ROOT"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CLAUDE_CHARTER_LOG_DIR/activity.log")" -eq 1000 ]
}

# ---- /charter:align (alignment check) ---------------------------------------

run_align() { ( cd "$REPO" && "$ROOT/bin/charter-align.sh" ); }

@test "align: bare repo reports no anchors to check against" {
  run run_align
  [ "$status" -eq 0 ]
  [[ "$output" == *"Decisions / ADRs: none recorded"* ]]
  [[ "$output" == *"Roadmap / backlog: none recorded"* ]]
  [[ "$output" == *"No recorded direction to align against"* ]]
}

@test "align: surfaces the decisions anchor with the do-not-reverse framing" {
  printf '# Decisions\n- Use bash + jq, no build step.\n' > "$REPO/DECISIONS.md"
  run run_align
  [[ "$output" == *"DECISIONS.md"* ]]
  [[ "$output" == *"do not reverse or contradict"* ]]
}

@test "align: surfaces the roadmap as the recorded direction" {
  mkdir -p "$REPO/docs"; printf '# Roadmap\n## Now\n- ship it\n' > "$REPO/docs/ROADMAP.md"
  run run_align
  [[ "$output" == *"docs/ROADMAP.md"* ]]
  [[ "$output" == *"recorded direction"* ]]
}

@test "align: surfaces recently-landed commits for reconciliation" {
  git -C "$REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m "feat: a landed thing"
  run run_align
  [[ "$output" == *"Recently landed"* ]]
  [[ "$output" == *"a landed thing"* ]]
}

@test "align: output is plain text, exits clean even with no git history" {
  run run_align
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}
