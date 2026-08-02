#!/usr/bin/env bash
# UserPromptSubmit — when the owner just says "continue" and the queue holds items that need THEM,
# say so at the moment it matters instead of hoping the model remembers.
#
# WHY A HOOK AND NOT STEERING (R28/R51). "On continue, review the parked pile first" is a reflex,
# and reflexes in prose are exactly what this project's own notes call its core weakness — the model
# may skip them, and a skipped one here means the owner types "continue" and gets more building on
# top of decisions they were never asked about. Injecting context is one of the three things code is
# allowed to do here, and this costs ZERO tokens in every session where nothing is parked.
#
# Deliberately NARROW. It fires only on a bare resume-style prompt: "continue", "keep going",
# "carry on", "proceed", "go on", "next" — optionally punctuated. Anything longer is a real
# instruction and must not be second-guessed, because the owner asking for something specific
# outranks a queue reflex. It also stays silent unless something is genuinely parked or blocked.
#
# Best-effort and non-blocking (R7/R68): every failure path exits 0 with no output, so a broken
# helper can never swallow the owner's prompt.
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
SELF="${BASH_SOURCE[0]}"
while [ -L "$SELF" ]; do
  link="$(readlink "$SELF")"
  case "$link" in /*) SELF="$link" ;; *) SELF="$(dirname "$SELF")/$link" ;; esac
done
# shellcheck source=../lib/companion.sh
. "$(cd "$(dirname "$SELF")/../lib" && pwd)/companion.sh"

in="$(cat 2>/dev/null || true)"
prompt="$(printf '%s' "$in" | jq -r '.prompt // empty' 2>/dev/null || true)"
[ -n "$prompt" ] || exit 0

# Normalise: trim, lowercase, drop trailing punctuation. Bash 3.2 has no ${x,,} (macOS ships 3.2).
norm="$(printf '%s' "$prompt" | tr '[:upper:]' '[:lower:]' \
        | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/[.!?[:space:]]*$//')"
case "$norm" in
  continue|"keep going"|"carry on"|proceed|"go on"|next|resume|"keep draining") : ;;
  *) exit 0 ;;
esac

cwd="$(printf '%s' "$in" | jq -r '.cwd // empty' 2>/dev/null || true)"; [ -n "$cwd" ] || cwd="$PWD"
root="$(companion_root "$cwd")"

# Count what needs the OWNER, not what needs building. Same classification the queue and the
# status line use: a ❓/⏳ prefix on the subject.
# -e alternation, NOT a [❓⏳] bracket: a bracket expression over multibyte characters is not
# portable — BSD grep (the macOS CI lane) can match bytes rather than characters.
pile="$(companion_open_tasks "$root" 2>/dev/null | grep '^  ◻' | grep -c -e '^  ◻ *❓' -e '^  ◻ *⏳' || true)"
case "$pile" in ''|*[!0-9]*) pile=0 ;; esac
[ "$pile" -gt 0 ] || exit 0        # nothing waiting on them → say nothing, just drain

if companion_autopilot_on "$root"; then
  ap="Autopilot is ON, so: run \`${SELF%/*}/autopilot.sh pause\` FIRST (the ask-guard blocks questions while it is armed and would park your questions instead of asking them), do the review, then run \`${SELF%/*}/autopilot.sh resume\` and carry straight on draining. Do not leave autopilot off afterwards — pause/resume exists so reviewing costs nothing."
else
  ap="Autopilot is off, so no pause is needed — just do the review, then continue in the normal loop."
fi

jq -cn --arg r "$ap" --arg n "$pile" '{hookSpecificOutput: {hookEventName: "UserPromptSubmit",
  additionalContext: ("BEFORE building anything: \($n) item(s) in the queue are waiting on the OWNER — parked ❓ decisions and/or blocked ⏳ manual jobs — and they typed a bare \"continue\". Run /companion:review FIRST: put the WHOLE pile to them up front (batched AskUserQuestion, up to 4 questions per call, recommendation-first — each park already carries its own `rec:`), write every pick back to the queue, and only then start work. Do not build on top of decisions they have not made. " + $r + " If the review turns out to be a no-op because every item is genuinely still blocked on them, say so in one line and drain the buildable queue instead.")}}'
