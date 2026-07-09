#!/usr/bin/env bash
# capture — heuristics for the UserPromptSubmit capture nudge (bin/tq-capture.sh).
#
# Kept out of tasks.sh so the core stays small and loadable; this is sourced
# only by the capture hook.

# NOTE: the multi-step heuristic (tq_looks_multistep) was removed 2026-06-26 when
# the capture hook stopped gating on "substantive" — every prompt now routes
# through the review loop, so there is nothing left to classify multi-step-ness
# for. consequential/design detection below remains: it selects which VARIANT of
# the loop fires, not whether it fires.

# Does this prompt ask for something CONSEQUENTIAL — irreversible or externally
# binding — that warrants extra scrutiny in the review loop? The categories mirror
# the native permissions deny/ask set (settings.json) so the system stays coherent.
# A single "drop the prod table" earns the loop with extra emphasis even though it
# isn't multi-step.
#
# Tuned for PRECISION, not recall: it must NOT fire on routine edits, because a
# gate that fires on "remove the unused import" trains rubber-stamping and taxes
# every prompt with a decompose+approve round-trip — the opposite of the token
# efficiency this project optimizes for. So bare verbs (delete/remove/drop) are
# deliberately excluded; only high-signal forms match — destructive shell/VCS, a
# delete/drop/truncate aimed at a table/database, SQL DML, data migrations, paid
# deps, and a deploy-verb aimed at production. Misses some genuinely consequential
# NL phrasings by design — charter's just-in-time action surfacing is the backstop.
# Returns 0 yes / 1 no.
tq_looks_consequential() {
  local p="$1"
  printf '%s' "$p" | grep -Eiq \
    'rm[[:space:]]+-[a-z]*[rf]|reset[[:space:]]+--hard|force[ -]?push|push[[:space:]].*(--force|-f([[:space:]]|$))|(drop|delete|truncate)([[:space:]]+[[:alnum:]_-]+){0,3}[[:space:]]+(tables?|databases?|schema)|delete[[:space:]]+from|migrat(e|ion)|backfill|alter[[:space:]]+table|schema[[:space:]]+change|(^|[^[:alnum:]])(paid|subscription|subscribe|license|purchase|billing)([^[:alnum:]]|$)|credit[[:space:]]+card|(deploy|release|ship|rollout)([[:space:]]+[[:alnum:]_-]+){0,4}[[:space:]]+prod(uction)?'
}

# Does this prompt ask for a VISUAL / UI / layout change worth PREVIEWING before
# building? The owner is non-technical and verifies by SEEING, so a visual change
# earns a recommended-plus-alternatives ASCII preview (via AskUserQuestion) before
# a line of code is written — the "demonstrate" half of the owner loop, moved ahead
# of the work. PRECISION-tuned like tq_looks_consequential: it must NOT fire on
# architecture/API "design" or functional edits (add a button, fix a slow page) —
# only on a visual/appearance INTENT applied to a UI element, an unambiguous
# visual VERB on its own (restyle/reskin/recolour…), or an inherently-visual
# term on its own. Returns 0 yes / 1 no.
tq_looks_design() {
  local p="$1" low
  low="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  # (A) inherently-visual terms — fire on their own.
  printf '%s' "$low" | grep -Eq \
    '(^|[^a-z])(layouts?|wireframes?|mock[- ]?ups?|ui|ux|user interface|design systems?|style[ -]?guides?|colou?r schemes?|colou?r palettes?|palettes?|typograph(y|ic))([^a-z]|$)' && return 0
  # (A2) unambiguous visual-appearance VERBS — fire on their own. These have no
  # non-visual meaning, so they need no paired noun ("restyle it", "reskin the app").
  printf '%s' "$low" | grep -Eq \
    '(^|[^a-z])(re-?style|re-?skin|re-?colou?r|re-?theme|re-?paint|prettif(y|ied)|beautif(y|ied))([^a-z]|$)' && return 0
  # (B) an AMBIGUOUS visual/appearance INTENT *and* a UI NOUN must both be present.
  # "design"/"move"/"style" alone could be architecture, so a UI noun is required —
  # this is what keeps "redesign the API/schema" from tripping the preview.
  printf '%s' "$low" | grep -Eq \
    '(^|[^a-z])((re-?)?design|(re-?)?lay[ -]?out|reposition|rearrange|re-?order|re-?align|realign|resize|move|cent(er|re)|style|theme|skin|looks?|looking|appearance|responsive|cleaner|prettier|sleeker|modern|polished|spacing|align(ment)?|visuals?|aesthetics?)([^a-z]|$)' || return 1
  printf '%s' "$low" | grep -Eq \
    '(^|[^a-z])(buttons?|pages?|home[- ]?pages?|landing[- ]?pages?|web[- ]?pages?|screens?|home[- ]?screens?|splash|views?|forms?|modals?|dialogs?|navs?|navbars?|navigation|sidebars?|menus?|headers?|footers?|heroe?s?|banners?|cards?|dashboards?|landing|panels?|tabs?|toolbars?|components?|widgets?|icons?|logos?|popups?|drop[- ]?downs?|tooltips?|badges?|avatars?|carousels?|accordions?|grids?|sections?|tables?|lists?|profiles?|settings|onboarding|checkouts?|paywalls?|drawers?|galler(y|ies)|feeds?|chips?|toasts?|snackbars?|spinners?|loaders?|skeletons?|empty states?)([^a-z]|$)' || return 1
  return 0
}

