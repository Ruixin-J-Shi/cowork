#!/usr/bin/env bash
# Shared helpers for coordination/bin/*.sh — sourced by every script, never run directly.
# Resolves COORD (this coordination/ dir) and ROOT (the project it lives in), loads cowork.conf.
# Portable across macOS (BSD stat, bash 3.2) and Linux (GNU stat).
set -u
_common_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
COORD="$(cd "$_common_dir/.." && pwd)"

# Defaults; cowork.conf overrides any of them.
PROJECT_ROOT_REL=""       # empty = derive the project root from the tree; set only if coordination/ lives somewhere unusual
PROJECT_NAME=""
SEATS=3
HEARTBEAT_MIN=30          # a working seat writes a line at least this often
DEAD_MIN=90               # outbox AND territories silent this long with open work = dead by evidence
STALL_MIN=45              # lead-watch stall alarm
WATCH_TIMEOUT=600         # seat watch fallback (seconds)
LEAD_WATCH_TIMEOUT=3000 # lead watch fallback (seconds)
TERRITORIES=""            # space-separated paths relative to ROOT where seats write
NTFY_TOPIC=""             # optional phone notifications (ntfy.sh topic) for seat sessions
NTFY_TOPIC_LEAD=""      # optional dedicated topic for the lead session
# shellcheck disable=SC1091
[ -f "$COORD/cowork.conf" ] && . "$COORD/cowork.conf"
# ---- Tree position. A coordination dir at <parent>/teams/seat-N is the team run by slot seat-N of <parent>.
# Any depth: <top>/teams/seat-2/teams/seat-1/… The node's session is seat-N above and the lead below.
_is_team_dir() { local b; b="$(basename "$1")"; case "${b#seat-}" in ''|*[!0-9]*) return 1;; esac; [ "$b" != "${b#seat-}" ] && [ "$(basename "$(dirname "$1")")" = teams ]; }
# the team dirs directly below this one, one path per line, strictly named
teams_below() { local t; [ -d "$COORD/teams" ] || return 0; for t in "$COORD"/teams/seat-*/; do t="${t%/}"; [ -d "$t/bin" ] && _is_team_dir "$t" && echo "$t"; done; return 0; }
UP_COORD=""; UP_SLOT=""
if _is_team_dir "$COORD"; then UP_COORD="$(cd "$COORD/../.." && pwd)"; UP_SLOT="$(basename "$COORD")"; fi
TOP="$COORD"; while _is_team_dir "$TOP"; do TOP="$(cd "$TOP/../.." && pwd)"; done
if [ -n "$PROJECT_ROOT_REL" ]; then ROOT="$(cd "$COORD/$PROJECT_ROOT_REL" && pwd)" || { echo "error: PROJECT_ROOT_REL=$PROJECT_ROOT_REL does not resolve from $COORD" >&2; exit 1; }
else ROOT="$(dirname "$TOP")"; fi
ROOT_P="$(cd "$ROOT" && pwd -P)"
C_REL="${COORD#$ROOT/}"; [ "$C_REL" = "$COORD" ] && C_REL="$COORD"   # path of this dir relative to ROOT (absolute if outside)
# "root", "seat-2", "seat-2/seat-1": the node's path in the tree
node_path() { local p="" d="$COORD"; while _is_team_dir "$d"; do p="$(basename "$d")${p:+/$p}"; d="$(cd "$d/../.." && pwd)"; done; echo "${p:-root}"; }
[ -n "$PROJECT_NAME" ] || PROJECT_NAME="$(basename "$ROOT")"
up_inbox()  { echo "$UP_COORD/inbox/$UP_SLOT.md"; }
up_outbox() { echo "$UP_COORD/outbox/$UP_SLOT.md"; }

