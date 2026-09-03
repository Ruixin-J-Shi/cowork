#!/usr/bin/env bash
# LEAD ONLY. Appends an entry to a seat's inbox (the only writer of inboxes is the lead).
#
# Usage:
#   dispatch.sh seat-N "T7 — <title>" -m "<body>"            body inline
#   dispatch.sh seat-N "T7 — <title>" - <<'EOF' ... EOF       body from stdin (explicit "-"; never blocks otherwise)
#   dispatch.sh seat-N "Ruling — <topic>" -f body.md          body from a file; any heading works, task headings start with T<n> —
#   dispatch.sh --all "⚠️ ALL-HANDS — <topic>" -m "..."          same entry into every seat's inbox
#   dispatch.sh seat-N --status ACTIVE|PAUSED|DISMISSED       rewrites the STATUS line (the one in-place edit)
#   dispatch.sh seat-N --next-id                              prints the next unused T<n> for that inbox
# Every append is stamped "(<ts>, lead)". Appending changes the inbox mtime, which is what wakes the seat.
# Bodies are appended raw: never put "## " headings inside a body (they become top-level entries); use "### " or bold.
. "$(dirname "$0")/common.sh"
case "${1:-}" in ''|-h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac

append_entry() { # file heading body
  { printf '\n## %s (%s, lead)\n' "$2" "$(ts)"; [ -n "$3" ] && printf '%s\n' "$3"; } >> "$1"
}
read_body() { # -m text | -f file | - (stdin) | nothing
  case "${1:-}" in -m) printf '%s' "${2:-}";; -f) cat "${2:?file}";; -) cat;; '') :;; *) die "body must be given as -m \"text\", -f file, or - (stdin)";; esac; }

if [ "$1" = "--all" ]; then
  shift; HEADING="${1:?heading}"; shift
  BODY="$(read_body "$@")" || exit 1
  n=1; while [ "$n" -le "$SEATS" ]; do
    w="seat-$n"; [ -f "$(inbox "$w")" ] || printf '# Inbox — %s (written by LEAD only)\n\nSTATUS: ACTIVE\n' "$w" > "$(inbox "$w")"
    append_entry "$(inbox "$w")" "$HEADING" "$BODY"; n=$((n+1)); done
  echo "broadcast to $SEATS inboxes: $HEADING"; exit 0
fi

W="$(seat_id "$1")" || exit 1; shift
F="$(inbox "$W")"
[ -f "$F" ] || printf '# Inbox — %s (written by LEAD only)\n\nSTATUS: ACTIVE\n' "$W" > "$F"

case "${1:-}" in
  --status)
    S="${2:?ACTIVE|PAUSED|DISMISSED}"
    case "$S" in ACTIVE|PAUSED|DISMISSED) ;; *) die "STATUS must be ACTIVE, PAUSED or DISMISSED";; esac
    if [ "$(inbox_status "$W")" = "$S" ]; then echo "$W STATUS: $S (unchanged — not rewritten, seat not woken)"; exit 0; fi
    tmp="$F.tmp.$$"
    if grep -qE '^STATUS:' "$F"; then awk -v s="$S" '/^STATUS:/ && !done {print "STATUS: " s; done=1; next} {print}' "$F" > "$tmp"
    else { head -1 "$F"; printf '\nSTATUS: %s\n' "$S"; tail -n +2 "$F"; } > "$tmp"; fi
    mv "$tmp" "$F"
    # The STATUS line is the one in-place edit in an append-only file — invisible to anyone reading the tail.
    # Append a dated entry too, so the change is visible both ways.
    printf '\n## STATUS → %s (%s, lead)\n' "$S" "$(ts)" >> "$F"
    echo "$W STATUS: $S"; exit 0;;
  --next-id)
    max="$(inbox_task_ids "$W" | sed -E 's/^T([0-9]+).*/\1/' | sort -n | tail -1)"; echo "T$(( ${max:-0} + 1 ))"; exit 0;;
esac

HEADING="${1:?heading}"; shift
BODY="$(read_body "$@")" || exit 1
append_entry "$F" "$HEADING" "$BODY"
echo "$W ← $HEADING"