# Design-preview gate marker (per session). On a present visual/design turn the capture
# hook arms this; the PreToolUse design guard (bin/tq-design-guard.sh) then blocks edits
# until a wireframe preview has been shown (the ask-guard clears it when an
# AskUserQuestion fires). Enforces "show before you build" so a visual change can't be
# coded before the owner has seen it. Lives in the SHARED away dir (tq_away_dir, from
# away.sh — sourced by every caller) beside present-<sid>/review-<root>, NOT the private
# plugin-data state dir, so hud can mirror it read-only for the 🎨 status slot (hud can't
# reach task-queue's CLAUDE_PLUGIN_DATA). `design-` prefix never collides with those.
tq_design_file()    { printf '%s/design-%s' "$(tq_away_dir)" "$(printf '%s' "${1:-nosession}" | sed 's:/:-:g')"; }
tq_design_set()     { [ -n "${1:-}" ] || return 0; mkdir -p "$(tq_away_dir)" 2>/dev/null || true; : > "$(tq_design_file "$1")" 2>/dev/null || true; }
tq_design_clear()   { [ -n "${1:-}" ] && rm -f "$(tq_design_file "$1")" 2>/dev/null || true; }
tq_design_pending() { [ -n "${1:-}" ] && [ -f "$(tq_design_file "$1")" ]; }

# Build the " First weigh it against <decisions/backlog> ..." alignment clause for
# the repo at $cwd, or empty if the project records no direction. Shared by the
# capture nudge and the consequential review-gate so neither duplicates it — the
# orchestration arm of charter's decisions anchor (clean ≠ correct). Depends on
# project.sh (tq_root_for_cwd / tq_decisions_path / tq_roadmap_path), sourced by
# the caller. Costs only local file checks (no model cost).
tq_alignment_clause() {
  local cwd="$1" root dpath rpath anchor=""
  [ -n "$cwd" ] || cwd="$PWD"
  root="$(tq_root_for_cwd "$cwd")"
  dpath="$(tq_decisions_path "$root" 2>/dev/null || true)"
  rpath="$(tq_roadmap_path "$root" 2>/dev/null || true)"
  [ -n "$dpath" ] && anchor="recorded decisions ($dpath)"
  [ -n "$rpath" ] && { [ -n "$anchor" ] && anchor="$anchor and the backlog ($rpath)" || anchor="the backlog ($rpath)"; }
  [ -n "$anchor" ] || return 0
  printf " First weigh it against %s — flag any drift or contradiction (neither the old nor the new wins silently) before you capture." "$anchor"
}
