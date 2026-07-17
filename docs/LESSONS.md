# Lessons — repo-specific gotchas

Hard-won traps for *this* repo, so a future session doesn't re-discover them. Injected at
SessionStart with the queue (R30·d7). **Append a line when you learn a trap; keep it curated and
lean** — one terse line each, delete anything that stops being true. Not decisions (those are the
ledger) and not in-flight work (that's the queue) — just "watch out for X here."

## Shell / portability (the hooks are bash+jq, run on macOS bash 3.2 too)
- **bash 3.2 + emoji:** an unbraced `$VAR` immediately before a multibyte glyph (e.g. `$B🛡`)
  makes bash swallow the emoji's lead byte into the variable name → `set -u` "unbound variable"
  crash on macOS. Always brace: `${B}🛡`.
- **jq 1.7 + broken pipe:** `jq … | hook` where the hook exits at a disable-guard *before reading
  stdin* races into a closed pipe; jq prints "writing output failed: Broken pipe" to stderr, which
  bats merges into `$output` → flaky `[ -z "$output" ]`. Add `2>/dev/null` to the producing jq.
- **jq array-length precedence:** `[ [$o[]|select(..)]|length, … ]` mis-parses; use
  `[ ($s | map(select(..)) | length), … ]`.
- **Apostrophe in a single-quoted jq program:** hook deny/context messages are `jq -cn '{…"…"…}'`
  (single-quoted). A literal `'` in the message (e.g. `owner's`) terminates the quote → the program
  breaks at runtime AND shellcheck trips (SC1036/SC2026). Reword to avoid apostrophes
  (`the owner's call` → `belongs to the owner`).
- **Tab-joined `read` needs `IFS=$'\t'`:** any `read` splitting a tab-joined `jq` line whose last
  field is free text (a task subject) must set `IFS=$'\t'` — the trailing subject can carry spaces
  and a default-IFS split corrupts it (the confirmed R32·1 status-line bug). Readers: `statusline.sh`,
  `stop-autopilot.sh`. *(Was ledger R46; moved here 2026-07-17 — it's a gotcha, not a decision.)*

## Tests (bats)
- **git identity:** `git commit` in a test needs `-c user.email=t@t -c user.name=t` — CI's bare
  runner has no global identity and fails status 128 otherwise. **Same for a hook that commits**
  (ship-mode's auto-commit in `stop-autopilot.sh`): try the repo's identity, then fall back to
  `git -c user.name=… -c user.email=… commit`, or it silently captures nothing on an unconfigured
  machine.
- **`--print-output-on-failure`** on the `bats` call is what surfaces a flaky test's real
  `$output` in CI; keep it in `check.sh`.
- Tests live in `plugins/companion/tests/*.bats`, split by concern (core · hud). The 300-line size
  gate covers only `bin/`+`lib/`, not tests.

## CI
- macOS is a **required** lane (bash 3.2 — the strictest environment). Test hooks for *silence*
  under missing tooling, not for their happy-path effect.
