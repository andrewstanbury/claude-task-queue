#!/usr/bin/env bash
# helper.bash — the SHARED fixture kit for every dev/tests/*.bats file. Extracted 2026-08-16 when
# companion-core.bats reached 3,922 lines and 183 tests: shipped code is held to 300 lines while the
# suite had no limit at all, and a failure in a four-thousand-line file tells you almost nothing
# about where to look.
#
# Everything here was ALREADY top-level in that file - setup, teardown, and the fixture builders
# tests share. Nothing was rewritten; the split moved whole blocks so `git log -L` (which
# dev/stale.sh uses per @test block) keeps following them, and every test NAME is byte-identical
# because dev/trace.sh matches requirements to tests by name.
#
# Loaded with `load helper` at the top of each .bats file.

#
# Enforced core — the base behavior that must execute or block: the secret gate, `tq` (THE
# queue; the companion owns its store and does NOT use native tasks), SessionStart (steering +
# root-scoped resume), and persisted+enforced autopilot. (R27 edit-gates
# live in companion-gates.bats; the status line in companion-hud.bats.)

# Fixture dirs go under BATS_TEST_TMPDIR, which bats removes after each test. Plain `mktemp -d`
# leaks: one session of this suite left 37,000 directories in /tmp and exhausted the inode table,
# which then fails unrelated tests for reasons that look like code defects.
_tmpd() { mktemp -d "$BATS_TEST_TMPDIR/d.XXXXXX"; }

setup() {
  # Tests live in dev/ and are NOT shipped. ROOT still means the SHIPPED plugin dir; DEV is
  # where the gates that verify it live. Keeping the two named apart is the point of the split.
  ROOT="$(cd "$BATS_TEST_DIRNAME/../../plugins/companion" && pwd)"
  DEV="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  GUARD="$ROOT/bin/check-secrets.sh"; TQ="$ROOT/bin/tq"; SL="$ROOT/bin/statusline.sh"
  AP="$ROOT/bin/autopilot.sh"; RESUME="$ROOT/bin/resume.sh"
  SS="$ROOT/bin/session-start.sh"; AG="$ROOT/bin/ask-guard.sh"   # R100/Pass 6 reinstated
  BOARD="$ROOT/bin/board.sh"
  DRIFT="$ROOT/bin/contract-drift.sh"   # R58 living contract (drift backstop)
  export CLAUDE_COMPANION_TASKS_DIR="$(_tmpd)"   # the companion's OWN store, not ~/.claude/tasks
  export CLAUDE_COMPANION_STATE_DIR="$(_tmpd)"   # autopilot flags live here
  export CLAUDE_COMPANION_SESSION_ID="s1"
}
teardown() { rm -rf "$CLAUDE_COMPANION_TASKS_DIR" "$CLAUDE_COMPANION_STATE_DIR"; }

# Write a per-repo feature OFF flag directly at the reader's enc path (the `/companion:features`
# CLI was removed 2026-07-18; the flag mechanism + its readers remain — R50). Mirrors
# companion_feature_file(companion_root(repo)) so secret-guard / resume / statusline find it.
_feature_off() {  # $1=feature  $2=repo-dir
  local root enc; root="$(git -C "$2" rev-parse --show-toplevel)"
  enc="$(printf '%s' "$root" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
  mkdir -p "$CLAUDE_COMPANION_STATE_DIR/features"
  printf '%s=off\n' "$1" >> "$CLAUDE_COMPANION_STATE_DIR/features/$enc"
}
_feature_clear() { rm -f "$CLAUDE_COMPANION_STATE_DIR/features/"* 2>/dev/null || true; }

