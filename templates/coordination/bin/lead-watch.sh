#!/usr/bin/env bash
# LEAD's monitor. Run as a BACKGROUND task; its exit re-invokes the lead.
#   exit 0  a seat outbox or the registry changed since the lead last woke -> read it, review/dispatch
#   exit 3  STALL: nothing written in outboxes or TERRITORIES for STALL_MIN minutes -> heartbeat-check the seats
#   exit 4  timeout, nothing happened this cycle -> re-arm
# Usage: bash coordination/bin/lead-watch.sh [timeout_seconds] [stall_minutes]
. "$(dirname "$0")/common.sh"
case "${1:-}" in -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
TIMEOUT="${1:-$LEAD_WATCH_TIMEOUT}"; STALL="${2:-$STALL_MIN}"
snapshot() { outbox_snapshot; }
recent() { # any file written within STALL minutes in outboxes or territories?
  local p; territory_list "$TERRITORIES" | while IFS= read -r p; do [ -n "$p" ] && inside_root "$p" && [ -e "$ROOT/$p" ] && find "$ROOT/$p" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -mmin -"$STALL" 2>/dev/null | head -1; done
  find "$COORD/outbox" -type f -mmin -"$STALL" 2>/dev/null | head -1
}
# Baseline = the snapshot the lead last woke on (persisted at exit 0), so a change that landed while the lead
# was reading and acting is still detected; a fresh lead with no record baselines on now.
S0="$(outbox_seen_baseline)"
[ "$(snapshot)" != "$S0" ] && { outbox_mark_seen; exit 0; }
# If everything is already idle past the stall window when we arm, a stall alarm would trip
# instantly forever — run as a pure change-watcher until timeout instead.
STALL_ENABLED=1; [ -z "$(recent | head -1)" ] && STALL_ENABLED=0
any_open_work || STALL_ENABLED=0   # nothing open below: a finished or dismissed team cannot stall
ELAPSED=0
while [ "$ELAPSED" -lt "$TIMEOUT" ]; do
  sleep 20; ELAPSED=$((ELAPSED + 20))
  [ "$(snapshot)" != "$S0" ] && { outbox_mark_seen; exit 0; }
  if [ "$STALL_ENABLED" = 1 ] && [ -z "$(recent | head -1)" ]; then outbox_mark_seen; exit 3; fi
done
outbox_mark_seen   # nothing new: what is on disk now is what the lead knows
exit 4
