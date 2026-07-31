# Lessons — repo-specific gotchas

Traps for *this* repo, so a future session doesn't re-discover them. Injected at SessionStart
with the queue (R30·d7). **Append a line when you learn one; keep it lean** — delete anything that
stops being true. Not decisions (the ledger) nor in-flight work (the queue).

## Shell / portability (the hooks are bash+jq, run on macOS bash 3.2 too)
- **bash 3.2 + emoji:** an unbraced `$VAR` before a multibyte glyph (`$B🛡`) swallows the emoji's
  lead byte into the variable name → `set -u` crash on macOS. Always brace: `${B}🛡`.
- **jq 1.7 + broken pipe:** `jq … | hook` where the hook exits at a disable-guard *before reading
  stdin* races into a closed pipe; jq prints "Broken pipe" to stderr, which bats
  merges into `$output` → flaky `[ -z "$output" ]`. Add `2>/dev/null` to the producing jq.
- **jq array-length precedence:** `[ [$o[]|select(..)]|length ]` mis-parses; use
  `[ ($s|map(select(..))|length) ]`.
- **jq `+` THROWS on a non-string** — `.a + "\n" + .b` emits nothing when `.b` is an array/object
  (NotebookEdit's `new_source`), so the caller reads empty and **fails open**. `| tostring` always.
- **Apostrophe in a single-quoted jq program:** a literal `'` in a `jq -cn '{…}'` message ends the
  quote → runtime break + shellcheck SC1036/SC2026. Reword around it.
- **BSD is not GNU — shipped red CI three times.** `\?`/`\+`/`\|` in `sed`/`grep` are GNU extensions
  BSD reads as LITERALS; an escaped `^` in a BRE differs too; BSD `wc -c` pads with spaces, so a
  digits-only guard reads garbage and zeroes the value. Strip: `wc -c < f | tr -d '[:space:]'`.
- **`printf '%s'` writes NO trailing newline**, so `read` returns 1 *having set the variable*. Test
  the VARIABLE, never `read`'s status — `read x < f && use "$x"` silently drops every such file
  (`.repo`/`.root` markers, the autopilot continue-file).
- **`grep -Ef <file>` compiles EVERY line as a regex, comments included.** One `(` in prose makes
  grep exit 2, the caller reads an empty match, and the gate **silently does not fire**. Strip
  `^#`/blanks first; treat grep's exit ≥2 as fail-CLOSED.
- **`PIPESTATUS` does not survive `$( )`** — it reports the *parent's* last pipeline, so a
  fail-closed check on it never fires. With `set -o pipefail`, use plain `$?` on the assignment.
- **`TIMEFORMAT` renders through the locale**: under de_DE, `%3R` is `0,124`, a digits-only guard
  rejects every sample, and a timing gate measures **0** and reports green. `export LC_ALL=C` in
  anything that parses `time`.
- **A command exiting without reading stdin SIGPIPEs its writer** — with `pipefail` that becomes 141
  and trips the "unexpected error" branch. Feed it `<<<"$var"`, not a pipe.
- **TAB is IFS *whitespace*: `IFS=$'\t' read` COLLAPSES repeats**, so every field after an EMPTY
  one shifts left, silently. Safe only where no field can be empty (`stop-autopilot.sh`); with any
  optional field use **US `$'\x1f'`** (`statusline.sh`). `@tsv` escapes `\n\r\t`; `join` does not.

## Tests (bats)
- **git identity:** `git commit` in a test needs `-c user.email=t@t -c user.name=t` — CI's bare
  runner has none and fails 128. **Same for a hook that commits** (ship-mode): fall back to
  `git -c user.name=… commit`, or it silently captures nothing on an unconfigured machine.
- **`--print-output-on-failure`** on the `bats` call is what surfaces a flaky test's `$output` in CI.
- **Colour:** never assert via `cat -v` + `grep`; prefix-match the literal escape in bash
  (`esc=$'\033'; case "${out#*label}" in "$esc[0m$esc[32m"*)`). Neutralise the caller's env with
  `env -u NO_COLOR TERM=xterm`, or an exported `NO_COLOR` reddens a correct tree.
- **Never assert an exact countdown from `date +%s`** — `now + 42m` floors to `41m` the moment a
  second passes. Assert unit and presence (`↻[0-9]+m`), never the count.
- **A test that re-implements the logic proves nothing** — one re-grepped a gate's config and passed
  with that gate **deleted**. Pipe through the real script; mutate to confirm.
- **`cmd && { …; false; }` fails a bats test when `cmd` correctly returns non-zero.** Use `if`.
- **Retuning a gate can disarm its own guard-test** — a raised threshold put the fake bad input
  under the noise floor, so the guard silently stopped guarding (it failed only under load). Pin
  guards to the threshold they assert; re-run them after any retune.

## Frontmatter (commands / skills)
- **Quote any YAML value starting with `[`, `{`, `*`, `&`, `!`, `>`, `|`, `,` or `#`.** An unquoted
  `description: [target] …` opens a flow sequence: js-yaml throws, discards the **whole frontmatter**
  and logs at *debug*. Six commands were one `land` from shipping that.
- **`check.sh` line-greps frontmatter, so it can never see a parse failure** — an assertion on a
  *value* validates a string the host may never have loaded. Verify with a real YAML parser.
- **Extraction leaves three traps.** (1) A second COPY — grep the old shape. (2) Orphaned
  MUTATIONS — `mutations.txt` still aims at the old file and matches nothing; re-aim in the SAME
  commit (4x). (3) A MOVED failure mode — code hoisted into a helper runs in `$( )`, which
  *isolates* an abort, so deleting its input guard changed no output, only stderr; render
  assertions passed and `--mutate` caught the hole.
- **A reader returning EMPTY on malformed input fails open, silently.** `NR==1&&$0=="---"` returned
  nothing for a CRLF file and every check on that block passed vacuously. When a parser can say
  "nothing here", ask what callers do with nothing — usually: succeed.

## CI
- macOS is a **required** lane (bash 3.2). Test hooks for *silence* under missing tooling.
- **`gitleaks` + `shellcheck` SKIP locally when absent but RUN on CI** — a local PASS is not a CI
  PASS for those two. Linuxbrew's `shellcheck` **under-reports `SC2015`** (`A && B || C`) that CI
  flags — shipped red twice (3.16.0, 3.17.0). **Never write `test && test || cmd` as a guard.** The
  split cuts both ways on CODES: a trap-invoked function is `SC2329` locally, `SC2317` on CI —
  disable **both**.