# ---- R61 anti-drift gate: the ONE matcher + extractor, shared by the gate AND its guard-test ----
# (Factored out so the guard actually exercises the real logic — a guard that re-implements a simpler
# check proves nothing about the gate. DA finding: fixed.)
# _ux_check_resolves FRAGMENT TITLES → 0 iff SOME title contains every ≥4-char …-segment of FRAGMENT.
# A fragment with no ≥4-char segment is UNRESOLVED (return 1), not a silent pass — an empty/too-short
# Check is itself drift, not coverage. Substring-not-exact is deliberate (Checks abbreviate with …);
# the honest ceiling: this proves the referenced test EXISTS + is wired to the row, not that a lazy
# 4-char coincidental substring is the *intended* test — the convention is a distinctive Check.
_ux_check_resolves() {
  local rest="$1" titles="$2" seg; local -a segs=()
  while [ -n "$rest" ]; do
    case "$rest" in *…*) seg="${rest%%…*}"; rest="${rest#*…}";; *) seg="$rest"; rest="";; esac
    seg="${seg#"${seg%%[![:space:]]*}"}"; seg="${seg%"${seg##*[![:space:]]}"}"
    [ "${#seg}" -ge 4 ] && segs+=("$seg")
  done
  [ "${#segs[@]}" -gt 0 ] || return 1
  local t ok; while IFS= read -r t; do ok=1
    for seg in "${segs[@]}"; do case "$t" in *"$seg"*) : ;; *) ok=0; break;; esac; done
    [ "$ok" = 1 ] && return 0
  done <<< "$titles"; return 1
}
# _ux_flow_check LINE → the backtick test-name from a flow page's Tests line, or nothing. A flow
# page (docs/flows/*.md, R62) lists tests as `- [E] `<test name>` ✅` (enforced → must resolve) or
# `- [S] … 👁` (judgment → skipped). The literal `- [E] ` prefix (matched literally via [[ == ]],
# NOT a case glob where [E] is a char-class) isolates Tests lines from every other `[E]` mention
# (headers, config bullets), so extraction can't stray. Robust to leading indentation.
_ux_flow_check() {
  local line="${1#"${1%%[![:space:]]*}"}"                  # strip leading whitespace
  [[ "$line" == '- [E] '* ]] || return 0                    # a Tests [E] line only
  printf '%s\n' "$line" | grep -oE '`[^`]*`' | head -1 || true
}

# ---- secret gate (the one enforced content block) ----


# ---- MCP server, Pass 5a: the remaining bin/ scripts as tools, same thin-wrapper contract ----

_mcp_call() {  # $1=repo-dir $2=json-array-of-{name,arguments} -> prints each result's text, \n-joined
  command -v node >/dev/null 2>&1 || skip "node not installed"
  [ -d "$ROOT/mcp-server/node_modules" ] || skip "mcp-server deps not installed (npm ci --prefix plugins/companion/mcp-server)"
  local script='
import { Client } from "@modelcontextprotocol/sdk/client/index.js";
import { StdioClientTransport } from "@modelcontextprotocol/sdk/client/stdio.js";
const calls = JSON.parse(process.env.MCP_CALLS);
const transport = new StdioClientTransport({ command: "node", args: [process.env.MCP_INDEX], env: process.env });
const client = new Client({ name: "bats-verify", version: "0.0.1" });
await client.connect(transport);
for (const c of calls) {
  const r = await client.callTool({ name: c.name, arguments: c.arguments || {} });
  process.stdout.write("<<<" + c.name + ">>>\n" + r.content[0].text + "\n");
}
await client.close();
'
  run bash -c 'cd "$1/mcp-server" && CLAUDE_PLUGIN_ROOT="$1" CLAUDE_PROJECT_DIR="$2" MCP_INDEX="$1/mcp-server/index.js" MCP_CALLS="$3" node --input-type=module -e "$4"' \
    _ "$ROOT" "$1" "$2" "$script"
}


# ── sweep mode (R77) ───────────────────────────────────────────────────────────────────────────
# Sweep is the ONE mode that reaches backwards into the already-parked pile, so eligibility is the
# safety property. It keys on a POSITIVE marker the parker wrote — `rev:` = reversible, but the
# owner's call — never on inference over prose. An earlier build inferred eligibility as
# "❓ ∧ rec: ∧ ¬decompose:", which under decisive mode selected EXACTLY the irreversible parks it
# was meant to protect (decisive parks only the irreversible, and writes `rec:` on them). Every
# exclusion below is pinned separately, and each fixture carries the OTHER markers so no rule can
# be masked by another — the masking trap that already hid two of these once.

_sw_task() {  # $1=subject $2=id
  mkdir -p "$CLAUDE_COMPANION_TASKS_DIR/sw"
  jq -n --arg s "$1" --arg i "$2" '{id:$i,subject:$s,status:"pending"}' > "$CLAUDE_COMPANION_TASKS_DIR/sw/$2.json"
}
# R100/Pass 4: stop-autopilot.sh is retired; the sweep-eligibility logic it only ever READ lives in
# (and is driven directly via) tq stopfields now — same rules, no Stop-hook wrapper left.
_sw_next() {  # -> the next-subject field, or "" when nothing is eligible/startable
  CLAUDE_COMPANION_SESSION_ID=sw "$TQ" stopfields "${1:-true}" 2>/dev/null | cut -d $'\x1f' -f4
}
_sw_repo() {
  local r; r="$(_tmpd)"; git -C "$r" init -q
  git -C "$r" -c user.email=t@t -c user.name=t commit -q --allow-empty -m i
  printf '%s' "$r"
}


