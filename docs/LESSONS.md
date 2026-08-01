# Lessons — repo-specific gotchas

Traps for *this* repo, so a future session doesn't re-discover them. **Two-tier, like STEERING
(R69):** only the core above the injection marker near the end is injected at SessionStart
(R30·d7); everything below it is on-demand reading. **Append where it belongs** — a trap that has
bitten more than once, or that a gate cannot catch, goes above; a narrow one-off, something a
linter already catches, or version provenance goes below. Delete anything that stops being true.
Not decisions (the ledger) nor in-flight work (the queue).

## Shell / portability (the hooks are bash+jq, run on macOS bash 3.2 too)
- **bash 3.2 + emoji:** an unbraced `$VAR` before a multibyte glyph (`$B🛡`) swallows the emoji's
  lead byte into the variable name → `set -u` crash on macOS. Always brace: `${B}🛡`.
- **jq `+` THROWS on a non-string** — `.a + "\n" + .b` emits nothing when `.b` is an array/object
  (NotebookEdit's `new_source`), so the caller reads empty and **fails open**. `| tostring` always.
- **BSD is not GNU — shipped red CI three times.** `\?`/`\+`/`\|` in `sed`/`grep` are GNU extensions
  BSD reads as LITERALS; an escaped `^` in a BRE differs too; BSD `wc -c` pads with spaces, so a
  digits-only guard reads garbage and zeroes the value. Strip: `wc -c < f | tr -d '[:space:]'`.
- **`printf '%s'` writes NO trailing newline**, so `read` returns 1 *having set the variable*. Test
  the VARIABLE, never `read`'s status — `read x < f && use "$x"` silently drops every such file
  (`.repo`/`.root` markers, the autopilot continue-file).
- **`grep -Ef <file>` compiles EVERY line as a regex, comments included.** One `(` in prose makes
  grep exit 2, the caller reads an empty match, and the gate **silently does not fire**. Strip
  `^#`/blanks first; treat grep's exit ≥2 as fail-CLOSED.
- **TAB is IFS *whitespace*: `IFS=$'\t' read` COLLAPSES repeats**, so every field after an EMPTY
  one shifts left, silently. Safe only where no field can be empty (`stop-autopilot.sh`); with any
  optional field use **US `$'\x1f'`** (`statusline.sh`). `@tsv` escapes `\n\r\t`; `join` does not.

## Tests (bats)
- **git identity:** `git commit` in a test needs `-c user.email=t@t -c user.name=t` — CI's bare
  runner has none and fails 128. **Same for a hook that commits** (ship-mode): fall back to
  `git -c user.name=… commit`, or it silently captures nothing on an unconfigured machine.
- **`--print-output-on-failure`** on the `bats` call is what surfaces a flaky test's `$output` in CI.
- **Never assert an exact countdown from `date +%s`** — `now + 42m` floors to `41m` the moment a
  second passes. Assert unit and presence (`↻[0-9]+m`), never the count.
- **An INTERRUPTED `--mutate` leaves enforced core MUTATED in the tree**, and `git status` is the
  only tell. A killed run left `doc-lint.sh` with BOM-stripping off and `ship.sh` blind to
  untracked critical paths — two gates failing OPEN, staged by the next `git add -A`. Two
  concurrent runs do the same to each other. After any interrupted run: `git status`, then
  `find . -name '*.mutbak'`. The gate now takes a lock and refuses a second run.
- **Measuring "did the suite go RED?" is meaningless if it was ALREADY red** — one pre-existing
  failure makes EVERY mutation report "caught", the most dangerous output this gate has: a clean
  bill of health for coverage it never observed. Require a green baseline before mutating.
- **Three ways a check silently CANNOT FAIL.** (1) It re-implements the logic — one re-grepped a
  gate's config and passed with that gate **deleted**. (2) It reads "nonzero = detected" —
  `--mutate` scored a KILLED suite (124, nothing run) as "caught", so a real hole read as covered,
  green locally and red on CI; demand the specific signal (`^not ok`), nonzero without it is an
  error. (3) A retune drops the fake bad input under the noise floor, and the guard stops guarding — pin
  guards to the threshold they assert, and re-run them after any retune.
  Pipe through the real script, **shim the tool on PATH** to test a gate without recursion, and
  mutate to confirm it CAN redden.
- **`cmd && { …; false; }` fails a bats test when `cmd` correctly returns non-zero.** Use `if`.

## Frontmatter (commands / skills)
- **Quote any YAML value starting with `[`, `{`, `*`, `&`, `!`, `>`, `|`, `,` or `#`.** An unquoted
  `description: [target] …` opens a flow sequence: js-yaml throws, discards the **whole frontmatter**
  and logs at *debug*. Six commands were one `land` from shipping that.
- **`check.sh` line-greps frontmatter, so it can never see a parse failure** — an assertion on a
  *value* validates a string the host may never have loaded. Verify with a real YAML parser.
- **Extraction leaves three traps.** (1) A second COPY — grep the old shape. (2) Orphaned
  MUTATIONS — `mutations.txt` still aims at the old file, matching nothing; re-aim in the SAME
  commit (5x). (3) A MOVED failure mode — code hoisted into a helper runs in `$( )`, which
  *isolates* an abort, so deleting its guard changed no output, only stderr.
- **A reader returning EMPTY on malformed input fails open, silently.** `NR==1&&$0=="---"` returned
  nothing for a CRLF file and every check on that block passed vacuously. When a parser can say
  "nothing here", ask what callers do with nothing — usually: succeed.

## CI
- macOS is a **required** lane (bash 3.2). Test hooks for *silence* under missing tooling.
- **`gitleaks` + `shellcheck` SKIP locally when absent but RUN on CI** — a local PASS is not a CI
  PASS. Linuxbrew's `shellcheck` under-reports `SC2015` (`A && B || C`) that CI flags — shipped red
  twice. **Never write `test && test || cmd` as a guard.** Codes split both ways: a trap-invoked
  function is `SC2329` locally, `SC2317` on CI — disable **both**.

<!-- lessons injection stops here — everything below is ON DEMAND, not injected per session -->

## On demand — narrow, linter-caught, or historical

These earned a place in the record but not in every session's context. Read them when working in
the area, or when a gate points here.

- **jq 1.7 + broken pipe:** `jq … | hook` where the hook exits at a disable-guard *before reading
  stdin* races into a closed pipe; jq prints "Broken pipe" to stderr, which bats
  merges into `$output` → flaky `[ -z "$output" ]`. Add `2>/dev/null` to the producing jq.
- **jq array-length precedence:** `[ [$o[]|select(..)]|length ]` mis-parses; use
  `[ ($s|map(select(..))|length) ]`. (A literal `'` in a single-quoted jq program also breaks it —
  shellcheck SC1036/SC2026 catches that one for you.)
- **`TIMEFORMAT` renders through the locale**: under de_DE, `%3R` is `0,124`, a digits-only guard
  rejects every sample, and a timing gate measures **0** and reports green. `export LC_ALL=C` in
  anything that parses `time`.
- **`PIPESTATUS` does not survive `$( )`** — it reports the *parent's* last pipeline, so a
  fail-closed check on it never fires. With `set -o pipefail`, use plain `$?` on the assignment.
- **A command exiting without reading stdin SIGPIPEs its writer** — with `pipefail` that becomes 141
  and trips the "unexpected error" branch. Feed it `<<<"$var"`, not a pipe.
- **Colour:** never assert via `cat -v` + `grep`; prefix-match the literal escape in bash
  (`esc=$'\033'; case "${out#*label}" in "$esc[0m$esc[32m"*)`). Neutralise the caller's env with
  `env -u NO_COLOR TERM=xterm`, or an exported `NO_COLOR` reddens a correct tree.
- **Apostrophe in a single-quoted jq program:** a literal `'` in a `jq -cn '{…}'` message ends the
  quote → runtime break. **Reword around it.** Below the line because shellcheck catches it for you
  (SC1036/SC2026) — the gate is the enforcement, so it need not also be context.
- **SC2015 provenance:** the `A && B || C` split shipped red CI in 3.16.0 and 3.17.0 — two separate
  ships before the rule above was written down.
- **Extraction/orphaned-mutation provenance:** 3.24.3, 3.27.0, 3.29.0, 3.30.0, 3.31.0. Five times,
  which is why the rule above is stated as a check to run rather than a thing to remember.
- **`--print-output-on-failure`** on the `bats` call is what surfaces a failing test's `$output` in
  CI. Worth knowing the day a CI-only failure prints nothing useful.
- **A flag consumed twice by a wrapper eats the first real argument.** Extracting `--mutate` from
  `check.sh` left the old `shift` in the new script, so `--mutate <file>` dropped the file and ran
  the FULL 31-mutation set (~35 min instead of ~2). CI never noticed — it passes no filter, so the
  only broken path was the one only humans use. Ask what CI does NOT exercise.
- **A mutation gate must distinguish "the suite failed" from "the suite never ran."** bats exits
  nonzero when KILLED (124) and when it cannot gather tests (a well-formed `1..1 / not ok
  bats-gather-tests`) — both having run nothing. Calibrate with `bats --count`, then require plan ==
  result-lines == count. The short version of this is above; the mechanism is here.
