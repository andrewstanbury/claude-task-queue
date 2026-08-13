#!/usr/bin/env bash
# tq-output — how `tq` TALKS TO THE READER: `usage()` (the help text) and `report()` (the grouped
# status report). Extracted from `tq` at its 300-line cap, and the seam is cohesion rather than line
# count: everything here renders, nothing here decides. Queue mechanics — id allocation, the
# atomic-rename writes, `stopfields()`'s startable selection — stay in `tq`, because that is state,
# and splitting state across files is how two owners of one concern start.
#
# SOURCED, not exec'd: both functions read `tq`'s own `$DIR`/`$STORE` and print to its stdout, so
# they must run in the same shell. MEASURED before extracting (R110's lesson — an unmeasured claim
# about this file is how it drifted to 382 lines unnoticed): sourcing a 60-line helper costs
# 0.634s vs 0.635s over 100 invocations, i.e. inside the noise floor, against a ~21ms `tq report`.
# The hot-path objection raised when this was parked turned out not to exist, and the number is
# what settled it.

usage() { cat >&2 <<'EOF'
tq — fallback task queue (native task tools gated off)
  tq add "<subject>" [more...] [--done "<acceptance>"] [--context "<files/flows>"]
                                 queue pending task(s) + delta line
  tq doing <id> ["<breadcrumb>"] mark in progress (opt. crash-resume note) + delta line
  tq note  <id> "<breadcrumb>"   update the in-progress breadcrumb
  tq done-when <id> "<accept>"   set/replace a task's done-when (survives compaction/clear)
  tq context <id> "<files>"      set/replace what's load-bearing for a task (survives compaction/clear)
  tq done  <id> [--seen "<obs>"] mark completed + print the FULL report (completion boundary).
                                 --seen records WHAT YOU EXERCISED AND IN WHICH RUNNING THING —
                                 the owner's layer, not yours ("tests pass" is refused). Optional.
  tq cancel <id>                 retract a mis-queued task (cancelled; kept for audit, uncounted)
  tq list                        terse one-line-each queue
  tq orphans [--orphans]         report state dirs no shipped code builds a path to
  tq report                      full grouped status report (also fires on done/import; other
                                 mutations print a one-line counts delta, R69)
  tq prune [--days N] [--dry-run] delete THIS repo's finished session stores older than N days
                                 (default 90); never a store with open/parked/blocked work
Lead a subject with ❓ (a parked decision) or ⏳ (owner-blocked) to defer it.
DEPENDENCIES live in the subject: write "after #<id>" and the task is NOT startable while #<id> is
still open. This is the ONLY syntax read (`stopfields`, which the Stop hook and `report` select
from) — "after 1/2", "depends on #3" and a `blockedBy` field are all silently ignored, and a task
whose dependency did not parse looks perfectly startable. Undocumented until 2026-08-12, when a
whole backlog read as startable while every item was in fact waiting on an unanswered park.
EOF
}

