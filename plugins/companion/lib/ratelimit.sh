#!/usr/bin/env bash
# ACCOUNT rate-limit bars for the status line (R76) — extracted from bin/statusline.sh 2026-07-31
# when adding the pace marker pushed that file past the 300-line guard, which is exactly the
# signal the guard exists to give ("decompose only when this fires"). Sourced by, and only by,
# bin/statusline.sh. Reads $NOW (the run's single wall-clock read) and the $D/$B/$G/$Y/$R/$X
# colour vars from its caller — deliberately, so there is still ONE `date` and ONE colour policy
# per repaint. Pure render helpers: no writes, no network, no forks.

# ▰▱ ACCOUNT rate-limit bars (R76) — the one thing on this line that is about neither this repo
# nor this session. Claude Code hands the subscription's rolling-window usage straight to the
# status line in `.rate_limits`, so this costs **no API call, no network, no token** — it is the
# same stdin payload already parsed above. Two windows: **5h** (the one that stops you mid-session)
# and **7d** (the weekly burn). NOT a billing cycle — the plans meter on rolling windows, so a
# "this month" bar would be fiction.
# The field is ABSENT for API-key users and for Pro/Max until the first API response of a session,
# and each window can vanish independently — so every path renders NOTHING rather than a
# placeholder or a zero (best-effort, R7/R68: a status line never invents a number it wasn't given).
# Percentages arrive as floats ("23.5"); bash 3.2 has no float math, so truncate to int first.
# Seconds left in a window — shared by the countdown and the pace marker so the two can never
# disagree about whether a window is readable. Uses the run's single $NOW, not its own `date`
# (R81: ~1200 repaints/hour, spawn count is the budget). NOW==0 means the clock failed: refuse
# rather than treat the epoch as "now" and render a 56-year countdown.
rlsecs() {  # $1 resets_at (epoch|"") → seconds remaining · "" when unreadable
  local rst="${1%%.*}" left
  [ -n "$rst" ] && [ "$NOW" -gt 0 ] || return 0   # sc2015-ok: unreadable unless both hold
  # A non-numeric timestamp (an ISO string, anything) must never reach $(( )) — the arithmetic
  # would abort mid-line and take the whole status line with it (R68: best-effort, always renders).
  case "$rst" in *[!0-9]*) return 0;; esac
  left=$(( rst - NOW ))
  # Already elapsed → nothing, never a negative. A stale timestamp is the ordinary case in the
  # beat right after a window rolls forward.
  [ "$left" -gt 0 ] || return 0
  printf '%s' "$left"
}

# ▴/▾ PACE MARKER (R76, owner-asked 2026-07-31) — "am I on track to spend this window before it
# resets?" ▴ used ≥ elapsed-fraction · ▾ behind, and at this rate the window resets unspent.
# EXACT, not a forecast: the length is known from the field name and `resets_at` gives what's
# left, so this is arithmetic on data already in the payload — nothing sampled, persisted or
# estimated, which is what keeps it inside R76's "never invent a number it wasn't given".
# BIAS, and getting its DIRECTION right is the point: `p` is the FLOORED percent, so elapsed is
# compared as a CEILING. ▴ then requires floor(used) >= ceil(elapsed), which cannot hold unless
# used >= elapsed — so **▴ is always honest, and only ▾ can be conservative** (it may say "behind"
# when you are marginally ahead). That is the safe direction for someone trying to SPEND the
# window: being nudged to push when you were already fine costs nothing, being told "on pace"
# when you are behind costs the window. Flooring both sides instead inverts this — a devil's-
# advocate sweep of 6.2M probes found 31861 wrong-▴ and zero wrong-▾ before this ceiling.
# ONLY for a length-bearing window (7d) — 5h is passed none, because "on pace" is not a question
# anyone asks of it.
rlpace() {  # $1 resets_at (epoch|"") · $2 window length in seconds ("" = no marker) · $3 used %
  local left="" len="$2" el
  case "${len:-}" in ''|*[!0-9]*) return 0;; esac
  [ "$len" -gt 0 ] || return 0
  left="$(rlsecs "$1")"; [ -n "$left" ] || return 0
  # CEILING division — see the bias note above; this is what makes ▴ un-lyingly honest. A
  # resets_at further out than the window is long yields a negative el, and `p >= negative` is ▴,
  # which is already correct at t=0 — so no clamp is needed (one was here, and was provably dead).
  el=$(( ((len - left) * 100 + len - 1) / len ))
  if [ "$3" -ge "$el" ]; then printf '▴'; else printf '▾'; fi
}

