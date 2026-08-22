#!/usr/bin/env bash
# R81 — the MEASURED hook budget. A hook's cost must stay BOUNDED as the project and the task
# store grow; this proves it by measurement instead of asserting it in prose.
#
# WHAT THIS ASSERTS, HONESTLY. An earlier draft made a SCALING RATIO the hard gate and claimed
# hooks are "O(1) in store size". That claim was false and the gate was tuned to hide it: a
# devil's-advocate pass showed the verdict was a function of the arbitrary baseline size —
# `session-start` passed at 200 files (1.85x) and FAILED at 800 (3.72x), because it legitimately
# READS the store and is therefore ~linear in it. A gate whose result you can change by picking a
# different baseline is measuring the baseline, not the code.
#
# So the HARD gate is the ABSOLUTE cost on the oversized store — the thing that actually decides
# whether a hook stalls the session — and it is sufficient on its own: the real regression this was
# written against measured 8585ms there against a 1500ms cap. The ratio is kept as a REPORTED
# diagnostic and only fails on the plainly pathological (>6x over 8x data; the real bug was 8.06x),
# so honest linear growth is visible in the output without being dressed up as a violation.
#
# The absolute number is machine-dependent, which is why the cap is generous rather than tight —
# it is a stall detector, not a benchmark. A flaky gate gets disabled, and a disabled gate is
# exactly the state this whole requirement exists to prevent.
#
# Best-effort about the ENVIRONMENT (missing jq/git → SKIP, never a false red), strict about the
# BUDGET (a measured breach is a hard fail). Portable to macOS bash 3.2 + BSD tools: timing uses
# the `time` builtin, never `date +%s%N` (a GNU extension BSD date does not have).
set -uo pipefail
# LC_ALL=C is LOAD-BEARING: `TIMEFORMAT` renders through the locale, so under a comma-decimal
# locale (de_DE, fr_FR, most of Europe) every sample came back "0,124", failed the digits-only
# guard, and fell through to 0 — the gate reported a cheerful green having measured NOTHING, and
# did not even catch a deliberately unbounded hook. A budget that silently stops measuring is
# worse than no budget, because it also stops anyone looking.
export LC_ALL=C

command -v jq  >/dev/null 2>&1 || { echo "  SKIP — jq not installed"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "  SKIP — git not installed"; exit 0; }

SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# This gate lives in dev/ (it verifies the plugin, it is not part of it), so the hooks it measures
# are NOT its siblings. $HOOK_BUDGET_BIN lets the tests point it at a fixture; the default is the
# shipped plugin's bin/ relative to the repo root.
BIN="${HOOK_BUDGET_BIN:-$(cd "$(dirname "$SELF")/../plugins/companion/bin" && pwd)}"

# Tunables (R81: the VALUES are tunable, measuring them is not).
MULT="${HOOK_BUDGET_MULT:-8}"        # how much bigger the oversized store is
MAXRATIO="${HOOK_BUDGET_MAXRATIO:-6}"  # pathology only; honest linear growth is REPORTED, not failed
ABSCAP="${HOOK_BUDGET_ABSCAP:-1500}"   # ms on the OVERSIZED store — THE hard gate (stall detector)
BASEDIRS="${HOOK_BUDGET_BASEDIRS:-20}" # session dirs in the baseline store
PERDIR="${HOOK_BUDGET_PERDIR:-10}"     # task files per session dir
NOISE_MS="${HOOK_BUDGET_NOISE_MS:-25}" # below this the ratio is noise, not signal

TMP="$(mktemp -d 2>/dev/null)" || { echo "  SKIP — cannot mktemp"; exit 0; }
trap 'rm -rf "$TMP" 2>/dev/null || true' EXIT

REPO="$TMP/repo"; mkdir -p "$REPO"
git -C "$REPO" init -q >/dev/null 2>&1 || { echo "  SKIP — git init unavailable"; exit 0; }
git -C "$REPO" config user.email t@t >/dev/null 2>&1; git -C "$REPO" config user.name t >/dev/null 2>&1
: > "$REPO/f"; git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm init >/dev/null 2>&1

# The fixture repo used to hold ONE file, which meant every `git status` a hook runs measured
# nothing: the store scaled, the WORKTREE never did. `companion_unreconciled` (R113) walks the
# worktree, so the repo has to be big enough for that walk to show up, and DIRTY enough that the
# warning takes its expensive branch (building the file list) rather than returning early.
# CLAUDE.md: an unmeasured budget is not a budget — adding the call without this would have shipped
# exactly the "43ms on a 17k-file repo" cost statusline.sh already learned about, unmeasured.
REPOFILES="${HOOK_BUDGET_REPOFILES:-400}"
i=0; while [ "$i" -lt "$REPOFILES" ]; do printf 'x\n' > "$REPO/f$i"; i=$((i+1)); done
git -C "$REPO" add -A >/dev/null 2>&1; git -C "$REPO" commit -qm bulk >/dev/null 2>&1
# A tenth of them modified + a handful untracked: a real interrupted-session tree, not a clean one.
i=0; while [ "$i" -lt "$((REPOFILES / 10))" ]; do printf 'y\n' >> "$REPO/f$i"; i=$((i+1)); done
i=0; while [ "$i" -lt 5 ]; do printf 'z\n' > "$REPO/new$i"; i=$((i+1)); done

