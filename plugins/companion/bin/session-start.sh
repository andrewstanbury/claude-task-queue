#!/usr/bin/env bash
# SessionStart — the things a document can't do itself:
#   1. Put STEERING.md (the working agreement) in context once per session.
#   2. Re-surface THIS repo's still-open tasks from an earlier session (cross-session resume).
#   3. Surface the repo's own LESSONS.md (accumulated gotchas) if it has one (R30·d7).
# The companion owns its task store (no native tasks); each session dir is stamped with its
# repo root (`.root`), so scoping needs no native transcript. `/companion:resume` re-runs the
# resume half on demand (its step 1). Read-only, best-effort: any failure injects nothing, never breaks startup.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

in="$(cat 2>/dev/null || true)"
cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
src="$(printf '%s' "$in" | jq -r '.source // empty' 2>/dev/null || true)"
root="$(companion_root "$cwd")"

# SessionStart fires on startup/resume AND after a context compaction (source=compact) — so this
# hook IS the post-compaction re-anchor (R30·d2). On compact it re-injects the live queue (each
# task's done-when) + LESSONS — the real cross-compaction memory — but NOT the STEERING core
# (~2.5k tokens injected, R69; the doc's rationale half is never injected at all) (R32): the
# agreement from session start still applies and the summarizer largely preserves it, so
# re-pasting static prose every compaction was the biggest repeatable token waste. What IS
# re-stated inline is the POSTURE — recommendation-first options AND the unconditional closing
# verdict — because that is the half that decays first and the half worth its ~40 bytes.
# Per-repo `steering` toggle (R50): when off, this repo opts out of the working-agreement
# injection (the one SessionStart output with real token cost) — resume + LESSONS still fire, since
# those are cheap and repo-specific. A `steering=off` line in the per-repo flag file sets it (the
# `/companion:features` CLI was removed 2026-07-18, R50; the flag mechanism + this read are unchanged).
steering_off=0; companion_feature_off steering "$root" && steering_off=1
if [ "$src" = "compact" ]; then
  if [ "$steering_off" = 1 ]; then
    msg="Your context was just compacted. Re-anchor from your LIVE task queue (each task's done-when is its acceptance test) and this repo's lessons below — resume from the queue, not from memory."$'\n\n'
  else
    msg="Your context was just compacted. Re-anchor from your LIVE task queue (each task's done-when is its acceptance test) and this repo's lessons below — resume from the queue, not from memory. The working agreement injected at session start still applies (not re-pasted here, to save tokens) — including its core move, which the summarizer must not drop: a decision-shaped request (choose / redesign / compare / evaluate / \"what do you recommend\") is owed recommendation-first options — 2–4 genuinely different, each with its cost, your pick first and marked, plus the brutal-honest read — never a flat one-opinion answer (R49). And the unconditional half, which decays first: close EVERY reply with a one-line brutal-honest verdict — agreement counts; what is banned is manufactured disagreement, not agreement."$'\n\n'
  fi
elif [ "$steering_off" = 1 ]; then
  msg=""
else
  msg="Read the working agreement below — it governs how you queue, decide, and keep this repo clean for the whole session."$'\n\n'
  # R69: inject only the CORE — the doc's rationale section sits below an "injection stops
  # here" marker and is on-demand reading, not a per-session tax. awk fails open: no marker
  # (or an old STEERING) → the whole file, exactly the pre-R69 behavior.
  [ -f "$PLUGIN_DIR/STEERING.md" ] && msg="$msg$(awk '/injection stops here/{exit} {print}' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || cat "$PLUGIN_DIR/STEERING.md")"
  # Autopilot's mode prose (~2.7KB) is dead weight in every session where autopilot is OFF, which
  # is most of them — so it rides ONLY when the mode is actually armed for this repo. Conditional
  # beats deleted: when the mode IS on, the rules are exactly as present as they ever were.
  if [ -f "$PLUGIN_DIR/STEERING.md" ] && companion_autopilot_on "$root"; then
    msg="$msg"$'\n'"$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || true)"
  fi
fi
carry="$(companion_open_tasks "$root")"
[ -n "$carry" ] && msg="$msg"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"

