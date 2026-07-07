#!/usr/bin/env bats
#
# TOKEN-BUDGET NFR — the project's defining quality attribute, enforced.
#
# Every hook injects context into the model's turn, and token efficiency is the
# whole point — so each injection carries a CHARACTER budget (~4 chars/token). This
# runs the REAL hooks in their representative path and fails CI if any exceeds its
# budget, so a future feature can't silently bloat a hook. The recurring injections
# (SessionStart steady-state, per-prompt) are budgeted tightest because they
# multiply; per-event Stop blocks get more room because they're pay-per-event.
#
# Budgets are ~30% over the measured baseline (2026-06-17). Growing one is a
# DELIBERATE RATCHET: bump the number here, in the same change, with a one-line why.

setup() {
  R="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  export CLAUDE_TQ_TASKS_DIR="$(mktemp -d)"
  export CLAUDE_TQ_STATE_DIR="$(mktemp -d)"
  export CLAUDE_CHARTER_LOG_DIR="$(mktemp -d)"
  export CLAUDE_TIDY_LOG_DIR="$(mktemp -d)"
  WORK="$(mktemp -d)"
}
teardown() {
  rm -rf "$CLAUDE_TQ_TASKS_DIR" "$CLAUDE_TQ_STATE_DIR" "$CLAUDE_CHARTER_LOG_DIR" "$CLAUDE_TIDY_LOG_DIR" "$WORK"
}

ctx() { jq -r '.hookSpecificOutput.additionalContext // ""'; }
rsn() { jq -r '.reason // .systemMessage // ""'; }

# within <name> <max-chars> <text> — print the measure, fail if over budget.
within() {
  local name="$1" max="$2" c="${#3}"
  echo "  $name: $c / $max chars"
  [ "$c" -le "$max" ]
}

# a marked, well-set-up repo with a scar-tissue hotspot (steady-state SessionStart)
marked_repo() {
  local d="$1"; mkdir -p "$d/docs"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  printf '# x <!-- claude-companion -->\n' > "$d/CLAUDE.md"
  printf '# m\n' > "$d/docs/MAP.md"; printf '# r\n' > "$d/docs/ROADMAP.md"
  printf '# d\n- use `Postgres`\n' > "$d/DECISIONS.md"
  printf 'echo a\n' > "$d/auth.sh"; git -C "$d" add -A; git -C "$d" commit -qm "feat: x"
  printf 'echo b\n' >> "$d/auth.sh"; git -C "$d" add -A; git -C "$d" commit -qm "fix: a"
  printf 'echo c\n' >> "$d/auth.sh"; git -C "$d" add -A; git -C "$d" commit -qm "fix: b"
}

@test "token budget: SessionStart steady-state (marked repo) stays lean" {
  local repo="$WORK/m"; marked_repo "$repo"
  local ss; ss="$(jq -nc --arg c "$repo" '{cwd:$c, source:"startup"}')"
  within "charter quiet+scar" 540  "$(printf '%s' "$ss" | "$R/plugins/charter/bin/charter-standard.sh" | ctx)"
  within "tidy quiet"         640  "$(printf '%s' "$ss" | "$R/plugins/tidy/bin/tidy-standard.sh" | ctx)"
  within "task-queue lean"    1280 "$(printf '%s' "$ss" | "$R/plugins/task-queue/bin/tq-resume.sh" | ctx)"
}

