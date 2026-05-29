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
