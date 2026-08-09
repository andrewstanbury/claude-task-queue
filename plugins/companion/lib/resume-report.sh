#!/usr/bin/env bash
# The session-context content builders — the single source of truth for what "resume" prints,
# shared by resume.sh (manual pull, R100/Pass 2) and session-start.sh (automatic push, R100/Pass 6
# reinstated — the owner asked for guaranteed context delivery back, having watched a model ignore
# instructions it never actually had in context). Extracted rather than duplicated: two copies of
# this content generator would drift on what "the resume content" means the moment either changed.
#
# Split in two because a fresh session start and a post-compaction re-anchor want different
# amounts of the STEERING core (full core vs a short re-anchor, R30·d2 — the doc's rationale is
# preserved through the summarizer, re-pasting it every compaction is the token cost this split
# avoids) but IDENTICAL everything else: carried tasks, the version-lag warning, LESSONS, R93's
# out-of-band changes, and R94's rework are all cheap (zero-cost when empty) and equally relevant
# after a compaction as at a fresh start — a compaction IS the state clear R93 exists to survive.

# companion_resume_steering ROOT PLUGIN_DIR WAS_ARMED -> the STEERING core (unless steering=off),
# with the mode prose appended when WAS_ARMED=1. Empty string when steering is off or absent.
companion_resume_steering() {
  local root="$1" PLUGIN_DIR="$2" was_armed="${3:-0}" out=""
  if ! companion_feature_off steering "$root"; then
    if [ -f "$PLUGIN_DIR/STEERING.md" ]; then
      out="── Working agreement — governs how you queue, decide, and keep this repo clean for the session ──"$'\n'"$(awk '/injection stops here/{exit} {print}' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || cat "$PLUGIN_DIR/STEERING.md")"
      if [ "$was_armed" -eq 1 ]; then
        out="$out"$'\n'"$(awk '/autopilot:start/{f=1;next} /autopilot:end/{f=0} f' "$PLUGIN_DIR/STEERING.md" 2>/dev/null || true)"
      fi
    fi
  fi
  printf '%s' "$out"
}

# companion_resume_report ROOT PLUGIN_DIR -> carried tasks + version-lag warning + LESSONS +
# recent out-of-band changes (R93) + recorded rework (R94). Deliberately does NOT include
# STEERING — see companion_resume_steering — so a caller can pair a short message with the full
# report (the compact re-anchor) instead of the full STEERING core with it (a fresh start).
companion_resume_report() {
  local root="$1" PLUGIN_DIR="$2" out=""

  local carry; carry="$(companion_open_tasks "$root")"
  if [ -n "$carry" ]; then
    out="$out"$'\n\n'"── Open tasks carried over from an earlier session (reinstate before new work) ──"$'\n'"$carry"
  else
    out="$out"$'\n\n'"No carried-over open tasks for $root."
  fi

  local _ver_running _ver_name
  _ver_running="$(jq -r '.version // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
  _ver_name="$(jq -r '.name // empty' "$PLUGIN_DIR/.claude-plugin/plugin.json" 2>/dev/null || true)"
  if [ -n "$_ver_running" ] && [ -n "$_ver_name" ]; then
    local _m _ver_tree
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

  local lf
  for lf in "$root/docs/LESSONS.md" "$root/LESSONS.md" "$root/.companion/LESSONS.md"; do
    [ -f "$lf" ] || continue
    out="$out"$'\n\n'"── This repo's LESSONS (accumulated gotchas — heed them, and append new ones as you learn them) ──"$'\n'"$(awk '/lessons injection stops here/{exit} {print}' "$lf" 2>/dev/null || cat "$lf")"
    break
  done

  local _win _cut
  _win="${CLAUDE_COMPANION_CHANGE_WINDOW_DAYS:-14}"
  case "$_win" in ''|*[!0-9]*) _win=14 ;; esac
  _cut="$(date -u -d "-${_win} days" +%Y-%m-%d 2>/dev/null || date -u -v-"${_win}"d +%Y-%m-%d 2>/dev/null || true)"
  if [ -n "$_cut" ]; then
    local cf _recent
    for cf in "$root/docs/CHANGES-OUTSIDE-GIT.md" "$root/CHANGES-OUTSIDE-GIT.md" "$root/.companion/CHANGES-OUTSIDE-GIT.md"; do
      [ -f "$cf" ] || continue
      _recent="$(tail -n 200 "$cf" 2>/dev/null | awk -v c="$_cut" '
        /^- [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/ { f = ($2 >= c) }
        f' 2>/dev/null | head -c 2000)"
      [ -n "$_recent" ] && out="$out"$'\n\n'"── Changed OUTSIDE this repo in the last ${_win} days — git cannot show these, and they are the first thing to suspect when something breaks ──"$'\n'"$_recent"
      break
    done
  fi

  local _rw _rwout
  _rw="$(companion_rework_file "$root")"
  if [ -f "$_rw" ]; then
    _rwout="$(REWORK_ROOT="$root" "$PLUGIN_DIR/bin/rework.sh" report 2>/dev/null | head -c 800)"
    case "${_rwout:-}" in
      ''|rework:\ none*) : ;;
      *) out="$out"$'\n\n'"── REWORK already recorded here (work that had to be done twice — read it as your own defect rate, not as a list of catches) ──"$'\n'"$_rwout" ;;
    esac
  fi

  printf '%s' "$out"
}