@test "token budget: per-prompt injections" {
  local repo="$WORK/p"; mkdir -p "$repo"; git -C "$repo" init -q
  cap() { jq -nc --arg p "$1" --arg s s --arg c "$repo" '{prompt:$p, session_id:$s, cwd:$c}' \
            | "$R/plugins/task-queue/bin/tq-capture.sh" | ctx; }
  # Ratchet DOWN 2026-06-27 (split-from-interrupt): the DEFAULT path is now a LEAN
  # re-anchor (~420), not the full procedure+critique — that rides the SessionStart
  # policy now. The heavy present-and-approve+critique fires only on the deterministic
  # high-stakes signal, so it gets its OWN budget (capture consequential) below.
  within "capture substantive"   600 "$(cap 'add the login form and wire it and test it')"
  within "capture consequential" 1800 "$(cap 'delete the user accounts table')"
  within "capture design"        1800 "$(cap 'make the login page cleaner')"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/s"
  jq -n '{id:"1",subject:"❓ Block or warn?",status:"pending"}' > "$CLAUDE_TQ_TASKS_DIR/s/1.json"
  # Isolate the open-Q reminder by putting the repo in SOLO mode: since 2026-06-26 the
  # review loop fires on EVERY prompt (incl. 'thanks'), so solo suppresses the loop
  # while the reminder still rides — measuring the reminder alone, as this budget intends.
  # CLAUDE_TQ_PRESENT_WINDOW=0 = lights-out autopilot: even the owner's own prompt is
  # treated as absent, so the loop stays suppressed here (a fresh prompt would otherwise
  # be "present" and re-enable the interactive loop — measured on its own line below).
  export CLAUDE_TQ_AWAY_DIR="$WORK/away"; mkdir -p "$CLAUDE_TQ_AWAY_DIR"
  : > "$CLAUDE_TQ_AWAY_DIR/$(printf '%s' "$repo" | sed 's:/:-:g')"
  within "open-Q reminder"     280  "$(CLAUDE_TQ_PRESENT_WINDOW=0 cap 'thanks')"
  # away + owner PRESENT (fresh prompt this turn): the interactive loop fires with a
  # present-note prefix that overrides the standing "never ask" banner. Fires only on
  # this away+present path, so the normal-path budgets above are untouched.
  within "capture away-present" 900 "$(cap 'add the login form and wire it and test it')"
  # agent-mode fan-out injection: a fresh (non-away) repo/session with 2 independent
  # ready tasks + agent-mode on. Rides alongside the loop; opt-in, so normal paths pay 0.
  local fp="$WORK/fan"; mkdir -p "$fp"; git -C "$fp" init -q
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/fan"
  jq -n '{id:"1",subject:"build the header",status:"pending",blocks:[],blockedBy:[]}' > "$CLAUDE_TQ_TASKS_DIR/fan/1.json"
  jq -n '{id:"2",subject:"build the footer",status:"pending",blocks:[],blockedBy:[]}' > "$CLAUDE_TQ_TASKS_DIR/fan/2.json"
  capf() { jq -nc --arg p "$1" --arg s fan --arg c "$fp" '{prompt:$p, session_id:$s, cwd:$c}' \
             | "$R/plugins/task-queue/bin/tq-capture.sh" | ctx; }
  within "capture agent-fanout" 1000 "$(CLAUDE_TQ_AGENT_MODE=on capf 'thanks')"
}

@test "token budget: MCP probe is silent at rest, bounded when warning" {
  local repo="$WORK/mcp"; mkdir -p "$repo"; git -C "$repo" init -q
  export CLAUDE_MCP_HOME_CONFIG="$WORK/no-home.json"   # never read real ~/.claude.json
  export CLAUDE_CHARTER_MCP_TIMEOUT=1
  local ss; ss="$(jq -nc --arg c "$repo" '{cwd:$c, source:"startup"}')"
  probe() { printf '%s' "$ss" | "$R/plugins/charter/bin/charter-mcp-probe.sh" | ctx; }
  within "mcp probe at rest" 0 "$(probe)"             # no servers declared → silent
  printf '%s' '{"mcpServers":{"ghost":{"command":"definitely-not-a-real-cmd-xyz"}}}' > "$repo/.mcp.json"
  within "mcp probe warning" 560 "$(probe)"           # pay-per-event, one down server
}

