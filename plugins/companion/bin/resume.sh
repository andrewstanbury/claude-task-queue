#!/usr/bin/env bash
# resume — the on-demand session-context pull. Absorbed the old SessionStart hook's content
# (R100/Pass 2): with no guaranteed hook left to inject anything automatically, this is now the
# ONLY way any of it reaches a session — STEERING, LESSONS, the version-lag warning, recent
# out-of-band changes (R93), and recorded rework all ride here, alongside the carried-over open
# tasks this script already surfaced. Nothing here is triggered for you; call it yourself, at the
# start of a session or after a compaction — that is the accepted cost of dropping the hook
# (docs/adr/README.md R100).
#
# Resume is a TRIAGE handoff (R39): it first turns autopilot OFF (announced when it was on) so the
# resumed decisions come back to the OWNER, not to autopilot — while autopilot is on the ask-guard
# used to block questions; that guard is gone too (Pass 4), but the triage-to-owner intent stays,
# because a resume mid-drain is exactly the moment a parked ❓ should get a human, not a nudge.
set -uo pipefail
command -v jq >/dev/null 2>&1 || { echo "resume: jq required" >&2; exit 1; }
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
PLUGIN_DIR="$(cd "$(dirname "$SELF")/.." && pwd)"
# shellcheck source=../lib/companion.sh
. "$PLUGIN_DIR/lib/companion.sh"

root="$(companion_root "$PWD")"
out=""

# Capture armed-ness BEFORE clearing it below — both the disarm announcement and whether the mode
# prose (D) rides depend on the state at CALL time, not after this script has already changed it.
was_armed=0
companion_autopilot_on "$root" && was_armed=1

# A — disable autopilot first so the resumed pile is triaged, not autopiloted. Loud when it was
# on (don't silently clobber a persisted intent); quiet no-op when already off.
if [ "$was_armed" -eq 1 ]; then
  companion_autopilot_clear "$root"
  out="autopilot was ON — turned it OFF so the resumed pile comes back to you, not autopilot. Re-arm with /companion:autopilot on when you want to drain again."$'\n'
fi

# B — STEERING core, unless this repo opted out (R50 steering=off). Same two-tier split as before
# (R69's intent, if not its byte-cap enforcement mechanism): only the core above the injection
# marker, never the rationale below it — that stays on-demand reading.
if ! companion_feature_off steering "$root"; then
  if [ -f "$PLUGIN_DIR/STEERING.md" ]; then
    out="$out"$'\n\n'"── Working agreement — governs how you queue, decide, and keep this repo clean for the session ──"$'\n'"$(awk '/injection stops here/{exit} {print}' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || cat "$PLUGIN_DIR/STEERING.md")"
    # Mode prose (~2.7KB) rides only when the mode WAS armed at call time (R69) — dead weight
    # otherwise, and by the time we'd check post-clear it would always read "off".
    if [ "$was_armed" -eq 1 ]; then
      out="$out"$'\n'"$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || true)"
    fi
  fi
fi

# C — open tasks carried over from earlier sessions (unchanged from before the merge).
carry="$(companion_open_tasks "$root")"
if [ -n "$carry" ]; then
  out="$out"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"
else
  out="$out"$'\n\n'"No carried-over open tasks for $root."
fi

# D — INSTALLED-VS-WORKING-TREE VERSION LAG (unchanged rationale from the old SessionStart hook —
# still the failure this repo already paid for once: six hours of work inert on a stale cache).
_ver_running="$(jq -r '.version // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
_ver_name="$(jq -r '.name // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
if [ -n "$_ver_running" ] && [ -n "$_ver_name" ]; then
  for _m in "$root"/plugins/*/.claude-plugin/plugin.json; do
    [ -f "$_m" ] || continue
    [ "$(jq -r '.name // empty' "$_m" 2>/dev/null || true)" = "$_ver_name" ] || continue
    _ver_tree="$(jq -r '.version // empty' "$_m" 2>/dev/null || true)"
    if [ -n "$_ver_tree" ] && [ "$_ver_tree" != "$_ver_running" ]; then
      out="$out"$'\n\n'"⚠️  RUNNING v${_ver_running}, BUT THIS WORKING TREE IS v${_ver_tree}. Anything you add here is INERT until the plugin is reinstalled. Do not report a change as working because the repo is green; say which version actually ran."
    fi
    break
  done
fi

# E — this repo's accumulated gotchas (R30·d7). First match wins; two-tier like STEERING.
for lf in "$root/docs/LESSONS.md" "$root/LESSONS.md" "$root/.companion/LESSONS.md"; do
  [ -f "$lf" ] || continue
  out="$out"$'\n\n'"── This repo's LESSONS (accumulated gotchas — heed them, and append new ones as you learn them) ──"$'\n'"$(awk '/lessons injection stops here/{exit} {print}' "$lf" 2>/dev/null || cat "$lf")"
  break
done

# F — RECENT OUT-OF-BAND CHANGES (R93). Honesty, not silence: R93's own reasoning was that this
# class of fact must arrive UNASKED, because "go look" cannot survive a context clear — pulling it
# on demand instead reopens exactly the failure that motivated it (a days-long chase of the wrong
# cause because a real recent change wasn't top-of-mind). Kept here, on-demand, as the accepted
# cost of R100; not a fix for it.
_win="${CLAUDE_COMPANION_CHANGE_WINDOW_DAYS:-14}"
case "$_win" in ''|*[!0-9]*) _win=14 ;; esac
_cut="$(date -u -d "-${_win} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${_win}"d +%Y-%m-%d 2>/dev/null || true)"
if [ -n "$_cut" ]; then
  for cf in "$root/docs/CHANGES-OUTSIDE-GIT.md" "$root/CHANGES-OUTSIDE-GIT.md" "$root/.companion/CHANGES-OUTSIDE-GIT.md"; do
    [ -f "$cf" ] || continue
    _recent="$(tail -n 200 "$cf" 2>/dev/null | awk -v c="$_cut" '
      /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = ($2 >= c) }
      f' 2>/dev/null | head -c 2000)"
    [ -n "$_recent" ] && out="$out"$'\n\n'"── Changed OUTSIDE this repo in the last ${_win} days — git cannot show these, and they are the first thing to suspect when something breaks ──"$'\n'"$_recent"
    break
  done
fi

# G — REWORK, surfaced not narrated (R94). Zero bytes when nothing was recorded.
_rw="$(companion_rework_file "$root")"
if [ -f "$_rw" ]; then
  _rwout="$(REWORK_ROOT="$root" "$(dirname "$SELF")/rework.sh" report 2>/dev/null | head -c 800)"
  case "${_rwout:-}" in
    ''|rework:\ none*) : ;;
    *) out="$out"$'\n\n'"── REWORK already recorded here (work that had to be done twice — read it as your own defect rate, not as a list of catches) ──"$'\n'"$_rwout" ;;
  esac
fi

printf '%s\n' "$out"
