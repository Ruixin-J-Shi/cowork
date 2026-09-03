#!/usr/bin/env bash
# SEAT's wake-up. Blocks until your inbox changes, then exits 0. Exits 4 on timeout (same code as lead-watch.sh).
# Baseline = the inbox version you last read via inbox.sh (locks/seat-N.lock/inbox-seen); if the inbox
# is already newer than that, exits 0 immediately — a dispatch that landed while you were working is
# never missed. Without a record it baselines on the current mtime.
# On EITHER exit code go back to reading your inbox (exit 4 means "nothing in this window", not "nothing").
# Usage: bash coordination/bin/watch.sh seat-N [timeout_seconds]     (run as a background task)
. "$(dirname "$0")/common.sh"
case "${1:-}" in -h|--help|'') awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
W="$(seat_id "$1")" || exit 1; T="${2:-$WATCH_TIMEOUT}"
F="$(inbox "$W")"; SEEN="$(lockdir "$W")/inbox-seen"
if [ -f "$SEEN" ]; then M0="$(tr -d '[:space:]' < "$SEEN")"; else M0="$(mtime "$F")"; fi
[ "$(mtime "$F")" != "$M0" ] && exit 0
ELAPSED=0
while [ "$ELAPSED" -lt "$T" ]; do
  sleep 15; ELAPSED=$((ELAPSED + 15))
  [ "$(mtime "$F")" != "$M0" ] && exit 0
done
exit 4