_mg_fixture() {  # a minimal repo the mutation gate can actually run against
  MG="$(_tmpd)"; mkdir -p "$MG/dev/tests" "$MG/plugins/companion/bin"
  git -C "$MG" init -q
  cp "$DEV/mutate-gate.sh" "$MG/dev/"
  printf '#!/usr/bin/env bash\necho MARKER_A\n' > "$MG/plugins/companion/bin/t.sh"
  # >=2 tests: the gate refuses to certify a suite it cannot enumerate
  printf '#!/usr/bin/env bats\n@test "marker" {\n  run bash plugins/companion/bin/t.sh\n  [[ "$output" == *MARKER_A* ]]\n}\n@test "f1" { true; }\n@test "f2" { true; }\n' > "$MG/dev/tests/t.bats"
  printf 'plugins/companion/bin/t.sh::s@MARKER_A@MARKER_B@::t stops printing the marker\n' > "$MG/dev/tests/mutations.txt"
  MG_LOCK="${TMPDIR:-/tmp}/companion-mutate-$(printf '%s' "$MG" | cksum | cut -d' ' -f1).lock"
}


# ── the mutation gate itself (R78) ─────────────────────────────────────────────────────────────
# The gate whose whole job is proving tests CAN fail had no test of its own, and shipped TWO
# defects that let it certify coverage it never observed (3.30.2 and 3.31.0, both caught by
# something other than the suite). It now lives in bin/ so these cases can exist at all; a FAKE
# `bats` first on PATH drives each verdict branch in milliseconds without recursing into the
# real suite.
_mutgate() {  # $1 = shim body ("" = use the real bats) · $2 = tag → runs the REAL gate
  local d="$BATS_TEST_TMPDIR/mg$2"
  mkdir -p "$d/dev/tests" "$d/plugins/companion" "$d/shim"
  cp "$DEV/mutate-gate.sh" "$d/dev/"
  printf 'VALUE=1\n' > "$d/plugins/companion/target.sh"
  printf 'plugins/companion/target.sh::s@VALUE=1@VALUE=2@::the value changes\n' \
    > "$d/dev/tests/mutations.txt"
  [ -n "$1" ] && { printf '%s\n' "$1" > "$d/shim/bats"; chmod +x "$d/shim/bats"; }
  ( cd "$d" && PATH="$d/shim:$PATH" ./dev/mutate-gate.sh plugins/companion/target.sh 2>&1 )
}
# A shim that answers --count with 3, passes the gate's GREEN BASELINE run (call #1), and only
# then behaves as told. The baseline check is itself under test below, so shims must satisfy it.
_shim() {
  printf '#!/bin/sh\n[ "$1" = "--count" ] && { echo 3; exit 0; }\n'
  printf 'n=$(cat "$0.n" 2>/dev/null || echo 0); n=$((n+1)); echo "$n" > "$0.n"\n'
  printf 'if [ "$n" -eq 1 ]; then echo "1..3"; echo "ok 1 a"; echo "ok 2 b"; echo "ok 3 c"; exit 0; fi\n'
  printf '%s\n' "$1"
}


# ── burn-down mode (the only mode that AUTHORS work) ───────────────────────────────────────────
_bd() {  # $1=used7 $2=used5 $3=age-offset → run the forecaster against a fresh fixture
  # 7d reset is +172800 (2 days), NOT +86400. At exactly one day the fixture sat ON the FINAL
  # STRETCH boundary, and burn-down reads its own clock a beat after the payload is built — so
  # `left` came out 86399, tipped into the stretch, and the projection-based hold this helper's
  # callers rely on stopped applying at random. Same class as "never assert an exact countdown
  # from date +%s". Two days keeps every caller's HOLD/BURN outcome and stays clear of the edge;
  # the stretch itself is covered deliberately by its own test.
  # A BURN now needs TWO distinct agreeing readings, because one was measured swinging 21 points at
  # a 5h rollover. So seed an earlier, identical sample first — that is what the status line does in
  # reality by repainting. The seeding run is discarded; only the second is asserted on.
  printf '%s %s %s %s %s\n' "$(( $(date +%s) - ${3:-0} - 5 ))" "${2:-20}" "$(( $(date +%s)+7200 ))" \
    "${1:-10}" "$(( $(date +%s)+172800 ))" > "$BD_STATE/ratelimit"
  env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status >/dev/null 2>&1 || true
  printf '%s %s %s %s %s\n' "$(( $(date +%s) - ${3:-0} ))" "${2:-20}" "$(( $(date +%s)+7200 ))" \
    "${1:-10}" "$(( $(date +%s)+172800 ))" > "$BD_STATE/ratelimit"
  run env CLAUDE_COMPANION_STATE_DIR="$BD_STATE" CLAUDE_COMPANION_TASKS_DIR="$BD_TASKS" \
      BURNDOWN_BRANCHES_PER_DAY="${_PERDAY:-3}" \
      BURNDOWN_ROOT="$BD_REPO" bash "$ROOT/bin/burn-down.sh" status
}
# Encode a repo path the way lib/companion.sh does, keyed on the RESOLVED root. On macOS
# `_tmpd` returns /var/folders/... and git resolves it to /private/var/folders/..., so any test
# that hand-encodes the mktemp path creates a flag the product never looks at — green on Linux,
# vacuous on macOS. Always go through git, exactly like companion_root does.
# Stamp a session store with the RESOLVED repo root, the way tq and companion_root do. Writing the
# raw mktemp path is the same macOS trap as _flagpath: git resolves /var/... to /private/var/...,
# the stamp never matches, companion_open_tasks returns nothing, and a test asserting "the queue
# holds work" silently asserts nothing at all.
_stamp_root() {  # $1=session dir · $2=repo dir
  local r; r="$(git -C "$2" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$2")"
  # NOT a recursive call: the bulk rewrite that introduced this helper matched its OWN body and
  # turned the write into a self-call, which spun forever and looked exactly like a hung test.
  printf '%s' "$r" > "$1/.root"
}

