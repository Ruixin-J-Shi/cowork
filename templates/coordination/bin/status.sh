#!/usr/bin/env bash
# One screen of truth for the lead (or a curious human): every slot's lock, inbox STATUS,
# write ages, open tasks and a liveness verdict; then territory activity.
# Usage: status.sh [--json]
. "$(dirname "$0")/common.sh"
case "${1:-}" in -h|--help) awk 'NR>1 && !/^#/ {exit} NR>1 {print}' "$0"; exit 0;; esac
JSON=""; [ "${1:-}" = "--json" ] && JSON=1

if [ -n "$JSON" ]; then
  printf '{"project":"%s","root":"%s","time":"%s","seats":[' "$PROJECT_NAME" "$ROOT" "$(ts)"
  n=1; while [ "$n" -le "$SEATS" ]; do
    w="seat-$n"; [ "$n" -gt 1 ] && printf ','
    printf '{"id":"%s","lock":"%s","status":"%s","inbox_age_min":"%s","outbox_age_min":"%s","open":"%s","liveness":"%s"}' \
      "$w" "$(lock_state "$w")" "$(inbox_status "$w")" "$(age_min "$(inbox "$w")")" "$(age_min "$(outbox "$w")")" "$(open_tasks "$w")" "$(liveness "$w")"
    n=$((n+1)); done
  printf '],"territory_age_min":"%s","lead":{"lock":"%s","activity_age_min":"%s","liveness":"%s"}}\n' "$(territory_age_min)" "$(lead_lock_state)" "$(lead_activity_age_min)" "$(lead_liveness)"
  exit 0
fi

echo "cowork status — $PROJECT_NAME · node $(node_path) · $(ts) · ROOT=$ROOT"
echo "thresholds: heartbeat ${HEARTBEAT_MIN}m · dead ${DEAD_MIN}m · stall ${STALL_MIN}m"
echo "lead: lock $(lead_lock_state) · last write $(fmt_age "$(lead_activity_age_min)") ago · $(lead_liveness)"
printf '%-10s %-10s %-10s %-8s %-8s %-8s %-28s %s\n' slot lock STATUS inbox↑ outbox↑ terr↑ 'open tasks' liveness
n=1
while [ "$n" -le "$SEATS" ]; do
  w="seat-$n"; lb="$(slot_label "$w")"; [ -n "$lb" ] && lb="$w=$lb" || lb="$w"
  printf '%-10s %-10s %-10s %-8s %-8s %-8s %-28s %s\n' "$lb" "$(lock_state "$w")" "$(inbox_status "$w" | cut -c1-10)" \
    "$(fmt_age "$(age_min "$(inbox "$w")")")" "$(fmt_age "$(age_min "$(outbox "$w")")")" "$(fmt_age "$(slot_territory_age_min "$w")")" "$(open_tasks "$w" | cut -c1-28)" "$(liveness "$w")"
  n=$((n + 1))
done
echo "terr↑ = newest write in the slot's own territory (TERRITORY_N in cowork.conf) or, unset, in all territories"
echo "territories:$(territory_list "$TERRITORIES" | while IFS= read -r p; do [ -n "$p" ] || continue; if ! inside_root "$p"; then printf ' %s(OUTSIDE ROOT, ignored)' "$p"; elif [ -e "$ROOT/$p" ]; then printf ' %s(%s)' "$p" "$(fmt_age "$(newest_age_min "$ROOT/$p")")"; else printf ' %s(missing)' "$p"; fi; done) · newest write anywhere: $(fmt_age "$(territory_age_min)") ago"
last="$(tail -1 "$COORD/registry.md" 2>/dev/null)"; [ -n "$last" ] && echo "registry, last line: $last"
