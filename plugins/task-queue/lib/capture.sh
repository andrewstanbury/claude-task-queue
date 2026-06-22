#!/usr/bin/env bash
# capture — heuristics for the UserPromptSubmit capture nudge (bin/tq-capture.sh).
#
# Kept out of tasks.sh so the core stays small and loadable; this is sourced
# only by the capture hook.

# Conservative heuristic: does this prompt look like multi-step work worth
# queuing? Errs toward NOT firing — a false nudge is noise, but a miss is
# harmless (the SessionStart policy still covers capture). Returns 0 yes / 1 no.
tq_looks_multistep() {
  local p="$1" low n=0 v
  [ "$(printf '%s' "$p" | wc -w)" -ge 8 ] || return 1      # too short to be multi-step
  low="$(printf '%s' "$p" | tr '[:upper:]' '[:lower:]')"
  case "$low" in
    *" then "*|*" also "*|*" after that "*) return 0 ;;   # " then " covers "and then" / ", then"
  esac
  printf '%s' "$p" | grep -qE '(^|[[:space:]])([0-9]+[.)]|[-*][[:space:]])' && return 0  # list markers
  for v in add fix implement refactor build create update remove rename migrate \
           write test wire integrate support handle setup configure; do
    case "$low" in *"$v "*) n=$((n + 1)) ;; esac
  done
  [ "$n" -ge 2 ]                                            # 2+ action verbs → multi-step
}

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

# Is the repo at $root a Godot project? (a project.godot manifest at the root.)
# Used to stand down the wireframe design-preview: that preview is a web-UI
# convention (box/input/button layouts) and misleads on a game's scene/sprite
# visuals — there the "demonstrate before build" step is running the game, not an
# ASCII mockup. Returns 0 yes / 1 no.
tq_is_godot_project() {
  local root="$1"
  [ -n "$root" ] && [ -f "$root/project.godot" ]
}

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
  printf " First weigh it against %s — flag any drift or contradiction (don't reverse a recorded decision) before you capture." "$anchor"
}