_flagpath() {  # $1=state dir · $2=flag kind (autopilot|burndown|ship|…) · $3=repo dir
  local r; r="$(git -C "$3" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$3")"
  printf '%s/%s/%s' "$1" "$2" "$(printf '%s' "$r" | sed -e 's:%:%25:g' -e 's:/:%2F:g')"
}

_bd_setup() {
  BD_REPO="$(_tmpd)"; git -C "$BD_REPO" init -q -b main
  git -C "$BD_REPO" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
  BD_STATE="$(_tmpd)"; BD_TASKS="$(_tmpd)"
  mkdir -p "$BD_STATE/burndown"
  touch "$(_flagpath "$BD_STATE" burndown "$BD_REPO")"
}


# ---- SessionStart hook (R100/Pass 6 reinstated — guaranteed context delivery, docs/adr R105) ----

_ss_ctx() {  # $1=repo  $2=source ("" for fresh start)
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" "{cwd:\$c,source:\$s}" | "$3" | jq -r ".hookSpecificOutput.additionalContext"' \
    _ "$1" "$2" "$SS"
}


# ---- PreToolUse[AskUserQuestion] guard (R100/Pass 6 reinstated, docs/adr R105) ----

_ag_ask() {  # $1=repo  $2=session-id
  run bash -c 'jq -nc --arg c "$1" --arg s "$2" \
    "{cwd:\$c,session_id:\$s,tool_input:{questions:[{question:\"pick A or B\",options:[{label:\"A\",description:\"faster\"},{label:\"B\",description:\"safer\"}]}]}}" \
    | "$3" | jq -r ".hookSpecificOutput.permissionDecision + \"|\" + .hookSpecificOutput.permissionDecisionReason"' \
    _ "$1" "$2" "$AG"
}


# ── staleness / challenge (R97) ────────────────────────────────────────────────────────────────
# The contract is a claim about what the owner still wants, and nothing was re-asking. These cover
# the part that must be MECHANICAL: which requirements the work has moved out from under, on the
# only axis each tier actually has. Whether a stale requirement should then be reversed is
# judgement, and deliberately not testable here.

# A repo whose single .bats holds TWO test blocks, so "per block, not per file" is observable.
_stale_repo() {                                  # $1=dir
  local d="$1"
  mkdir -p "$d/dev/tests" "$d/docs"
  cp dev/stale.sh "$d/dev/stale.sh"
  git -C "$d" init -q
  # printf, NOT a heredoc: bats preprocesses this very file and rewrites any line that STARTS with
  # `@test` into a test function — including fixture text inside a quoted heredoc. That silently
  # corrupted both the fixture and every helper defined after it, and the symptom was a drift of 0
  # with no error anywhere. Keep `@test` off column 0 in this file.
  printf -- '@test "alpha holds" {\n  marker=0\n  [ "$marker" -eq 0 ]\n}\n\n@test "beta holds" {\n  run true\n  [ "$status" -eq 0 ]\n}\n' \
    > "$d/dev/tests/t.bats"
}
# Bump ONLY the alpha block. `sed -i` is spelled differently on GNU and BSD, so: temp file + mv.
_bump_alpha() {                                  # $1=dir  $2=n
  sed "s/marker=[0-9]*/marker=$2/" "$1/dev/tests/t.bats" > "$1/dev/tests/t.new"
  mv "$1/dev/tests/t.new" "$1/dev/tests/t.bats"
}
_stale_commit() {                                # $1=dir  $2=YYYY-MM-DD  $3=msg
  git -C "$1" add -A
  GIT_AUTHOR_DATE="$2T12:00:00" GIT_COMMITTER_DATE="$2T12:00:00" \
    git -C "$1" -c user.email=t@t -c user.name=t commit -q -m "$3"
}
_st() { printf '%s\n' "$output" | awk -v i="$1" '$1 == i { print $2; exit }'; }