# One task file, copied rather than re-generated per file — building the store must not dominate.
jq -nc '{id:"1",subject:"a carried task with a reasonably typical subject length",
         status:"pending",done_when:"some acceptance text that survives a compaction",
         notes:[{text:"a breadcrumb"}]}' > "$TMP/task.json"

build_store() {  # $1=dest  $2=number of session dirs
  local dest="$1" n="$2" i j
  mkdir -p "$dest"
  i=0; while [ "$i" -lt "$n" ]; do
    mkdir -p "$dest/s$i"
    # Half the dirs carry the path-stable .repo stamp, half the legacy .root stamp, so BOTH
    # match paths are exercised. Written with printf '%s' (NO trailing newline) exactly as `tq`
    # writes them — the newline-less marker is the shape that broke a naive `read`.
    if [ $((i % 2)) -eq 0 ]; then printf '%s' "$RID" > "$dest/s$i/.repo"
    else                         printf '%s' "$REPO" > "$dest/s$i/.root"; fi
    j=0; while [ "$j" -lt "$PERDIR" ]; do cp "$TMP/task.json" "$dest/s$i/$j.json"; j=$((j+1)); done
    i=$((i+1))
  done
}

RID="$(cd "$REPO" && bash -c '. "$1"; companion_repo_id "$PWD"' _ "$BIN/../lib/companion.sh" 2>/dev/null || printf 'x')"
build_store "$TMP/small" "$BASEDIRS"
build_store "$TMP/big"   "$((BASEDIRS * MULT))"
SID="s0"   # a session dir that exists in both stores, for the session-scoped hooks

# Realistic stdin for each hook. session-start.sh and ask-guard.sh are back (R100/Pass 6) and
# stop-autopilot.sh is back too (owner-decided 2026-08-12, partial restore) — all three read the
# task store, so all three belong here. The Stop hook is the store-scaling case that MATTERS most:
# it fires on EVERY stop of an autopiloted run, and it calls `tq stopfields`, which reads the whole
# session store. CLAUDE.md: an unmeasured budget is not a budget — restoring the code without
# restoring its measurement would have re-shipped the guarantee and dropped the guard on it.
# session-start.sh is in fact THE store-scaling-sensitive case this gate was originally written
# against (see the header comment: 200 files 1.85x, 800 files 3.72x).
jq -nc --arg c "$REPO" --arg s "$SID" '{model:{display_name:"Opus"},session_id:$s,
  workspace:{current_dir:$c},context_window:{total_input_tokens:1,total_output_tokens:1}}' > "$TMP/in-sl"
jq -nc --arg c "$REPO" '{cwd:$c,source:""}' > "$TMP/in-ss"
jq -nc --arg c "$REPO" --arg s "$SID" \
  '{cwd:$c,session_id:$s,tool_input:{questions:[{question:"q",options:[{label:"A"}]}]}}' > "$TMP/in-ag"
# The Stop hook, like ask-guard, only does real work while autopilot is ARMED (it exits at
# `companion_autopilot_on` otherwise). The same arming below covers both.
jq -nc --arg c "$REPO" --arg s "$SID" '{cwd:$c,session_id:$s}' > "$TMP/in-sa"
# contract-guard.sh (restored 2026-08-22) fires on EVERY Write/Edit, which is the highest-frequency
# hook path there is — so it is measured with a payload that reaches its most expensive branch: a
# real requirements.yaml path plus both sides of an edit, i.e. past the cheap path filter.
# secret-guard.sh fires on EVERY Write/Edit/NotebookEdit — the highest-frequency hook path in the
# plugin — so it is measured on content that reaches BOTH regex passes (no anchored hit, so the
# generic heuristic also runs), not on a payload that exits early.
# ask-close.sh fires only on an AskUserQuestion result, so it is rare — but it SCANS THE SESSION
# STORE looking for the park to close, which is the one thing R81 cares about: cost that grows with
# the store. Measured with an answered payload so it takes the scanning branch, not an early exit.
jq -nc --arg c "$REPO" --arg s "$SID" '{cwd:$c,session_id:$s,
  tool_input:{questions:[{question:"pick a cache",options:[{label:"sqlite"},{label:"files"}]}]},
  tool_response:{"pick a cache":"sqlite"}}' > "$TMP/in-ac"
jq -nc --arg f "$REPO/f0" '{tool_name:"Write",tool_input:{file_path:$f,
  content:"function x() { return 1 } // a line of ordinary code with password_hint = \"the dog\""}}' > "$TMP/in-sg"
jq -nc --arg f "$REPO/docs/requirements.yaml" '{tool_name:"Edit",tool_input:{file_path:$f,
  old_string:"- id: R1\n  requirement: a\n    - \"t\"\n",new_string:"- id: R1\n  requirement: a\n"}}' > "$TMP/in-cg"