ts() { date '+%Y-%m-%d %H:%M'; }
now_s() { date +%s; }
mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }
# stat flavour, decided once: BSD (macOS) or GNU (Linux)
if stat -f %m / >/dev/null 2>&1; then STAT_MTIME="-f %m"; else STAT_MTIME="-c %Y"; fi
# newest mtime (epoch) of any file under a path, excluding VCS/node_modules noise; 0 if none
newest_mtime() {
  [ -e "$1" ] || { echo 0; return; }
  [ -f "$1" ] && { mtime "$1"; return; }
  # shellcheck disable=SC2086
  local m; m="$(find "$1" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -not -name .gitkeep -not -name .DS_Store -print0 2>/dev/null | xargs -0 stat $STAT_MTIME 2>/dev/null | sort -n | tail -1)"
  echo "${m:-0}"
}
newest_age_min() { local m; m="$(newest_mtime "$1")"; if [ "$m" = 0 ]; then echo "-"; else echo $(( ( $(now_s) - m ) / 60 )); fi; }
# minutes since the file was last written; "-" if it does not exist
age_min() { local m; m="$(mtime "$1")"; if [ "$m" = 0 ]; then echo "-"; else echo $(( ( $(now_s) - m ) / 60 )); fi; }
fmt_age() { # minutes -> 3m / 2h05 / 3d
  local m="$1"; [ "$m" = "-" ] && { echo "-"; return; }
  if [ "$m" -lt 60 ]; then echo "${m}m"
  elif [ "$m" -lt 1440 ]; then printf '%dh%02d\n' $((m/60)) $((m%60))
  else printf '%dd%02dh\n' $((m/1440)) $(((m%1440)/60)); fi
}
die() { echo "error: $*" >&2; exit 1; }