rlleft() {  # $1 resets_at (epoch|"") → "↻2h" · "↻44m" · "" when the field is absent or unusable
  local left
  left="$(rlsecs "$1")"; [ -n "$left" ] || return 0
  # Integer division FLOORS, so 2h20m renders `↻2h`: it under-reports remaining time and never
  # over-reports, the safe direction for a number you might plan around.
  if   [ "$left" -ge 86400 ]; then printf '↻%dd' "$((left/86400))"
  elif [ "$left" -ge 3600  ]; then printf '↻%dh' "$((left/3600))"
  else                             printf '↻%dm' "$((left/60))"; fi
}

rlbar() {  # $1 used_pct (float|"") · $2 fallback label · $3 resets_at (epoch|"") · $4 window secs
  local p="${1%%.*}" lab="$2" rst="${3%%.*}" n i bar col s pace
  case "${p:-}" in ''|*[!0-9]*) return 0;; esac
  # A long all-digit string passes the guard above but overflows the shell's integer
  # compare (stderr spew every refresh). Length-clamp first, then value-clamp.
  [ "${#p}" -gt 3 ] && p=100
  [ "$p" -gt 100 ] && p=100
  # 5 cells, FLOOR — so only a genuinely exhausted window shows five filled. Rounding up would
  # paint 87% and 100% identically, which is the one reading that has to stay distinguishable.
  # Floor alone would hide 1-19% entirely, so anything above zero lights at least one cell.
  n=$(( p / 20 )); [ "$p" -gt 0 ] && [ "$n" -eq 0 ] && n=1
  # 0 < raw < 1 truncates to p=0: still in use, so light one cell rather than read as idle.
  case "$1" in 0.*[1-9]*) [ "$n" -eq 0 ] && n=1 ;; esac
  bar=""; i=0
  while [ "$i" -lt 5 ]; do
    if [ "$i" -lt "$n" ]; then bar="${bar}▰"; else bar="${bar}▱"; fi
    i=$((i+1))
  done
  col="$G"; [ "$p" -ge 60 ] && col="$Y"; [ "$p" -ge 85 ] && col="$R"
  # THE LABEL SLOT CARRIES THE COUNTDOWN, not the window name (owner-asked 2026-07-31, replacing
  # `5h`/`7d`): "when does this ease?" is the reading wanted at a glance, and it now costs the slot
  # the window name used to hold rather than extra width. `↻` is kept as the marker — a bare `2h`
  # sitting next to a percentage reads as "2 hours used", the opposite of what it says.
  #   · These are ROLLING windows (R76), so `resets_at` is when the window rolls forward, not a
  #     moment when the quota snaps back to full. `↻2h` is honest about the timestamp; it is not a
  #     promise of a full tank. The bar beside it is what says how much is left.
  # FALLBACK to the window name whenever the countdown is unavailable — API-key users, before the
  # session's first API response, an elapsed or malformed timestamp, EACH WINDOW INDEPENDENTLY.
  # An unlabelled bar is not a smaller version of a labelled one: either window can be absent on
  # its own (a first-class path here, R7/R68), so a lone anonymous bar could not be told from the
  # other window's — the exact field-shift class of defect R76 already had to fix once. The slot
  # is never empty and never anonymous.
  lab="$(rlleft "$rst")"; [ -n "$lab" ] || lab="$2"
  # Spaces around the bar (owner-asked 2026-07-31): label, bar and percent are three readings, and
  # `5h▰▱▱▱▱20%` runs them into one glyph blur. Two columns per rendered window. Deliberately
  # OUTSIDE the dim/colour escapes so neither gap carries an SGR of its own.
  # Rides the percent with NO gap — it qualifies that one reading, where a space would read as a
  # fourth field. Dim on purpose: it must not compete with the bar's green/yellow/red, which means
  # the OPPOSITE thing on the window it appears on (there, high usage is the goal).
  pace="$(rlpace "$rst" "${4:-}" "$p")"
  # Wrap ONLY when there is a marker — `${D}${X}` around an empty string is a null SGR pair
  # emitted on every repaint of every marker-less bar.
  [ -n "$pace" ] && pace="${D}${pace}${X}"
  s=" ${D}${lab}${X} ${col}${bar}${X} ${col}${B}${p}%${X}${pace}"
  printf '%s' "$s"
}
