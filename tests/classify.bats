#!/usr/bin/env bats

setup() {
  THIS_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
  . "$THIS_DIR/lib/classify.sh"
}

@test "blank prompt is trivial" {
  ! tq_classify ""
}

@test "slash command is trivial" {
  ! tq_classify "/help"
}

@test "bang shell line is trivial" {
  ! tq_classify "!ls -la"
}

@test "short yes-no is trivial" {
  ! tq_classify "yes please"
}

@test "single action verb under 4 words is trivial" {
  # "fix it now" is only 3 words → still trivial.
  ! tq_classify "fix it now"
}

@test "explicit build request is non-trivial" {
  tq_classify "Please build the offline media auto-download feature"
}

@test "compound 'and' request is non-trivial" {
  tq_classify "do A and B and C"
}

@test "long descriptive prompt without action verbs is non-trivial" {
  prompt="for the offline mode feature in the client app I would like the system to automatically download all content especially the program as soon as it is active or assigned"
  tq_classify "$prompt"
}

@test "review request is non-trivial" {
  tq_classify "review the PR I just opened"
}

# --- tq_plan_trigger --------------------------------------------------------

@test "plan: prefix is a trigger and is stripped" {
  run tq_plan_trigger "plan: build the auth flow"
  [ "$status" -eq 0 ]
  [ "$output" = "build the auth flow" ]
}

@test "bare 'plan ' prefix is a trigger and is stripped" {
  run tq_plan_trigger "Plan the migration in three steps"
  [ "$status" -eq 0 ]
  [ "$output" = "the migration in three steps" ]
}

@test "no plan prefix is not a trigger and prompt passes through unchanged" {
  run tq_plan_trigger "build the auth flow"
  [ "$status" -eq 1 ]
  [ "$output" = "build the auth flow" ]
}

@test "'planner' is not a false trigger" {
  run tq_plan_trigger "planner component needs a test"
  [ "$status" -eq 1 ]
  [ "$output" = "planner component needs a test" ]
}

# --- tq_should_triage -------------------------------------------------------

@test "queue-first: triage fires on any non-trivial prompt (empty queue)" {
  tq_should_triage 1 0 0
}

@test "queue-first: triage still fires on non-trivial even when work is queued" {
  # The legacy 3rd arg (has_actionable=1) is ignored — queue-first never skips.
  tq_should_triage 1 0 1
}

@test "plan trigger forces triage regardless of queue state" {
  tq_should_triage 1 1 1
}

@test "trivial prompt never triages" {
  ! tq_should_triage 0 0 0
  ! tq_should_triage 0 0 1
}