report() {
  local files=("$DIR"/*.json); [ -e "${files[0]}" ] || { printf '📋 Task queue — (empty)\n'; return 0; }
  # Design D (ultra-compact): glyph-count header, one line per ACTIVE task (no done-when),
  # completed shown as a count only. done-when still lives in the store and is re-surfaced on
  # cross-session resume (lib/companion.sh), so trimming it here costs no crash-resume context.
  jq -rs '
    def pk: ((.subject//"")|sub("^\\s+";"")|startswith("❓")); def bl: ((.subject//"")|sub("^\\s+";"")|startswith("⏳"));
    # ⛔ = a hypothesis the OWNER closed. It is not work and must never be offered, but it has to
    # survive compaction — the Apple/AWS incident happened because "confirmed twice" lived only in
    # a context window. A prefix-view over pending, exactly like ❓/⏳ (R42), so it rides the same
    # resume path that already re-injects open tasks.
    def rl: ((.subject//"")|sub("^\\s+";"")|startswith("⛔"));
    # strip a leading ❓/⏳ marker so the front glyph is not duplicated, then truncate
    def s72: ((.subject//"")|sub("^\\s*[❓⏳⛔]\\s*";"")|if length>72 then .[0:71]+"…" else . end);
    def ln($g): "  "+$g+" #"+(.id|tostring)+"  "+s72;
    # A park is REQUIRED to carry its own `rec:` so the review is a decision, not a rubber stamp —
    # and s72 truncated at 72 chars, which is exactly where `rec:` lives. The convention was being
    # stored and then hidden in the one place anyone reads it. Parks (and blocked items) now get a
    # continuation line with the recommendation, so "what should I do about this?" is answerable
    # from the queue alone. Costs nothing when nothing is parked, which is the common case.
    def rec: ((.subject//"") | if test("rec:") then "\n       └ rec: " + (split("rec:")[1]|sub("^\\s+";"")) else "" end);
    def lnr($g): ln($g) + rec;
    # A task can WAIT on another — most often on an unanswered park. Convention: the subject
    # names `after #N`. The next-pointer skips it while #N is still live, because pointing at
    # work that cannot start is how the drain offers the same blocked task repeatedly (it
    # offered one four times in a row before this existed). Such a task stays plain: it is not
    # parked and not a manual job, it is simply not next.
    # NOTE: no apostrophes anywhere in this jq program — a single quote ENDS it (LESSONS).
    # EVERY "after #N" in the subject, not just the first: a task naming two blockers must wait
    # for both. `capture` returns only the first match, so it started as soon as blocker one closed.
    def waits: [((.subject//"") | match("after #([0-9]+)";"g").captures[0].string)];
    (map(select(.status=="pending" or .status=="in_progress")) | map(.id|tostring)) as $live
    |(map(select(.status=="in_progress"))|sort_by(.id|tonumber)) as $ip
    |(map(select(.status=="pending" and (pk|not) and (bl|not) and (rl|not)))|sort_by(.id|tonumber)) as $op
    |(map(select(.status=="pending" and pk))|sort_by(.id|tonumber)) as $p
    |(map(select(.status=="pending" and bl))|sort_by(.id|tonumber)) as $b
    |(map(select(.status=="pending" and rl))|sort_by(.id|tonumber)) as $rlist
    |(map(select(.status=="completed"))|sort_by(.id|tonumber)) as $d
    |([ (if($ip|length)>0 then "▸\($ip|length)" else empty end),
        (if($op|length)>0 then "◻\($op|length)" else empty end),
        (if($p|length)>0 then "❓\($p|length)" else empty end),
        (if($b|length)>0 then "⏳\($b|length)" else empty end),
        (if($rlist|length)>0 then "⛔\($rlist|length)" else empty end),
        (if($d|length)>0 then "✔\($d|length)" else empty end)]|join(" ")) as $h
    |("📋"+(if $h=="" then " Task queue — (all clear)" else "  "+$h end)),
     ($ip[]|ln("▸")),($op[]|ln("◻")),($p[]|lnr("❓")),($b[]|lnr("⏳")),($rlist[]|ln("⛔")),
     (([$ip[], $op[]] | map(select(waits as $w | ($w | map(. as $x | select($live|index($x))) | length) == 0)) | .[0]) as $nx
      | if $nx then "  → next: #\($nx.id)"
       elif ([$ip[], $op[]]|length) > 0 then
         "  → nothing STARTABLE — " + (([$ip[], $op[]]|length)|tostring)
           + " task(s) wait on an earlier item. Answer that first."
       elif (($p|length)+($b|length))>0 then
         "  → nothing left to build — "
           + (if ($p|length)>0 then (($p|length)|tostring)+" decision(s) for you" else "" end)
           + (if ($p|length)>0 and ($b|length)>0 then " and " else "" end)
           + (if ($b|length)>0 then (($b|length)|tostring)+" manual job(s) only you can do" else "" end)
           + ". Run /companion:review — it asks the whole pile at once, then resumes autopilot if it was on."
       else empty end)
  ' "${files[@]}" 2>/dev/null || printf '📋 Task queue — (unreadable)\n'
}