# Normalise "2" or "seat-2" -> "seat-2"; validate 1..SEATS.
seat_id() {
  local w="$1"; case "$w" in seat-*) ;; *) w="seat-$w";; esac
  local n="${w#seat-}"
  case "$n" in ''|*[!0-9]*) die "bad seat id: $1";; esac
  n=$((10#$n))
  [ "$n" -ge 1 ] && [ "$n" -le "$SEATS" ] || die "seat id out of range 1..$SEATS: $1"
  echo "seat-$n"
}
inbox()  { echo "$COORD/inbox/$1.md"; }
outbox() { echo "$COORD/outbox/$1.md"; }
lockdir(){ echo "$COORD/locks/$1.lock"; }

# Territory lists are colon-separated (PATH-style; a path may then contain spaces); whitespace also separates
# when no colon is present. One entry per output line.
territory_list() { local s="${1:-}"; case "$s" in '') ;; *:*) printf '%s\n' "$s" | tr ':' '\n';; *) printf '%s\n' $s;; esac; }
# A territory must resolve inside the project root; anything else is ignored by liveness and flagged by doctor.
inside_root() { local rp; [ -e "$ROOT/$1" ] || return 0; rp="$(cd "$ROOT/$1" 2>/dev/null && pwd -P)" || return 1; case "$rp" in "$ROOT_P"|"$ROOT_P"/*) return 0;; *) return 1;; esac; }

# Age in minutes of the newest file across TERRITORIES (+ the outbox dir); "-" if nothing found.
territory_age_min() { # [--no-outbox]  (liveness judges territories only; the stall alarm includes the outbox dir)
  local newest=0 p m
  while IFS= read -r p; do
    [ -n "$p" ] || continue; inside_root "$p" || continue
    m="$(newest_mtime "$ROOT/$p")"; [ "$m" -gt "$newest" ] && newest="$m"
  done <<EOF
$(territory_list "$TERRITORIES")
EOF
  if [ "${1:-}" != "--no-outbox" ]; then m="$(newest_mtime "$COORD/outbox")"; [ "$m" -gt "$newest" ] && newest="$m"; fi
  if [ "$newest" = 0 ]; then echo "-"; else echo $(( ( $(now_s) - newest ) / 60 )); fi
}

# Per-slot territory (cowork.conf: TERRITORY_1="src", TERRITORY_2="tests" …); falls back to the global TERRITORIES.
slot_territory() { local n="${1#seat-}"; eval "printf '%s' \"\${TERRITORY_$n:-}\""; }
slot_territory_age_min() {
  local t newest=0 p m; t="$(slot_territory "$1")"
  [ -n "$t" ] || { territory_age_min --no-outbox; return; }
  while IFS= read -r p; do
    [ -n "$p" ] || continue; inside_root "$p" || continue
    m="$(newest_mtime "$ROOT/$p")"; [ "$m" -gt "$newest" ] && newest="$m"
  done <<EOF
$(territory_list "$t")
EOF
  if [ "$newest" = 0 ]; then echo "-"; else echo $(( ( $(now_s) - newest ) / 60 )); fi
}

# Optional per-slot display labels (cowork.conf: LABEL_1="backend-lead") — shown by status.sh next to the id.
slot_label() { local n="${1#seat-}"; eval "printf '%s' \"\${LABEL_$n:-}\""; }

# The lead: one lock, one append-only log (heartbeats, boot, decisions). Inbox writes count as lead activity too.
lead_log()  { echo "$COORD/lead-log.md"; }
lead_lock() { echo "$COORD/locks/lead.lock"; }
lead_lock_state() { local L; L="$(lead_lock)"; [ -d "$L" ] || { echo free; return; }; local n; n="$(ls -d "$L"/takeover-*.lock 2>/dev/null | wc -l | tr -d ' ')"; if [ "$n" = 0 ]; then echo held; else echo "held(+$n)"; fi; }
# epoch of the lead's last write: its log, any inbox below, and — for a node — its outbox above (work done as a
# seat is still this lead being alive; a node blocked on a review above must not accrue death evidence below)
lead_last_write() {
  local newest=0 m f
  m="$(mtime "$(lead_log)")"; [ "$m" -gt "$newest" ] && newest="$m"
  for f in "$COORD"/inbox/seat-*.md; do [ -f "$f" ] || continue; m="$(mtime "$f")"; [ "$m" -gt "$newest" ] && newest="$m"; done
  if [ -n "$UP_COORD" ] && [ -f "$(up_outbox)" ]; then m="$(mtime "$(up_outbox)")"; [ "$m" -gt "$newest" ] && newest="$m"; fi
  echo "$newest"
}
# minutes since the lead last wrote anything; "-" if never
lead_activity_age_min() { local m; m="$(lead_last_write)"; if [ "$m" = 0 ]; then echo "-"; else echo $(( ( $(now_s) - m ) / 60 )); fi; }
# is any seat waiting on the lead (an outbox written after the lead's last write)?
work_waiting() {
  local mi f m; mi="$(lead_last_write)"
  for f in "$COORD"/outbox/seat-*.md; do [ -f "$f" ] || continue; m="$(mtime "$f")"; [ "$m" -gt "$mi" ] && return 0; done
  return 1
}
# does any slot still have open work and not DISMISSED? (a finished team cannot stall)
any_open_work() { local n=1 w; while [ "$n" -le "$SEATS" ]; do w="seat-$n"; [ "$(inbox_status "$w")" != DISMISSED ] && [ "$(open_tasks "$w")" != "-" ] && return 0; n=$((n + 1)); done; return 1; }
lead_liveness() {
  local a; [ "$(lead_lock_state)" = free ] && { echo unclaimed; return; }
  a="$(lead_activity_age_min)"; [ "$a" = "-" ] && { echo "claimed, nothing written yet"; return; }
  if [ "$a" -le "$HEARTBEAT_MIN" ]; then echo ALIVE; return; fi
  if [ "$a" -lt "$DEAD_MIN" ]; then echo "QUIET ${a}m"; return; fi
  if work_waiting; then echo "DEAD? silent ${a}m with work waiting — standby may take over"; else echo "idle ${a}m (nothing waiting)"; fi
}

# Below-side change detection with a persisted baseline: what the lead last woke up on. A change that lands between
# the lead's read and its next watch arm is still newer than the persisted snapshot, so it cannot be missed.
outbox_snapshot() { local f; for f in "$COORD"/outbox/seat-*.md "$COORD/registry.md"; do [ -f "$f" ] && printf '%s %s\n' "$(mtime "$f")" "$f"; done; return 0; }
outbox_seen_file() { echo "$COORD/locks/lead.lock/outbox-seen"; }
outbox_seen_baseline() { if [ -f "$(outbox_seen_file)" ]; then cat "$(outbox_seen_file)"; else outbox_snapshot; fi; }
outbox_mark_seen() { [ -d "$COORD/locks/lead.lock" ] && outbox_snapshot > "$(outbox_seen_file)" 2>/dev/null; return 0; }

# Task bookkeeping. Inbox task headings: "## T<n> — <title>". Outbox: "## T<n> — IN_PROGRESS|DONE|BLOCKED|RESUMED <ts>".
# A task's state is its LAST outbox heading; only DONE closes it (a BLOCKED task stays open: the seat re-checks
# the blocker at every wake-up and keeps the heartbeat duty).
inbox_task_ids()  { grep -E '^## T[0-9]+[a-z]? — ' "$(inbox "$1")" 2>/dev/null | sed -E 's/^## (T[0-9]+[a-z]?) — .*/\1/' | awk '!seen[$0]++'; }
task_state() { # seat id -> IN_PROGRESS|DONE|BLOCKED|RESUMED|"" (last state heading for that id)
  grep -E "^## $2 — (IN_PROGRESS|DONE|BLOCKED|RESUMED)" "$(outbox "$1")" 2>/dev/null | tail -1 | sed -E 's/^## [^ ]+ — ([A-Z_]+).*/\1/'; }
# Open tasks for a seat, annotated: T3(in progress) T4(unacked) T5(blocked)
open_tasks() {
  local w="$1" id st out=""
  for id in $(inbox_task_ids "$w"); do
    st="$(task_state "$w" "$id")"
    case "$st" in
      DONE) ;;
      IN_PROGRESS|RESUMED) out="$out $id(in progress)";;
      BLOCKED) out="$out $id(blocked)";;
      *) out="$out $id(unacked)";;
    esac
  done
  out="${out# }"; echo "${out:--}"
}
inbox_status() { grep -E '^STATUS:' "$(inbox "$1")" 2>/dev/null | head -1 | sed -E 's/^STATUS:[[:space:]]*//'; }
lock_state() { # free | held | held(+N takeovers)
  local L; L="$(lockdir "$1")"
  [ -d "$L" ] || { echo free; return; }
  local n; n="$(ls -d "$L"/takeover-*.lock 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" = 0 ]; then echo held; else echo "held(+$n)"; fi
}
# Liveness verdict for a claimed slot.
liveness() {
  local w="$1" oa ta open
  oa="$(age_min "$(outbox "$w")")"; open="$(open_tasks "$w")"; [ "$open" = "-" ] && open=""
  [ "$(lock_state "$w")" = free ] && { echo unclaimed; return; }
  [ "$(inbox_status "$w")" = DISMISSED ] && { echo "DISMISSED (outbox ${oa}m)"; return; }
  [ "$oa" = "-" ] && { echo "no outbox yet"; return; }
  if [ "$oa" -le "$HEARTBEAT_MIN" ]; then [ -n "$open" ] && echo ALIVE || echo "ALIVE, idle"; return; fi
  if [ -z "$open" ]; then echo "idle ${oa}m (no open tasks)"; return; fi
  if [ "$oa" -lt "$DEAD_MIN" ]; then echo "QUIET ${oa}m — past heartbeat window, nudge"; return; fi
  ta="$(slot_territory_age_min "$w")"
  if [ "$ta" != "-" ] && [ "$ta" -le "$HEARTBEAT_MIN" ]; then echo "SILENT outbox ${oa}m but territory active ${ta}m — nudge"; else echo "DEAD? outbox ${oa}m, territory ${ta}m, open work — takeover candidate"; fi
}
