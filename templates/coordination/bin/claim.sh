#!/usr/bin/env bash
# Seat slot claim. `mkdir` is atomic, so two sessions can never share a slot.
#
# Usage:
#   claim.sh [--desc "one-line self description"]
#       Tries seat-1, seat-2, ... in order. Prints the claimed id on stdout (exit 0).
#       Exit 2 if every slot is held, with per-slot evidence so you can judge a takeover.
#   claim.sh --slot seat-N [--desc "..."]
#       Claim exactly that slot (a node's slot above is fixed by its team dir). Exit 2 with evidence if held.
#   claim.sh --takeover seat-N --reason "<evidence>" [--force] [--desc "..."]
#       Dead-session recovery: nested atomic mkdir inside the stale lock — first taker wins.
#       Refuses unless the slot is dead by evidence — outbox stale >= DEAD_MIN AND its territory silent AND an open
#       task (a STATUS: DISMISSED slot needs only the stale outbox): the three facts status.sh reports. --force overrides.
#       After a takeover you MUST audit the predecessor's on-disk work before continuing it.
. "$(dirname "$0")/common.sh"
DESC="Claude Code seat session"; TAKEOVER=""; REASON=""; FORCE=""; SLOT=""
while [ $# -gt 0 ]; do case "$1" in
  --desc) DESC="$2"; shift 2;;
  --slot) SLOT="$(seat_id "$2")" || exit 1; shift 2;;
  --takeover) TAKEOVER="$(seat_id "$2")" || exit 1; shift 2;;
  --reason) REASON="$2"; shift 2;;
  --force) FORCE=1; shift;;
  -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;;
  *) die "unknown arg: $1";; esac; done
mkdir -p "$COORD/locks" "$COORD/outbox"
[ -f "$COORD/registry.md" ] || printf '# Seat registry\n\nLock directories in coordination/locks/ are the source of truth; this file is the human-readable history.\n\n' > "$COORD/registry.md"

ensure_outbox() { [ -f "$(outbox "$1")" ] || printf '# Outbox — %s (written by %s only; append-only)\n' "$1" "$1" > "$(outbox "$1")"; }

if [ -n "$TAKEOVER" ]; then
  [ -n "$REASON" ] || die "--takeover needs --reason citing the evidence (last outbox write, unfinished task, territory silence)"
  L="$(lockdir "$TAKEOVER")"
  [ -d "$L" ] || die "$TAKEOVER is not locked — claim it normally"
  oa="$(age_min "$(outbox "$TAKEOVER")")"
  if [ -z "$FORCE" ]; then   # the same three facts liveness() reports: stale outbox, silent territory, open work
    [ "$oa" = "-" ] && die "$TAKEOVER has no outbox on disk — no evidence it is dead (it may be initialising). Re-check status.sh, or --force with stronger evidence."
    [ "$oa" -lt "$DEAD_MIN" ] && die "$TAKEOVER wrote its outbox ${oa}m ago (< DEAD_MIN=$DEAD_MIN). It may be alive. Re-check status.sh, or --force if you have stronger evidence."
    if [ "$(inbox_status "$TAKEOVER")" != DISMISSED ]; then
      ta="$(slot_territory_age_min "$TAKEOVER")"; open="$(open_tasks "$TAKEOVER")"
      [ "$ta" != "-" ] && [ "$ta" -le "$HEARTBEAT_MIN" ] && die "$TAKEOVER's territory was written ${ta}m ago — heads-down, not dead (status.sh says nudge). Re-check, or --force with stronger evidence."
      [ "$open" = "-" ] && die "$TAKEOVER has no open task — idle, not dead by evidence (outbox ${oa}m). Ask the lead to dispatch to it or dismiss it, or --force with stronger evidence."
    fi
  fi
  gen="$(ls -d "$L"/takeover-*.lock 2>/dev/null | wc -l | tr -d ' ')"
  T="$L/takeover-$((gen + 1)).lock"
  [ -n "${COWORK_TEST_SLEEP:-}" ] && sleep "$COWORK_TEST_SLEEP"   # test hook: widen the race window
  if mkdir "$T" 2>/dev/null; then
    printf '%s takeover %s — %s\n' "$(ts)" "$DESC" "$REASON" > "$T/claim"
    printf -- '- %s TAKEN OVER at %s by a new session (%s). Evidence: %s. Successor audits the predecessor'"'"'s unreported on-disk work against the open task before continuing.\n' \
      "$TAKEOVER" "$(ts)" "$DESC" "$REASON" >> "$COORD/registry.md"
    ensure_outbox "$TAKEOVER"
    # Announce in the outbox immediately: the slot is now ALIVE to everyone else, so a second taker is refused.
    printf '\n## Takeover %s — slot taken over by a new session (%s)\nEvidence: %s. Auditing the predecessor'"'"'s on-disk work before resuming any task.\n' "$(ts)" "$DESC" "$REASON" >> "$(outbox "$TAKEOVER")"
    echo "$TAKEOVER"; exit 0
  fi
  die "takeover race lost for $TAKEOVER — another session claimed it first; re-run status.sh"
fi

n=1
while [ "$n" -le "$SEATS" ]; do
  w="seat-$n"
  if [ -n "$SLOT" ] && [ "$w" != "$SLOT" ]; then n=$((n + 1)); continue; fi
  if mkdir "$(lockdir "$w")" 2>/dev/null; then
    printf '%s claimed %s\n' "$(ts)" "$DESC" > "$(lockdir "$w")/claim"
    printf -- '- %s claimed at %s, %s\n' "$w" "$(ts)" "$DESC" >> "$COORD/registry.md"
    ensure_outbox "$w"
    printf '\n## Claimed %s — %s\n' "$(ts)" "$DESC" >> "$(outbox "$w")"   # the slot reads ALIVE from its first second
    echo "$w"; exit 0
  fi
  n=$((n + 1))
done

if [ -n "$SLOT" ]; then echo "slot $SLOT is held. Evidence (decide takeover per PROTOCOL.md):" >&2; else echo "all $SEATS slots are held. Evidence per slot (decide takeover per PROTOCOL.md):" >&2; fi
n=1
while [ "$n" -le "$SEATS" ]; do
  w="seat-$n"
  if [ -n "$SLOT" ] && [ "$w" != "$SLOT" ]; then n=$((n + 1)); continue; fi
  echo "  $w: lock $(lock_state "$w") · outbox written $(fmt_age "$(age_min "$(outbox "$w")")") ago · its territory written $(fmt_age "$(slot_territory_age_min "$w")") ago · open: $(open_tasks "$w") · verdict: $(liveness "$w")" >&2
  n=$((n + 1))
done
echo "dead by evidence = outbox >= DEAD_MIN (${DEAD_MIN}m) AND its territory silent AND an open task (acked or not)." >&2
echo "takeover: $0 --takeover seat-N --reason \"<the evidence above>\"" >&2
exit 2
