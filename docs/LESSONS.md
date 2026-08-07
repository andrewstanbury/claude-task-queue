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
  one shifts left. **Always US `$'\x1f'` — no carve-out** (the old `stop-autopilot.sh` exemption
  rested on its optional field being LAST). `@tsv` escapes `\n\r\t`; `join` does not.

## Tests (bats)
- **git identity:** `git commit` in a test needs `-c user.email=t@t -c user.name=t` — CI's bare
  runner has none and fails 128. **Same for a hook that commits** (ship-mode): fall back to
  `git -c user.name=… commit`, or it silently captures nothing on an unconfigured machine.
- **`--print-output-on-failure`** on the `bats` call is what surfaces a flaky test's `$output` in CI.
- **Never assert an exact countdown from `date +%s`, nor pin a fixture ON a threshold** — the code
  reads its clock a beat later, so `now+86400` arrives as 86399. Offset it.
- **An INTERRUPTED `--mutate` leaves enforced core MUTATED in the tree**, and `git status` is the
  only tell. A killed run left `doc-lint.sh` with BOM-stripping off and `ship.sh` blind to
  untracked critical paths — two gates failing OPEN, staged by the next `git add -A`. Two
  concurrent runs do the same to each other. After any interrupted run: `git status`, then
  `find . -name '*.mutbak'`. The gate now takes a lock and refuses a second run.
- **Measuring "did the suite go RED?" is meaningless if it was ALREADY red** — one pre-existing
  failure makes EVERY mutation report "caught", the most dangerous output this gate has: a clean
  bill of health for coverage it never observed. Require a green baseline before mutating.
- **"Green in the repo" is not "running for you."** Claude Code runs the plugin from its CACHE,
  not your checkout. A whole day's hooks were inert in the owner's own session while CI was green
  and the work was reported as shipped. Say which VERSION ran, not whether the tree is green.
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

- **`./check.sh` does NOT run the mutation gate — only `./check.sh --mutate` does, and CI runs it
  sharded.** So "PASS, N tests" is evidence about tests, never about mutation coverage, and
  reporting it as though the run were fully verified is how a declared HOLE shipped three times
  (4a86f91, a9d5ea6, 7c389d1 — each landed green locally, red in CI, on the same hole).
  Running mutations only for the files you touched has the same blind spot by construction: a hole
  elsewhere is invisible precisely because you did not touch it. Before claiming a change is
  verified, either run the full `--mutate` or say plainly that mutation coverage was not checked.
- **A test I write for code I just wrote tends to CONFIRM my own model of it, not falsify it —
  and "this is just a display/read-only command" is not evidence it's low-risk.** `board.sh`
  (2026-08-07) shipped its own passing tests, then a required DA pass found 3 real bugs in under
  an hour: one file that could not parse silently blanked the ENTIRE render (no fallback, exit 0),
  a `select($live|index(.))` filter that matched every id regardless of liveness (`.` rebinds to
  `$live` inside `index(.)`, not the mapped element — verify jq `select`/`index` interactions by
  running them, never by reading), and two new flags that could silently swallow each other as a
  value. None were caught by tests I wrote myself. Run the DA pass at real depth on NEW code
  regardless of how safe it looks — "read-only" is a property of intent, not of an untested
  implementation.
- **Never assert ABSENCE against a whole rendered line that embeds environment text.** The status
  line prints the project directory name; `_tmpd` generates a random one; a directory whose name
  happens to contain `5h` failed `[[ "$output" != *"5h"* ]]`. That is a red gate roughly once in
  hundreds of runs, unreproducible on rerun (31 clean), and it blocked the mutation gate — whose
  baseline guard correctly refused to measure against an already-red suite. Anchor absence to the
  STRUCTURE you mean (`[[ ! "$output" =~ 5h[[:space:]]*[▰▱] ]]` — the label slot before the bar),
  then prove the anchored form still fails on a real regression, or you have swapped a flake for a
  vacuous test.
- **jq 1.7 + broken pipe:** `jq … | hook` where the hook exits at a disable-guard *before reading
  stdin* races into a closed pipe; jq prints "Broken pipe" to stderr, which bats
  merges into `$output` → flaky `[ -z "$output" ]`. Add `2>/dev/null` to the producing jq.
- **A BACKTICK inside a DOUBLE-quoted argument runs as a command.** Twice in one day: once in a
  `--da` note (`` `: ; emit 5 rework` ``) and once in a `tq note` describing a new verb, which
  silently executed it and stored the note with the fragment DELETED. The failure is quiet — the
  text is simply missing, not an error — so check what was stored, not what you typed. Single-quote
  the argument, or drop the backticks.
- **An apostrophe inside a single-quoted jq program ENDS the program.** Demoted below this line
  earlier the same day as "shellcheck catches it" — then written straight into a `tq` comment
  (`owner's`) an hour later, breaking the script. The linter is not a substitute for the rule when
  you are editing INSIDE the quoted program. **Third strike: `index()'s`, written into a
  `stop-autopilot.sh` jq COMMENT that was itself explaining the fix.** A `#` comment inside the
  program is still inside the bash string — the quote does not care that the text is a comment.
  The tell is a hook that silently degrades (every field empty, so it fails open) rather than
  erroring: extract the program with `awk` and run it standalone and it works fine, because the
  extraction is what dropped the bash quoting.
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
- **An unescaped `&` in a sed REPLACEMENT expands to the whole match** — so a mutation can change
  the file (and pass validation) while re-inserting the very string it was meant to remove. It then
  reads as a HOLE in whatever guard searches for that string, sending you to debug the guard. Four
  sed-escaping traps in one session, all in mutation declarations, all invisible until CI: two
  delimiter collisions (`"$@"`), one `@{u}`, and this. `--validate` now catches three of the four.
- **A bulk regex over a file that also DEFINES the thing being rewritten will eat its own
  definition.** A rewrite introducing a `_stamp_root` helper matched the helper's own body and
  turned its write into a self-call — infinite recursion that presented as a hung test, costing
  three runs and two timeouts before it was read as recursion. Exclude the definition, or add the
  helper after the rewrite.
- **A permanently-failing test makes every mutation look CAUGHT.** Mutation verification is only
  meaningful against a passing test; check the test is green before trusting "ok caught". Twice in
  one session that produced verification worth nothing.
- **A mutation gate must distinguish "the suite failed" from "the suite never ran."** bats exits
  nonzero when KILLED (124) and when it cannot gather tests (a well-formed `1..1 / not ok
  bats-gather-tests`) — both having run nothing. Calibrate with `bats --count`, then require plan ==
  result-lines == count. The short version of this is above; the mechanism is here.
