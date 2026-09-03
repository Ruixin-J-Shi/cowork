#!/usr/bin/env bash
# Health check for a coordination/ dir: structure, config, stale locks, dead sessions, hooks.
# Exit 1 if anything FAILs; WARN/INFO never fail. Usage: doctor.sh
. "$(dirname "$0")/common.sh"
case "${1:-}" in -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
fails=0
ok()   { echo "  ok    $*"; }
warn() { echo "  WARN  $*"; }
info() { echo "  info  $*"; }
fail() { echo "  FAIL  $*"; fails=$((fails + 1)); }

echo "cowork doctor — $PROJECT_NAME · ROOT=$ROOT"
echo "structure"
for d in inbox outbox locks trash bin; do [ -d "$COORD/$d" ] && ok "coordination/$d" || fail "coordination/$d missing"; done
for b in common claim report inbox watch dispatch lead-watch status doctor; do [ -f "$COORD/bin/$b.sh" ] || fail "bin/$b.sh missing (run 'cowork update')"; done
for d in locks trash inbox outbox; do [ -f "$COORD/$d/.gitkeep" ] || warn "coordination/$d/.gitkeep missing (git keeps no empty dirs; a fresh clone would lack the dir)"; done
[ -f "$COORD/PROTOCOL.md" ] && ok "PROTOCOL.md" || fail "coordination/PROTOCOL.md missing — seats cannot boot"
[ -f "$COORD/LEAD.md" ] && ok "LEAD.md" || warn "coordination/LEAD.md missing — lead playbook"
[ -f "$COORD/registry.md" ] && ok "registry.md" || warn "registry.md missing (claim.sh creates it)"
[ -f "$COORD/cowork.conf" ] && ok "cowork.conf (SEATS=$SEATS, HEARTBEAT_MIN=$HEARTBEAT_MIN, DEAD_MIN=$DEAD_MIN, STALL_MIN=$STALL_MIN)" || warn "cowork.conf missing — defaults in use"
[ "$(mtime "$COORD/PROTOCOL.md")" != 0 ] && ok "stat works (mtime probing)" || fail "stat could not read an mtime — watch scripts will not work"
if [ -z "$TERRITORIES" ]; then warn "TERRITORIES empty — stall detection only sees outboxes; set it in cowork.conf"; else
  while IFS= read -r p; do [ -n "$p" ] || continue
    if ! inside_root "$p"; then fail "territory '$p' resolves outside the project root — liveness ignores it; fix cowork.conf"
    elif [ -e "$ROOT/$p" ]; then ok "territory $p"; else warn "territory '$p' does not exist (yet?)"; fi
  done <<EOF
$(territory_list "$TERRITORIES")
EOF
fi
if [ "$SEATS" -gt 1 ]; then
  missing=""; n=1; while [ "$n" -le "$SEATS" ]; do grep -qE "^TERRITORY_$n=" "$COORD/cowork.conf" 2>/dev/null || missing="$missing $n"; n=$((n + 1)); done
  [ -n "$missing" ] && warn "no TERRITORY_N in cowork.conf for seat(s)$missing — a dead seat there can hide behind a busy sibling; mirror PLAN.md's ownership map"
fi
grep -qE '^## ' "$COORD/PROTOCOL.md" 2>/dev/null && grep -q 'STATUS: DISMISSED' "$COORD/PROTOCOL.md" 2>/dev/null || warn "PROTOCOL.md does not mention STATUS: DISMISSED — seats would never know how to end"
for f in PROTOCOL.md LEAD.md cowork.conf prompts/seat-boot.md prompts/lead-boot.md; do grep -q '@@' "$COORD/$f" 2>/dev/null && fail "$f still contains unrendered @@PLACEHOLDERS@@"; done

