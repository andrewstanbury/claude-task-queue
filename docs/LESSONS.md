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
- **BSD is not GNU — this has shipped red CI three times.** `\?`/`\+`/`\|` in `sed`/`grep` are GNU
  extensions BSD reads as LITERALS, so the expression matches nothing and the check silently
  passes locally (3.24.1). A backslash-escaped `^` in a BRE differs the same way (3.20.0). And
  BSD `wc` pads with leading whitespace: `wc -c < f` emits `"  1200000"`, so a
  digits-only guard (`case … *[!0-9]*`) reads it as garbage and zeroes the value — the 3.13.0
  capture-rotation bug (green locally on GNU, red on macOS CI). Strip first:
  `wc -c < f | tr -d '[:space:]'`.
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
- **Never assert on ANSI colour via `cat -v` + `grep`** — prefix-match the literal escape in pure
  bash: `esc=$'\033'; case "${out#*label}" in "$esc[0m$esc[32m"*) … esac`. No tool, no dialect.
- **A colour test must neutralise the caller's env**: `env -u NO_COLOR TERM=xterm` on the
  invocation, or a maintainer who exports `NO_COLOR` gets a red gate on a correct tree.
- **Never assert an exact countdown built from `date +%s`.** `now + 42m` floors to `41m` the
  moment a second passes between building the payload and the script reading the clock. Assert
  the unit and presence (`↻[0-9]+m`), never the remaining count.
- Tests live in `plugins/companion/tests/*.bats`, split by concern (core · hud). The 300-line size
  gate covers only `bin/`+`lib/`, not tests.

## Frontmatter (commands / skills)
- **Quote any YAML value that starts with `[`, `{`, `*`, `&`, `!`, `>`, `|`, `,` or `#`.** An
  unquoted `description: [target] …` opens a **flow sequence**: the host's js-yaml throws, discards
  the **whole frontmatter** (description *and* argument-hint), and logs it at *debug* level — the
  command just quietly loses both. Six commands were one `land` away from shipping that.
- **`check.sh` line-greps frontmatter, so it can never see a parse failure.** Any assertion about a
  frontmatter *value* is validating a string the host may never have loaded. Verify with a real YAML
  parser (`python3 -m venv` + pyyaml is enough) before trusting an `awk -F'key: '` extraction —
  checking with the same naive reader that introduced the bug proves nothing.

- **Every extraction leaves a second copy — grep for the old shape before calling it done.** Both
  self-inflicted bugs this session were that: a restore trap globbing only `plugins/` after the
  mutation set grew to `check.sh`, and a frontmatter `awk` duplicated into `check.sh`.
- **A reader returning EMPTY on malformed input fails open, silently.** `NR==1&&$0=="---"` returned
  nothing for a CRLF file and every check on that block passed vacuously. When a parser can say
  "nothing here", ask what callers do with nothing — usually: succeed.

## CI
- macOS is a **required** lane (bash 3.2 — the strictest environment). Test hooks for *silence*
  under missing tooling, not for their happy-path effect.
- **`gitleaks` + `shellcheck` are SKIPped locally when absent but RUN on CI** — so a local
  `check.sh` PASS is not a CI PASS for those two. The linuxbrew `shellcheck` build additionally
  **under-reports `SC2015`** (`A && B || C`) that CI's build flags — this shipped a red CI twice
  (3.16.0, 3.17.0). **Never use `test && test || cmd` for a guard; write `if [ … ]; then cmd; fi`.**
  When touching `bin/`, trust CI's shellcheck over local, or grep for `\] && \[ .* \] || ` before shipping.
  **The version split cuts both ways on CODES too:** a trap-invoked function is `SC2329` on local
  0.11 and `SC2317` on CI's older build — disable **both** or CI reddens on a locally-clean tree.
