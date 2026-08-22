# The scheduled burn-down cycle

**What a scheduled run does, and what it must refuse to do.** Kept HERE rather than inside the
routine's prompt so it is versioned, reviewable and improvable by ordinary means — a prompt buried
in a scheduler config is the one instruction nobody can diff. Decision: [adr R116](./adr/README.md).

**Read this whole file before acting.** You are ONE bounded cycle, not a session that runs until
something stops you.

## Where you are

A fresh checkout of the plugin's SOURCE. **The plugin's hooks are NOT active** — hooks are served
from an installed plugin cache, which a sandbox does not have. So nothing injects the working
agreement, nothing refuses your stop, and nothing parks a question for you. Drive
`plugins/companion/bin/` directly and follow only this file.

## The cycle

1. **Arm the mode.** `./plugins/companion/bin/autopilot.sh burndown on`
   The flag is machine-local and deliberately not committed, so each sandbox arms its own.

2. **Ask permission — and respect a refusal.**
   `./plugins/companion/bin/burn-down.sh should-burn --scheduled`
   Non-zero exit → print the reason it gave and **STOP**. Do not retry it, do not work around it,
   do not edit anything first. **Holding is a correct, common and cheap outcome**: the caps exist
   to stop generation outrunning the owner's review. `--scheduled` already bypasses the rate-limit
   forecast (a sandbox has no status line to write one), so anything *still* refusing you is a real
   safety gate — the mode being off, real queued work outranking generated work, or the
   unreviewed-branch cap.

3. **Pick the work.** `./plugins/companion/bin/candidates.sh` → take the **highest-ranked line**.
   Prints nothing → stop and say so. **Never invent work.** Hardening outranks features by design
   (R116); do not reorder it.

4. **Record WHY before building.**
   `./plugins/companion/bin/burndown-branch.sh start "<candidate line verbatim>" --why "<rationale>"`
   The rationale must name **which of the project's ordered core values** it serves — *keep the
   project self-describing · contain blast radius · verify and stay aligned · subtract as you add* —
   your **cost estimate**, and **what you chose it over**. It lands in the branch manifest so the
   owner can correct your priorities, not just your output. If `start` refuses (tier ceiling,
   feature cap, dirty tree), print the reason and stop.

5. **Do the work, on that branch only.** Small and reversible. Any new behaviour needs a test.
   **Never** edit `docs/needs.yaml`, and do not rewrite `docs/requirements.yaml` — if the work
   implies a contract change, say so in the commit body and leave the contract alone (R86).

6. **`./check.sh` must be green.** If you cannot make it green, discard rather than ship noise:
   `./plugins/companion/bin/burndown-branch.sh discard <slug>` and stop.

7. **Commit on the `burndown/*` branch, then push it.**
   `git push -u origin <branch>`
   Pushing is required *only because the sandbox is ephemeral* — an unpushed branch dies with the
   container, and the owner would have nothing to review. **Never commit, merge, or push to the
   default branch. Never open a PR. Never merge anything.** The branch is a proposal.

8. **Report** in a few lines: what you built, which core value it served, what you chose it over,
   and the branch name. If you held at step 2 or 3, say so plainly and stop — a quiet cycle that
   did nothing is a success, not a failure to explain away.

## Standing refusals

- Never touch `main`.
- Never invent work when `candidates` is empty.
- Never bypass a refusal from `should-burn` or `burndown-branch start`.
- Never leave a red `check.sh` on a pushed branch.
- Never rewrite the contract (`docs/requirements.yaml`) or author a need (`docs/needs.yaml`).