echo "lead"
info "node $(node_path) · dir $C_REL · root $ROOT${PROJECT_ROOT_REL:+ (PROJECT_ROOT_REL=$PROJECT_ROOT_REL)}"
[ -n "$UP_COORD" ] && { [ -f "$(up_inbox)" ] && info "above: $UP_SLOT of ${UP_COORD#$ROOT/}" || fail "above: ${UP_COORD#$ROOT/} has no inbox for $UP_SLOT — the parent's SEATS is too small for this team dir"; }
[ -f "$COORD/lead-log.md" ] && info "lead-log.md present" || info "no lead-log.md yet (lead.sh claim writes it)"
mlv="$(lead_liveness)"; case "$mlv" in DEAD*) warn "lead: $mlv";; *) info "lead: lock $(lead_lock_state) · $mlv";; esac
teams_below | while IFS= read -r t; do info "team below: $(basename "$t") ($(bash "$t/bin/lead.sh" status 2>/dev/null || echo 'no scripts?'))"; done
teams_below | while IFS= read -r t; do tn="$(basename "$t")"; tn="${tn#seat-}"; [ "$tn" -gt "$SEATS" ] && warn "teams/seat-$tn exists but SEATS=$SEATS — orphaned team (node.sh boot there fails with 'out of range'); raise SEATS and add inbox/outbox/seat-$tn.md"; done
if [ -n "$UP_COORD" ] && [ -f "$UP_COORD/cowork.conf" ]; then
  pt="$(grep -E '^TERRITORIES=' "$UP_COORD/cowork.conf" | head -1)"; mt="$(grep -E '^TERRITORIES=' "$COORD/cowork.conf" | head -1)"
  [ -n "$pt" ] && [ "$pt" = "$mt" ] && warn "this team's TERRITORIES is identical to its parent's — scope it to what THIS node owns, or a sibling's writes silence your stall alarm"
fi
for b in lead node; do [ -f "$COORD/bin/$b.sh" ] || fail "bin/$b.sh missing (run 'cowork update')"; done
echo "slots"
n=1
while [ "$n" -le "$SEATS" ]; do
  w="seat-$n"
  [ -f "$(inbox "$w")" ] || fail "$w inbox missing"
  [ -f "$(inbox "$w")" ] && ! grep -qE '^STATUS:' "$(inbox "$w")" && fail "$w inbox has no STATUS: line"
  st="$(inbox_status "$w")"; ls="$(lock_state "$w")"; lv="$(liveness "$w")"
  case "$lv" in
    DEAD*) warn "$w: $lv → bin/claim.sh --takeover $w --reason \"...\" (from a new session), and/or reassign its open work";;
    QUIET*|SILENT*) warn "$w: $lv → dispatch a heartbeat check";;
    *) info "$w: lock $ls · STATUS ${st:-?} · $lv";;
  esac
  [ "$st" = DISMISSED ] && [ "$ls" != free ] && info "$w is DISMISSED but its lock is held — the session may still be wrapping up; the lock is harmless until a successor takes over"
  n=$((n + 1))
done
n=$((SEATS + 1)); while [ -d "$(lockdir "seat-$n")" ]; do warn "locks/seat-$n.lock exists but SEATS=$SEATS"; n=$((n + 1)); done

echo "git"
[ -d "$ROOT/.git" ] && ok "git repository" || info "not a git repository yet (the protocol does not require git; the lead usually wants it)"
if grep -qs 'locks/\*' "$ROOT/.gitignore"; then ok ".gitignore covers locks (runtime state stays out of history)"; else warn ".gitignore does not exclude coordination/**/locks/* — committed locks would block claims on a fresh clone"; fi
if grep -qs 'trash/\*' "$ROOT/.gitignore"; then ok ".gitignore covers trash"; else warn ".gitignore does not exclude coordination/**/trash/"; fi

echo "notifications (optional)"
[ -f "$HOME/.claude/hooks/ntfy-hook.sh" ] && info "~/.claude/hooks/ntfy-hook.sh installed" || info "ntfy hook not installed (optional; see hooks/ntfy-hook.sh header)"
[ -f "$HOME/.claude/lead-session-id" ] && info "lead session id recorded: $(tr -d '[:space:]' < "$HOME/.claude/lead-session-id" | cut -c1-8)…" || info "no ~/.claude/lead-session-id (only needed for the lead ring)"
[ -n "$NTFY_TOPIC" ] && info "NTFY_TOPIC set" || info "NTFY_TOPIC unset"

t="$(du -sh "$COORD/trash" 2>/dev/null | cut -f1)"; info "trash size: ${t:-0}"
echo; [ "$fails" = 0 ] && echo "healthy" || { echo "$fails FAIL(s)"; exit 1; }
