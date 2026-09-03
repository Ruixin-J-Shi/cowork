#!/usr/bin/env bash
# SEAT ONLY. Appends to your own outbox — the file is append-only and this script can only append.
#
# Usage:
#   report.sh seat-N T3 IN_PROGRESS|DONE|BLOCKED|RESUMED  -m "<body>" | -f file | - <<'EOF'...EOF
#   report.sh seat-N HEARTBEAT [-m "one line of progress"]               "## Heartbeat <ts> — alive"
#   report.sh seat-N INCIDENT -m "<what slipped, blast radius, audit>"    mandatory self-report line
#   report.sh seat-N ACK "<what>" [-m "one line"]                        acknowledge an all-hands, ruling or review: "## ACK <what> <ts>"
#   report.sh seat-N NOTE "<heading>" [-m "<body>" | -f file | -]         anything else (answers to a sibling, interface notes)
# Body sources are explicit; with none given the entry is heading-only (stdin is never read implicitly).
. "$(dirname "$0")/common.sh"
case "${1:-}" in -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
[ $# -ge 2 ] || { awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 1; }
W="$(seat_id "$1")" || exit 1; shift
F="$(outbox "$W")"
[ -f "$F" ] || printf '# Outbox — %s (written by %s only; append-only)\n' "$W" "$W" > "$F"

body_from() { case "${1:-}" in -m) printf '%s' "${2:-}";; -f) cat "${2:?file}";; -) cat;; '') :;; *) die "body must be -m \"text\", -f file, or - (stdin)";; esac; }

case "$1" in
  HEARTBEAT) shift; B="$(body_from "$@")" || exit 1; { printf '\n## Heartbeat %s — alive\n' "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$F"; echo "$W heartbeat";;
  INCIDENT)  shift; B="$(body_from "$@")" || exit 1; [ -n "$B" ] || die "INCIDENT needs a body: what ran, blast radius checked (not assumed), audit result"
             { printf '\n## ⚠️ INCIDENT %s — self-report\n%s\n' "$(ts)" "$B"; } >> "$F"; echo "$W incident recorded — now STOP and audit before resuming";;
  ACK)       H="${2:?what you acknowledge}"; shift 2; B="$(body_from "$@")" || exit 1; { printf '\n## ACK %s %s\n' "$H" "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$F"; echo "$W ack: $H";;
  NOTE)      H="${2:?heading}"; shift 2; B="$(body_from "$@")" || exit 1; { printf '\n## %s (%s)\n' "$H" "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$F"; echo "$W note: $H";;
  T[0-9]*)   ID="$1"; ST="${2:?IN_PROGRESS|DONE|BLOCKED|RESUMED}"; shift 2
             case "$ST" in IN_PROGRESS|DONE|BLOCKED|RESUMED) ;; *) die "state must be IN_PROGRESS, DONE, BLOCKED or RESUMED";; esac
             B="$(body_from "$@")" || exit 1
             if [ "$ST" = DONE ] && [ -z "$B" ]; then die "DONE needs a report: what you did, every file touched, how you verified, what the lead must know"; fi
             if [ "$ST" = BLOCKED ] && [ -z "$B" ]; then die "BLOCKED needs the reason (name the file or rule that blocks you)"; fi
             { printf '\n## %s — %s %s\n' "$ID" "$ST" "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$F"; echo "$W $ID $ST";;
  *) die "unknown kind: $1";;
esac