# INSTALLED-VS-WORKING-TREE VERSION LAG. Claude Code runs the plugin from its CACHE, not from the
# checkout you are editing — so a session can spend hours reporting work as shipped while the hooks
# actually firing are an older build. That happened on 2026-08-02: the session opened on a cache
# that had no UserPromptSubmit registration at all, so every hook added that day was inert while
# the repo was green. Nothing surfaced the gap; the status line showed the OLD version the whole
# time and neither of us read it as a warning.
#
# Only fires when the repo you are IN is the one that builds this plugin — a manifest under
# plugins/*/.claude-plugin/ whose name matches the running plugin. Bounded: one glob, one jq, once
# per session, and silent on every failure (R7/R68).
_ver_running="$(jq -r '.version // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
_ver_name="$(jq -r '.name // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
if [ -n "$_ver_running" ] && [ -n "$_ver_name" ]; then
  for _m in "$root"/plugins/*/.claude-plugin/plugin.json; do
    [ -f "$_m" ] || continue
    [ "$(jq -r '.name // empty' "$_m" 2>/dev/null || true)" = "$_ver_name" ] || continue
    _ver_tree="$(jq -r '.version // empty' "$_m" 2>/dev/null || true)"
    if [ -n "$_ver_tree" ] && [ "$_ver_tree" != "$_ver_running" ]; then
      msg="$msg"$'\n\n'"⚠️  RUNNING v${_ver_running}, BUT THIS WORKING TREE IS v${_ver_tree}. The hooks and commands firing in this session come from the installed cache, NOT from the code you are about to edit — so anything you add here is INERT until the plugin is reinstalled. Do not report a change as working because the repo is green; say which version actually ran. (Seen 2026-08-02: six hours of work was inert in the owner's own session.)"
    fi
    break
  done
fi

# This repo's accumulated gotchas (R30·d7) — model-maintained; first match wins.
for lf in "$root/docs/LESSONS.md" "$root/LESSONS.md" "$root/.companion/LESSONS.md"; do
  [ -f "$lf" ] || continue
  # Two-tier like STEERING (R69): only the core above the marker is injected; everything below is
  # on-demand. Same awk, same FAIL-OPEN — no marker means the whole file rides, which is what an
  # unsplit LESSONS.md in someone else's repo should do (R9: a stranger's file still works).
  msg="$msg"$'\n\n'"── This repo's LESSONS (accumulated gotchas — heed them, and append new ones as you learn them) ──"$'\n'"$(awk '/lessons injection stops here/{exit} {print}' "$lf" 2>/dev/null || cat "$lf")"
  break
done

# RECENT OUT-OF-BAND CHANGES (R93). git is already the timeline for everything IN the repo; what
# no `git log` can show is the change made in a console, a DNS panel, a provider dashboard or a
# credential rotation — and that is the class that cost the owner days on another project, where a
# recent AWS change was the cause while an innocent, twice-confirmed login config was investigated.
#
# Injected rather than read on demand because the failure mode is CONTEXT LOSS: clear the state,
# open a bug, and the fact that something relevant changed last week is simply gone. A rule that
# says "go look" cannot survive that; a fact that arrives unasked can.
#
# The token cost is near zero because the window is TIME-BOUNDED: entries older than the window are
# not injected, so a repo with no recent out-of-band change contributes nothing at all. Bounded for
# R81 the same way: only the tail of the file is read, so the work does not grow with its history.
# Dates compare as STRINGS (ISO-8601 sorts lexically) — no GNU-only date arithmetic on the values.
_win="${CLAUDE_COMPANION_CHANGE_WINDOW_DAYS:-14}"
case "$_win" in ''|*[!0-9]*) _win=14 ;; esac
_cut="$(date -u -d "-${_win} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${_win}"d +%Y-%m-%d 2>/dev/null || true)"
if [ -n "$_cut" ]; then
  for cf in "$root/docs/CHANGES-OUTSIDE-GIT.md" "$root/CHANGES-OUTSIDE-GIT.md" "$root/.companion/CHANGES-OUTSIDE-GIT.md"; do
    [ -f "$cf" ] || continue
    _recent="$(tail -n 200 "$cf" 2>/dev/null | awk -v c="$_cut" '
      /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = ($2 >= c) }
      f' 2>/dev/null | head -c 2000)"
    [ -n "$_recent" ] && msg="$msg"$'\n\n'"── Changed OUTSIDE this repo in the last ${_win} days — git cannot show these, and they are the first thing to suspect when something breaks ──"$'\n'"$_recent"
    break
  done
fi

# REWORK, surfaced not narrated (R94). The owner's words: "Claude seems to be making more and more
# obvious mistakes requiring rework then telling me about how it caught the mistakes." A caught
# mistake reported as an apparatus win reframes a defect rate as a success; a count cannot be spun.
# Zero bytes when nothing was recorded, which is the intended steady state.
_rw="$(companion_rework_file "$root")"
if [ -f "$_rw" ]; then
  _rwout="$(REWORK_ROOT="$root" "$(dirname "$SELF")/rework.sh" report 2>/dev/null | head -c 800)"
  case "${_rwout:-}" in
    ''|rework:\ none*) : ;;
    *) msg="$msg"$'\n\n'"── REWORK already recorded here (work that had to be done twice — read it as your own defect rate, not as a list of catches) ──"$'\n'"$_rwout" ;;
  esac
fi

jq -cn --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$m}}'