# ask-guard.sh only does real work while autopilot is ARMED for the repo (its dedup grep + `tq
# add` path) — off, it exits in one `companion_autopilot_on` check regardless of store size, which
# would measure nothing. Arm it here, in the SAME state dir ms_of() uses below, so the benchmark
# exercises the path that actually scales.
( cd "$REPO" && CLAUDE_COMPANION_STATE_DIR="$TMP/state" bash "$BIN/autopilot.sh" on ) >/dev/null 2>&1 || true

# Milliseconds for one run, BEST of 3 (best-of, not mean: we want the hook's own cost, not the
# scheduler's worst moment). `time` builtin + TIMEFORMAT — portable to bash 3.2, unlike date %N.
ms_of() {  # $1=script  $2=stdin file  $3=store dir
  local s="$1" in="$2" store="$3" best="" t n=3
  while [ "$n" -gt 0 ]; do
    n=$((n - 1))
    TIMEFORMAT='%3R'
    t="$( { time CLAUDE_COMPANION_TASKS_DIR="$store" CLAUDE_COMPANION_STATE_DIR="$TMP/state" \
              bash "$s" < "$in" >/dev/null 2>&1; } 2>&1 | tr -d '[:space:]' )"
    # "0.123" -> 123 with awk (no bc, no float math in bash 3.2). Garbage -> skip this sample.
    case "$t" in ''|*[!0-9.]*) continue ;; esac
    t="$(awk -v v="$t" 'BEGIN{printf "%d", (v*1000)+0.5}' 2>/dev/null)"
    case "$t" in ''|*[!0-9]*) continue ;; esac
    [ -z "$best" ] && best="$t"
    [ "$t" -lt "$best" ] && best="$t"
  done
  printf '%s' "${best:-0}"
}

printf '  %-22s %9s %9s %8s   %s\n' HOOK "small" "8x" "ratio" "verdict"
rc=0
for spec in \
  "statusline.sh:in-sl" \
  "session-start.sh:in-ss" \
  "ask-guard.sh:in-ag" \
  "stop-autopilot.sh:in-sa" \
  "contract-guard.sh:in-cg" \
  "secret-guard.sh:in-sg" \
  "ask-close.sh:in-ac"
do
  script="${spec%%:*}"; inf="${spec##*:}"
  [ -f "$BIN/$script" ] || continue
  a="$(ms_of "$BIN/$script" "$TMP/$inf" "$TMP/small")"
  b="$(ms_of "$BIN/$script" "$TMP/$inf" "$TMP/big")"
  # Ratio in hundredths, integer math only. Below the noise floor a ratio is meaningless
  # (2ms vs 6ms is 3x of nothing), so it is reported but not enforced.
  base="$a"; [ "$base" -lt 1 ] && base=1
  ratio=$(( b * 100 / base ))
  verdict="ok"
  if [ "$b" -gt "$ABSCAP" ]; then
    verdict="FAIL >${ABSCAP}ms on a ${MULT}x store — this stalls the session"; rc=1
  elif [ "$a" -ge "$NOISE_MS" ] && [ "$ratio" -gt $((MAXRATIO * 100)) ]; then
    verdict="FAIL pathological scaling (>${MAXRATIO}x over ${MULT}x data)"; rc=1
  elif [ "$a" -lt "$NOISE_MS" ]; then
    verdict="ok (under noise floor)"
  fi
  printf '  %-22s %7sms %7sms %6s.%02sx   %s\n' \
    "$script" "$a" "$b" "$((ratio/100))" "$(printf '%02d' $((ratio%100)))" "$verdict"
done

# THE DRY-QUEUE BURN-DOWN PATH (R82 hand-off, restored 2026-08-15). Every measurement above runs
# against a store that HAS tasks, so `stop-autopilot.sh` returns at its startable-work branch and
# the new hand-off — which shells out to `burn-down.sh` — is never executed. Measuring the hook
# without exercising its most expensive branch is precisely the "budget that measures nothing"
# this file was already caught doing once today with a one-file fixture repo. So: an EMPTY store
# with burn-down armed, which is the only shape that reaches the call.
if [ -f "$BIN/stop-autopilot.sh" ]; then
  mkdir -p "$TMP/drystore/$SID"
  printf '%s' "$RID" > "$TMP/drystore/$SID/.repo"   # stamped for this repo, but with NO task files
  ( cd "$REPO" && CLAUDE_COMPANION_STATE_DIR="$TMP/state" bash "$BIN/autopilot.sh" burndown on ) >/dev/null 2>&1 || true
  d="$(ms_of "$BIN/stop-autopilot.sh" "$TMP/in-sa" "$TMP/drystore")"
  verdict="ok"
  if [ "$d" -gt "$ABSCAP" ]; then
    verdict="FAIL >${ABSCAP}ms — the dry-queue burn-down hand-off stalls the session"; rc=1
  fi
  printf '  %-22s %7sms %9s %8s   %s\n' "stop-autopilot(dry+🔥)" "$d" "-" "-" "$verdict"
fi

exit "$rc"
