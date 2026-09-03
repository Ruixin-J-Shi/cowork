#!/usr/bin/env bash
# The LEAD's identity, log and failover. One lead per coordination dir, held by locks/lead.lock.
#
# Usage:
#   lead.sh claim [--desc "…"]              claim the lead lock (exit 2 with evidence if held); boot line in lead-log.md + registry
#   lead.sh takeover --reason "…" [--force] a STANDBY takes over a lead that is dead by evidence (nested atomic mkdir; refused
#                                             while the lead wrote anything < DEAD_MIN ago unless --force); notes every inbox
#   lead.sh heartbeat [-m "…"]              append "## Heartbeat <ts>" to lead-log.md — do this at every wake-up
#   lead.sh note "<heading>" [-m|-f|-]      append a decision/state note to lead-log.md (the lead's own append-only log)
#   lead.sh standby [timeout_s] [poll_s]    block until the lead is DEAD? by evidence → exit 0; exit 4 on timeout (run as a
#                                             background task from the standby session)
#   lead.sh status                          one line: lock, activity age, verdict
. "$(dirname "$0")/common.sh"
case "${1:-}" in ''|-h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
CMD="$1"; shift
mkdir -p "$COORD/locks" "$COORD/inbox" "$COORD/outbox"
[ -f "$COORD/registry.md" ] || printf '# Seat registry\n\n' > "$COORD/registry.md"
LOG="$(lead_log)"; L="$(lead_lock)"
ensure_log() { [ -f "$LOG" ] || printf '# Lead log — %s (written by the LEAD only; append-only: boot, heartbeats, decisions)\n' "$PROJECT_NAME" > "$LOG"; }
body_from() { case "${1:-}" in -m) printf '%s' "${2:-}";; -f) cat "${2:?file}";; -) cat;; '') :;; *) die "body must be -m \"text\", -f file, or - (stdin)";; esac; }

case "$CMD" in
  claim)
    DESC="Claude Code lead session"; [ "${1:-}" = "--desc" ] && DESC="$2"
    if mkdir "$L" 2>/dev/null; then
      printf '%s claimed %s\n' "$(ts)" "$DESC" > "$L/claim"
      ensure_log; printf '\n## Lead claimed %s — %s\n' "$(ts)" "$DESC" >> "$LOG"
      printf -- '- lead claimed at %s, %s\n' "$(ts)" "$DESC" >> "$COORD/registry.md"
      echo "lead"; exit 0
    fi
    echo "lead lock is held: $(lead_lock_state) · last lead write $(fmt_age "$(lead_activity_age_min)") ago · verdict: $(lead_liveness)" >&2
    echo "if it is dead by evidence: $0 takeover --reason \"<evidence>\"; otherwise you are a STANDBY: $0 standby" >&2
    exit 2;;
  takeover)
    REASON=""; FORCE=""; DESC="Claude Code standby lead"
    while [ $# -gt 0 ]; do case "$1" in --reason) REASON="$2"; shift 2;; --force) FORCE=1; shift;; --desc) DESC="$2"; shift 2;; *) die "unknown arg: $1";; esac; done
    [ -n "$REASON" ] || die "--reason required (cite the evidence: lead-log.md / inbox ages, what is waiting)"
    [ -d "$L" ] || die "no lead lock — claim it normally"
    a="$(lead_activity_age_min)"
    if [ -z "$FORCE" ] && { [ "$a" = "-" ] || [ "$a" -lt "$DEAD_MIN" ]; }; then
      die "the lead wrote something ${a}m ago (< DEAD_MIN=$DEAD_MIN) — it may be alive. Re-check '$0 status', or --force with stronger evidence."
    fi
    gen="$(ls -d "$L"/takeover-*.lock 2>/dev/null | wc -l | tr -d ' ')"; T="$L/takeover-$((gen + 1)).lock"
    [ -n "${COWORK_TEST_SLEEP:-}" ] && sleep "$COWORK_TEST_SLEEP"
    mkdir "$T" 2>/dev/null || die "takeover race lost — another standby got there first"
    printf '%s takeover %s — %s\n' "$(ts)" "$DESC" "$REASON" > "$T/claim"
    ensure_log; printf '\n## Lead TAKEN OVER %s — %s\nEvidence: %s. Resuming per LEAD.md Boot (state reconstructed from inboxes/outboxes, not from the predecessor'"'"'s memory).\n' "$(ts)" "$DESC" "$REASON" >> "$LOG"
    printf -- '- lead TAKEN OVER at %s by a new session (%s). Evidence: %s\n' "$(ts)" "$DESC" "$REASON" >> "$COORD/registry.md"
    n=1; while [ "$n" -le "$SEATS" ]; do f="$(inbox "seat-$n")"; [ -f "$f" ] && printf '\n## Lead session replaced (%s, lead)\nA standby lead took over (evidence in coordination/lead-log.md). Open rulings and reviews resume from here; nothing you reported is lost.\n' "$(ts)" >> "$f"; n=$((n + 1)); done
    echo "lead"; exit 0;;
  heartbeat)
    ensure_log; B="$(body_from "$@")" || exit 1
    { printf '\n## Heartbeat %s\n' "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$LOG"; echo "lead heartbeat";;
  note)
    H="${1:?heading}"; shift; ensure_log; B="$(body_from "$@")" || exit 1
    { printf '\n## %s (%s)\n' "$H" "$(ts)"; [ -n "$B" ] && printf '%s\n' "$B"; } >> "$LOG"; echo "lead note: $H";;
  standby)
    T="${1:-$LEAD_WATCH_TIMEOUT}"; P="${2:-20}"; ELAPSED=0
    while [ "$ELAPSED" -lt "$T" ]; do
      case "$(lead_liveness)" in DEAD?*|unclaimed) exit 0;; esac
      sleep "$P"; ELAPSED=$((ELAPSED + P))
    done
    exit 4;;
  status) echo "lead: lock $(lead_lock_state) · last write $(fmt_age "$(lead_activity_age_min)") ago · $(lead_liveness)";;
  *) die "unknown command: $CMD";;
esac