@test "token budget: Stop-gate blocks (pay-per-event)" {
  local g="$WORK/g"; mkdir -p "$g"
  git -C "$g" init -q; git -C "$g" config user.email t@t; git -C "$g" config user.name t
  printf 'echo a\n' > "$g/a.sh"; git -C "$g" add -A; git -C "$g" commit -qm init
  printf 'we use `Postgres`\n' > "$g/DECISIONS.md"
  printf '{"dependencies":{"mongodb":"^6"}}\n' > "$g/package.json"
  printf 'echo b\n' >> "$g/a.sh"
  local S; S="$(jq -nc --arg c "$g" --arg s zz '{cwd:$c, session_id:$s}')"
  within "align block"   660 "$(printf '%s' "$S" | "$R/plugins/charter/bin/charter-align-gate.sh" | rsn)"
  printf 'add rate limiting\n' > "$CLAUDE_TQ_STATE_DIR/intent-zz"
  within "intent block"  850 "$(printf '%s' "$S" | "$R/plugins/task-queue/bin/tq-verify.sh" | rsn)"
  # away/solo auto-continue block (pay-per-event Stop): away flag on + open queue work.
  export CLAUDE_TQ_AWAY_DIR="$WORK/away"; mkdir -p "$CLAUDE_TQ_AWAY_DIR"
  : > "$CLAUDE_TQ_AWAY_DIR/$(printf '%s' "$g" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_TASKS_DIR/zz"
  jq -n '{id:"1",subject:"wire the checkout flow",status:"pending"}' > "$CLAUDE_TQ_TASKS_DIR/zz/1.json"
  # ratchet 760→960: tq_park_rule gained a "never stall on the absent owner — default to
  # your recommendation" clause (owner request), which rides into this per-Stop nudge.
  within "away continue"  960 "$(printf '%s' "$S" | "$R/plugins/task-queue/bin/tq-verify.sh" | rsn)"
  # ask-guard deny (pay-per-event PreToolUse): reason lives in permissionDecisionReason.
  local AG; AG="$(printf '%s' "$S" | "$R/plugins/task-queue/bin/tq-ask-guard.sh" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  within "ask-guard deny" 780 "$AG"   # ratchet 620→780: same never-stall clause in tq_park_rule
  # review-guard deny (pay-per-event PreToolUse): armed marker + a parked ❓ for this repo.
  export CLAUDE_TQ_PROJECTS_DIR="$WORK/rg-proj"
  RG_ENC="$(printf '%s' "$g" | sed 's:/:-:g')"
  mkdir -p "$CLAUDE_TQ_PROJECTS_DIR/$RG_ENC"; printf '{"cwd":"%s"}\n' "$g" > "$CLAUDE_TQ_PROJECTS_DIR/$RG_ENC/zz.jsonl"
  jq -n '{id:"2",subject:"❓ [parked] pick the storage backend",status:"pending"}' > "$CLAUDE_TQ_TASKS_DIR/zz/2.json"
  : > "$CLAUDE_TQ_AWAY_DIR/review-$RG_ENC"
  local RG; RG="$(printf '%s' "$S" | "$R/plugins/task-queue/bin/tq-review-guard.sh" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  within "review-guard deny" 520 "$RG"
  # design-guard deny (pay-per-event PreToolUse): a pending design preview, owner present.
  : > "$CLAUDE_TQ_STATE_DIR/design-zz"
  date +%s > "$CLAUDE_TQ_AWAY_DIR/present-zz"   # owner present → gate active (not a drain)
  local DG; DG="$(printf '%s' "$S" | "$R/plugins/task-queue/bin/tq-design-guard.sh" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  within "design-guard deny" 520 "$DG"
  within "quality block" 360 "$(printf '%s' "$S" | CLAUDE_TIDY_QUALITY_CMD='echo ERR; exit 1' "$R/plugins/tidy/bin/tidy-verify.sh" | rsn)"
  within "diagnose block" 950 "$(printf '%s' "$S" | CLAUDE_TIDY_LOG_DIR="$WORK/dl" CLAUDE_TIDY_TEST_CMD='echo BOOM; exit 1' "$R/plugins/tidy/bin/tidy-verify.sh" | rsn)"
  # secret block writes its reason to STDERR (PreToolUse exit-2 convention), not JSON.
  # Key shape assembled at runtime so the literal isn't contiguous in this source.
  local k; k="AKIA""ABCDEFGHIJKLMNOP"
  local sj; sj="$(jq -nc --arg p "/x/config.py" --arg c "API_KEY = '$k'" '{tool_name:"Write", tool_input:{file_path:$p, content:$c}}')"
  within "secret block" 420 "$(printf '%s' "$sj" | "$R/plugins/tidy/bin/tidy-presecret.sh" 2>&1 || true)"
}
