#!/usr/bin/env bash
# SEAT's inbox read. Prints your inbox AND records the version you have now seen
# (its mtime, in locks/seat-N.lock/inbox-seen). watch.sh baselines on that record, so a dispatch
# that lands between this read and your next watch can never be missed.
# Usage: inbox.sh seat-N [--quiet]     (--quiet records without printing)
. "$(dirname "$0")/common.sh"
case "${1:-}" in ''|-h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
W="$(seat_id "${1:?seat-N}")" || exit 1; F="$(inbox "$W")"
[ -f "$F" ] || die "no inbox for $W yet ($F)"
L="$(lockdir "$W")"; mkdir -p "$L" 2>/dev/null || true
m="$(mtime "$F")"
[ "${2:-}" = "--quiet" ] || cat "$F"
printf '%s\n' "$m" > "$L/inbox-seen" 2>/dev/null || true
