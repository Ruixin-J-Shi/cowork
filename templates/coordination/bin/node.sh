#!/usr/bin/env bash
# A NODE is one session that is seat-N of the team above AND the lead of this team. This script runs both sides.
# Position is derived from the directory: <parent>/teams/seat-N/ ⇒ you are seat-N of <parent>. The top dir has no "above".
#
# Usage:
#   node.sh boot [--desc "…"]     claim your fixed slot above (if any) and the lead lock here; read the inbox above; print what to arm
#                                 (refuses, claiming nothing, if the lead lock here is already held — this team has a node)
#   node.sh boot --takeover --reason "<evidence>" [--force] [--desc "…"]
#                                 replace a dead node: take over the slot above, THEN the lead lock below (that order), then as boot
#   node.sh status                where you are in the tree, your link above, your team below
#   node.sh watch [timeout_s]     one combined wait: exit 10 = your inbox ABOVE changed (seat steps; the side above wins a tie,
#                                 the change below is kept for the next call); exit 0 = an outbox/registry BELOW changed
#                                 (lead steps); 3 = team stalled; 4 = timeout
#   node.sh inbox [--quiet]       read your inbox above (records the seen version — the race-free read)
#   node.sh report <args…>        append to your outbox above (same forms as report.sh, slot filled in)
#   node.sh heartbeat [-m "…"]    one line both ways: HEARTBEAT above (if any) and lead-log.md below
. "$(dirname "$0")/common.sh"
case "${1:-}" in ''|-h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
CMD="$1"; shift
UPB="$UP_COORD/bin"
# Undo the claim (or takeover) this boot made on the slot above seconds ago, when the lead lock below then could not be
# taken: the slot must never sit orphaned, reading ALIVE with no node behind it. Nothing else can hold what we just made
# (a takeover needs a DEAD_MIN-stale outbox, and our own line made it fresh). Deletion = mv to trash, announced.
release_above() { # $1 = why
  [ -n "$UP_COORD" ] || return 0
  local L="$UP_COORD/locks/$UP_SLOT.lock" src what rel n
  if [ -n "$TAKE" ]; then n="$(ls -d "$L"/takeover-*.lock 2>/dev/null | wc -l | tr -d ' ')"; src="$L/takeover-$n.lock"; what=Takeover
  else src="$L"; what=Claim; fi
  [ -d "$src" ] || return 0
  mkdir -p "$UP_COORD/trash"; rel="$UP_COORD/trash/$UP_SLOT.$(basename "$src").released-$(date +%Y%m%d%H%M%S)"
  mv "$src" "$rel" 2>/dev/null || return 0
  printf -- '- %s %s RELEASED at %s: node boot aborted (lead lock below: %s); moved to trash\n' "$UP_SLOT" "$what" "$(ts)" "$1" >> "$UP_COORD/registry.md"
  printf '\n## %s released %s — node boot aborted (lead lock of %s: %s); the slot is as it was before this boot\n' "$what" "$(ts)" "$C_REL" "$1" >> "$(up_outbox)"
  echo "above: released the $(echo "$what" | tr 'A-Z' 'a-z') of $UP_SLOT again (moved to ${rel#$ROOT/})" >&2
}
case "$CMD" in
  boot)
    DESC="Claude Code node session"; TAKE=""; REASON=""; FORCE=""
    while [ $# -gt 0 ]; do case "$1" in --desc) DESC="$2"; shift 2;; --takeover) TAKE=1; shift;; --reason) REASON="$2"; shift 2;; --force) FORCE="--force"; shift;; *) die "unknown arg: $1";; esac; done
    echo "node $(node_path) · dir $C_REL · root $ROOT"
    if [ -n "$UP_COORD" ]; then
      if [ -n "$TAKE" ]; then
        [ -n "$REASON" ] || die "--takeover needs --reason (the evidence: outbox above age, this team's lead-log.md age, open work)"
        up="$(bash "$UPB/claim.sh" --takeover "$UP_SLOT" --reason "$REASON" --desc "node $(node_path): $DESC" $FORCE)" || exit 1
        echo "above: took over $up in ${UP_COORD#$ROOT/}"
      else
        # pre-flight before touching the slot above: a boot must never leave an orphaned claim there
        [ -d "$(lead_lock)" ] && { echo "lead lock of $C_REL is already held ($(bash "$COORD/bin/lead.sh" status)) — this team already has a node. If it is dead by evidence: $0 boot --takeover --reason \"<evidence>\"; otherwise you are a standby (prompts/node-standby.md)." >&2; exit 2; }
        up="$(bash "$UPB/claim.sh" --slot "$UP_SLOT" --desc "node $(node_path): $DESC")"; rc=$?
        if [ "$rc" = 2 ]; then echo "slot $UP_SLOT above is held — if its session is dead by evidence: $0 boot --takeover --reason \"<evidence>\"; if alive, this team already has a node." >&2; exit 2
        elif [ "$rc" != 0 ]; then echo "the team above (${UP_COORD#$ROOT/}) has no slot $UP_SLOT: raise SEATS in its cowork.conf and add inbox/outbox/$UP_SLOT.md there (see 'cowork grow')." >&2; exit 1; fi
        echo "above: claimed $up in ${UP_COORD#$ROOT/}"
      fi
    else echo "above: none (top of the tree — the human is your lead; only this node runs git)"; fi
    if [ -n "$TAKE" ]; then
      # the slot above was the gate (claim.sh judged the evidence). If the dead node held the lead lock below, it belongs to
      # that same dead session and our own takeover line above has just made "lead activity" look fresh, so that takeover is
      # forced by construction; if there is no lead lock below (the node died before claiming it, or locks/ is a fresh clone), claim it.
      if [ -d "$(lead_lock)" ]; then
        m="$(bash "$COORD/bin/lead.sh" takeover --reason "$REASON" --desc "node $(node_path): $DESC" --force)" || { release_above "takeover race lost"; echo "the lead lock here was taken over by another session first — resolve with lead.sh status before booting again" >&2; exit 1; }
        echo "below: took over the lead lock of $C_REL ($SEATS slots)"
      else   # the dead node never held a lead lock here (or this is a fresh clone with empty locks/): claim it normally
        m="$(bash "$COORD/bin/lead.sh" claim --desc "node $(node_path): $DESC")" || { release_above "free, but could not be claimed"; echo "the free lead lock here could not be claimed — resolve with lead.sh status before booting again" >&2; exit 1; }
        echo "below: claimed the free lead lock of $C_REL ($SEATS slots)"
      fi
    else
      m="$(bash "$COORD/bin/lead.sh" claim --desc "node $(node_path): $DESC")" || {
        release_above "already held"   # lost the (pre-checked) race for the lead lock below
        echo "lead lock here is held — this team already has a node (standby or takeover per TREE.md)" >&2; exit 2; }
      echo "below: claimed lead lock of $C_REL ($SEATS slots)"
    fi
    outbox_mark_seen
    if [ -n "$UP_COORD" ]; then echo "--- inbox above (${UP_COORD#$ROOT/}/inbox/$UP_SLOT.md), now recorded as seen ---"; bash "$UPB/inbox.sh" "$UP_SLOT"; echo "---"; fi
    echo "next: read $C_REL/LEAD.md (§ You are a node), act on anything already in the inbox above, then arm 'bash $C_REL/bin/node.sh watch' as a background task";;
  status)
    echo "node $(node_path) · dir $C_REL"
    if [ -n "$UP_COORD" ]; then
      US="$UP_SLOT"   # sourcing the parent's common.sh recomputes UP_SLOT for the parent (empty at the top); keep ours
      echo "above: $US of ${UP_COORD#$ROOT/} · lock $(cd "$UP_COORD" && . bin/common.sh && lock_state "$US") · inbox↑ $(fmt_age "$(age_min "$(up_inbox)")") · outbox↑ $(fmt_age "$(age_min "$(up_outbox)")") · open above: $(cd "$UP_COORD" && . bin/common.sh && open_tasks "$US")"
    else echo "above: none (top)"; fi
    echo "below: $(bash "$COORD/bin/lead.sh" status)"
    bash "$COORD/bin/status.sh" | sed -n '4,$p' | sed 's/^/  /'
    teams_below | while IFS= read -r t; do echo "  team $(basename "$t"): $(bash "$t/bin/lead.sh" status 2>/dev/null)"; done; true;;
  watch)
    T="${1:-$LEAD_WATCH_TIMEOUT}"; STALL="$STALL_MIN"
    snapshot() { outbox_snapshot; }
    up_changed() { [ -n "$UP_COORD" ] || return 1; local seen="$UP_COORD/locks/$UP_SLOT.lock/inbox-seen" m0; if [ -f "$seen" ]; then m0="$(tr -d '[:space:]' < "$seen")"; else m0="$UPM0"; fi; [ "$(mtime "$(up_inbox)")" != "$m0" ]; }
    recent() { territory_list "$TERRITORIES" | while IFS= read -r p; do [ -n "$p" ] && inside_root "$p" && [ -e "$ROOT/$p" ] && find "$ROOT/$p" -type f -not -path '*/.git/*' -not -path '*/node_modules/*' -mmin -"$STALL" 2>/dev/null | head -1; done; find "$COORD/outbox" -type f -mmin -"$STALL" 2>/dev/null | head -1; }
    # Both sides keep a persisted "seen" baseline (inbox-seen above via inbox.sh; outbox-seen below, written at exit 0),
    # so a change on one side that was pre-empted by the other side's exit is still detected on the next call.
    UPM0="$( [ -n "$UP_COORD" ] && mtime "$(up_inbox)" || echo 0 )"; S0="$(outbox_seen_baseline)"
    up_changed && exit 10
    [ "$(snapshot)" != "$S0" ] && { outbox_mark_seen; exit 0; }
    STALL_ENABLED=1; [ -z "$(recent | head -1)" ] && STALL_ENABLED=0
    any_open_work || STALL_ENABLED=0   # a finished team waiting on the review above is not a stall
    ELAPSED=0
    while [ "$ELAPSED" -lt "$T" ]; do
      sleep 15; ELAPSED=$((ELAPSED + 15))
      up_changed && exit 10
      [ "$(snapshot)" != "$S0" ] && { outbox_mark_seen; exit 0; }
      if [ "$STALL_ENABLED" = 1 ] && [ -z "$(recent | head -1)" ]; then outbox_mark_seen; exit 3; fi
    done
    outbox_mark_seen; exit 4;;
  inbox)   [ -n "$UP_COORD" ] || die "top node: nothing above"; exec bash "$UPB/inbox.sh" "$UP_SLOT" "$@";;
  report)  [ -n "$UP_COORD" ] || die "top node: nothing above"; exec bash "$UPB/report.sh" "$UP_SLOT" "$@";;
  heartbeat)
    [ -n "$UP_COORD" ] && bash "$UPB/report.sh" "$UP_SLOT" HEARTBEAT "$@" >/dev/null
    bash "$COORD/bin/lead.sh" heartbeat "$@" >/dev/null; echo "node $(node_path) heartbeat";;
  *) die "unknown command: $CMD";;
esac
