#!/usr/bin/env bash
# task-queue — support lib: SessionStart STATE-SIGNAL assembly.
#
# The per-repo mode banners the SessionStart hook appends after the policy/resume
# text — checkpoint-armed, schema-drift, agent-mode, solo(away) + staleness. Pulled
# out of bin/tq-resume.sh (which was assembling policy + resume + roadmap + these
# four branches in one long script) so the signal logic is one cohesive, testable
# unit and tq-resume just calls it. The banner STRINGS are load-bearing: several
# tests (away.bats, checkpoint.bats, tasks.bats) assert their exact substrings, so
# keep them verbatim when editing.
#
# Depends (sourced alongside by the caller) on lib/tasks.sh (tq_schema_status,
# tq_is_agent_mode), lib/away.sh (tq_is_away, tq_away_since) and lib/checkpoint.sh
# (tq_ckpt_enabled/exists/ref/restore_cmd). Read-only; emits text, writes nothing.

# Assemble the state-signal block for a repo, or empty when no mode is active.
# Blocks are joined by a blank line so the caller appends the whole thing once.
#   $1 root       absolute repo root
#   $2 solo_cmd   the "bash …/tq.sh solo" invocation (for the off hints)
#   $3 agent_cmd  the "bash …/tq.sh agent" invocation (for the off hint)
#   $4 plugin_dir the plugin root (for the checkpoint-disarm command)
tq_state_signals() {
  local root="$1" solo_cmd="$2" agent_cmd="$3" plugin_dir="$4"
  local out="" nl=$'\n\n' ckpt_line block since now stale_h hours

  # Append $1 as a block, blank-line-separated from whatever's already there.
  _sig_add() { [ -n "${1:-}" ] || return 0; out="${out:+$out$nl}$1"; }

  if tq_ckpt_enabled "$root"; then
    ckpt_line="🧷 Crash-checkpoint is ARMED — your working-tree edits are auto-snapshotted to a hidden ref ($(tq_ckpt_ref)) as you work, off your branch (history stays clean, nothing pushed)."
    if tq_ckpt_exists "$root"; then
      ckpt_line="$ckpt_line If a crash lost uncommitted edits this session, restore them with: $(tq_ckpt_restore_cmd)"
    fi
    ckpt_line="$ckpt_line (bash \"$plugin_dir/bin/tq-checkpoint.sh\" off to disarm.)"
    _sig_add "$ckpt_line"
  fi

  if [ "$(tq_schema_status 2>/dev/null || true)" = "drift" ]; then
    _sig_add "⚠️ [task-queue] The native task store no longer matches the expected schema — Claude Code may have changed it; carry-over/advance may be degraded (see CONTRACT.md)."
  fi

  if tq_is_agent_mode "$root"; then
    _sig_add "🤖 Agent-mode is ON — DEFAULT to fanning work out to subagents (Task tool) when it pays off in speed: parallel reads/exploration/audits across many files, independent per-item transforms, and parallel verification. Safe to parallelize = unblocked, no shared blockedBy, disjoint files, low blast radius. Keep INLINE: coupled/chained work, edits to shared or high-fan-in files, or when unsure — conflicting parallel edits are the risk the blast-radius principle guards against. Decide per-task from your task list; don't ask each time. ($agent_cmd off to disable for this repo.)"
  fi

  if tq_is_away "$root"; then
    block="🚶 AWAY mode is ON — the owner is away from the keyboard, so do NOT block on them: never call AskUserQuestion and never ask them to run a test or take a manual step. Keep going in auto and finish as much as you safely can, VERIFYING your own work (run the tests/build yourself — you have a shell). PARK — don't guess, don't execute — anything that genuinely needs them: a design/visual choice, a genuinely ambiguous fork, a test only they can run (physical device/GUI), and ESPECIALLY any irreversible or externally-binding action (delete data, push, send, spend money). Park it as a \"❓ [parked] <what needs deciding — with your recommendation>\" task; that is the open-questions bucket that re-surfaces on their next prompt and shows in hud, so they review the pile when back. Do all reversible work now. This is now ENFORCED, not just asked: AskUserQuestion is hard-blocked and the Stop hook auto-continues while any non-❓ task is still queued, so parking is the ONLY way to defer to them — you cannot idle with work left. ($solo_cmd off when the owner returns.)"
    # Staleness guard: solo persists across sessions, so nudge if it's been on a
    # long time — the owner may have forgotten to turn it off (footgun, not auto-off).
    since="$(tq_away_since "$root")"
    now="$(date +%s 2>/dev/null || echo 0)"
    stale_h="${CLAUDE_TQ_AWAY_STALE_HOURS:-12}"
    if [ "$since" -gt 0 ] && [ "$now" -gt 0 ]; then
      hours=$(( (now - since) / 3600 ))
      [ "$hours" -ge "$stale_h" ] && block="$block$nl⏳ SOLO mode has been on for ~${hours}h — if the owner is back, turn it off ($solo_cmd off) so the review loop resumes."
    fi
    _sig_add "$block"
  fi

  printf '%s' "$out"
}
