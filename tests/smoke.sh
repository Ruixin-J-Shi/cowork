#!/usr/bin/env bash
# End-to-end smoke test of the kit: init → claim ×N (+1 fails) → dispatch → watch wakes → report → status → takeover → dismiss → doctor.
# Usage: bash tests/smoke.sh [scratch-dir]   (default: mktemp)
set -u
KIT="$(cd "$(dirname "$0")/.." && pwd)"
S="${1:-$(mktemp -d)}"; P="$S/demo-project"
cd "$S"   # never run from the kit dir: a relative glob in the CLI once rendered correctly only because the kit's own prompts/ was the cwd
pass=0; failn=0
ok()   { pass=$((pass+1)); echo "  ok   $*"; }
fail() { failn=$((failn+1)); echo "  FAIL $*"; }
check(){ if eval "$1"; then ok "$2"; else fail "$2  [$1]"; fi; }

echo "== init"
out="$("$KIT/cowork" init "$P" --seats 2 --project demo --territories "src tests" 2>&1)"; rc=$?
check '[ $rc = 0 ]' "init exits 0"
check '[ -f "$P/coordination/PROTOCOL.md" ]' "PROTOCOL.md scaffolded"
check '! grep -q "@@" "$P/coordination/PROTOCOL.md"' "placeholders rendered in PROTOCOL.md"
check '! grep -q "@@" "$P/coordination/cowork.conf"' "placeholders rendered in cowork.conf"
check 'grep -q "^SEATS=2" "$P/coordination/cowork.conf"' "SEATS=2 in conf"
check '[ -f "$P/coordination/inbox/seat-2.md" ] && [ ! -f "$P/coordination/inbox/seat-3.md" ]' "exactly 2 inbox files"
check 'grep -q "coordination/locks" "$P/.gitignore"' ".gitignore snippet appended"
check '[ -f "$P/PLAN.md" ] && [ -f "$P/CONVENTIONS.md" ]' "PLAN.md + CONVENTIONS.md created"
check '"$KIT/cowork" init "$P" 2>&1 | grep -q "already exists"' "second init refuses"
mkdir -p "$P/src" "$P/tests"; echo "x" > "$P/src/a.ts"; ( cd "$P" && git init -q . )
B="$P/coordination/bin"

echo "== claim"
w1="$(bash "$B/claim.sh" --desc "session A")"; check '[ "$w1" = seat-1 ]' "first claim → seat-1"
w2="$(bash "$B/claim.sh" --desc "session B")"; check '[ "$w2" = seat-2 ]' "second claim → seat-2"
err="$(bash "$B/claim.sh" 2>&1 >/dev/null)"; rc=$?; check '[ $rc = 2 ]' "third claim exits 2 (all held)"
check 'echo "$err" | grep -q "seat-1: lock held"' "third claim prints per-slot evidence"
check '[ "$(grep -c "claimed at" "$P/coordination/registry.md")" = 2 ]' "registry has 2 claim lines"
check 'grep -q "^## Claimed .* — session A" "$P/coordination/outbox/seat-1.md"' "claim announces itself in the outbox"
check 'bash "$B/status.sh" | grep seat-1 | grep -q "ALIVE"' "freshly claimed slot reads ALIVE"
check '[ -d "$P/coordination/locks/seat-1.lock" ]' "lock dir exists"

echo "== dispatch + watch"
( bash "$B/watch.sh" seat-1 60; echo "watch-exit=$?" > "$S/watch.out" ) &
sleep 1
nid="$(bash "$B/dispatch.sh" seat-1 --next-id)"; check '[ "$nid" = T1 ]' "next-id on empty inbox = T1"
bash "$B/dispatch.sh" seat-1 "T1 — build the widget" -m "1. do X
2. do Y
Acceptance: tests green." >/dev/null
check 'grep -q "^## T1 — build the widget (.*lead)" "$P/coordination/inbox/seat-1.md"' "task block appended with stamp"
nid="$(bash "$B/dispatch.sh" seat-1 --next-id)"; check '[ "$nid" = T2 ]' "next-id after T1 = T2"
printf 'Ruling body from stdin\n' | bash "$B/dispatch.sh" seat-1 "Ruling — widget colour" - >/dev/null
check 'grep -q "Ruling body from stdin" "$P/coordination/inbox/seat-1.md"' "stdin body works"
bash "$B/dispatch.sh" --all "⚠️ ALL-HANDS — rm discipline" -m "Acknowledge in one line." >/dev/null
check 'grep -q "ALL-HANDS" "$P/coordination/inbox/seat-2.md"' "broadcast reaches seat-2"
i=0; while [ ! -f "$S/watch.out" ] && [ $i -lt 40 ]; do sleep 1; i=$((i+1)); done
check '[ "$(cat "$S/watch.out" 2>/dev/null)" = "watch-exit=0" ]' "watch.sh woke on inbox change (exit 0) within ${i}s"
# the lost-wakeup race: read inbox (records seen mtime) → dispatch lands → THEN arm watch → must fire at once
bash "$B/inbox.sh" seat-1 --quiet
check '[ -f "$P/coordination/locks/seat-1.lock/inbox-seen" ]' "inbox.sh records the seen mtime"
sleep 1; bash "$B/dispatch.sh" seat-1 "Note — landed while working" -m "x" >/dev/null
t0=$(date +%s); bash "$B/watch.sh" seat-1 60; rc=$?; t1=$(date +%s)
check '[ $rc = 0 ] && [ $((t1-t0)) -lt 15 ]' "watch.sh fires immediately for a dispatch that landed after the last inbox read (${rc}, $((t1-t0))s)"
bash "$B/inbox.sh" seat-1 --quiet; bash "$B/watch.sh" seat-1 15; rc=$?
check '[ $rc = 4 ]' "watch.sh times out (exit 4) when nothing new since the last read"
check 'bash "$B/watch.sh" --help | grep -q "Usage"' "watch.sh --help"

echo "== report + status"
check 'echo "$(bash "$B/status.sh" | grep seat-1)" | grep -q "T1(unacked)"' "status shows T1 unacked"
bash "$B/report.sh" seat-01 T1 IN_PROGRESS -m "canonical id" >/dev/null
check 'grep -q "^## T1 — IN_PROGRESS" "$P/coordination/outbox/seat-1.md"' "seat-01 canonicalises to seat-1"
rc=0; bash "$B/report.sh" seat-1 TODO -m "x" >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "report.sh rejects a non-task kind starting with T"
n0="$(wc -l < "$P/coordination/inbox/seat-1.md")"; rc=0; bash "$B/dispatch.sh" seat-1 "Bad flag" -x "y" >/dev/null 2>&1 || rc=$?
check '[ $rc != 0 ] && [ "$(wc -l < "$P/coordination/inbox/seat-1.md")" = "$n0" ]' "dispatch with a bad body flag fails and appends nothing"
check 'bash "$B/status.sh" | grep seat-1 | grep -q "T1(in progress)"' "status shows T1 in progress"
check 'bash "$B/status.sh" | grep seat-1 | grep -q ALIVE' "seat-1 ALIVE after writing"
rc=0; bash "$B/report.sh" seat-1 T1 DONE >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "DONE without a report is refused"
printf 'from a file\n' > "$S/body.md"; bash "$B/report.sh" seat-1 NOTE "📎 seat-2: interface" -f "$S/body.md" >/dev/null
check 'grep -q "from a file" "$P/coordination/outbox/seat-1.md"' "report -f file body"
bash "$B/report.sh" seat-1 T1 DONE -m "did X and Y; files: src/a.ts; verified: tests 3/3" >/dev/null
check 'bash "$B/status.sh" | grep seat-1 | grep -q "ALIVE, idle"' "after DONE: ALIVE, idle (no open tasks)"
bash "$B/dispatch.sh" seat-1 "T9 — needs a file I do not own" -m "x" >/dev/null
bash "$B/report.sh" seat-1 T9 BLOCKED -m "needs Makefile (lead-owned)" >/dev/null
check 'bash "$B/status.sh" | grep seat-1 | grep -q "T9(blocked)"' "BLOCKED task stays visible as open"
bash "$B/report.sh" seat-1 T9 DONE -m "blocker cleared; supersedes the BLOCKED entry" >/dev/null
check 'bash "$B/status.sh" | grep seat-1 | grep -q "ALIVE, idle"' "DONE after BLOCKED closes the same id"
bash "$B/report.sh" seat-1 HEARTBEAT -m "still here" >/dev/null
check 'grep -q "^## Heartbeat .* — alive" "$P/coordination/outbox/seat-1.md"' "heartbeat line format"
bash "$B/report.sh" seat-1 INCIDENT -m "stray rm in a command; blast radius: none" >/dev/null
check 'grep -q "INCIDENT" "$P/coordination/outbox/seat-1.md"' "incident line recorded"
bash "$B/report.sh" seat-1 ACK "all-hands rm discipline" -m "read, understood" >/dev/null
check 'grep -q "^## ACK all-hands rm discipline" "$P/coordination/outbox/seat-1.md"' "ACK verb"
bash "$B/report.sh" seat-1 T1 RESUMED -m "took over" >/dev/null
check 'grep -q "^## T1 — RESUMED" "$P/coordination/outbox/seat-1.md"' "RESUMED marker"
check 'bash "$B/status.sh" --json | grep -q "\"id\":\"seat-1\""' "status --json emits seat entries"

echo "== takeover"
bash "$B/dispatch.sh" seat-2 "T1 — port the thing" -m "do it" >/dev/null
# backdate seat-2's outbox + territories to look dead (mtime 3h ago)
old="$(date -v-3H '+%Y%m%d%H%M' 2>/dev/null || date -d '3 hours ago' '+%Y%m%d%H%M')"
touch -t "$old" "$P/coordination/outbox/seat-2.md" "$P/coordination/outbox/seat-1.md"
find "$P/src" "$P/tests" -type f -exec touch -t "$old" {} \; 2>/dev/null
check 'bash "$B/status.sh" | grep seat-2 | grep -q "DEAD?"' "status flags seat-2 DEAD? (stale outbox, open task)"
# a busy sibling must not mask a dead seat: per-slot territories
echo fresh > "$P/src/b.ts"
check 'bash "$B/status.sh" | grep seat-2 | grep -q "SILENT"' "without per-slot territories, sibling activity masks seat-2 (SILENT)"
mkdir -p "$P/my docs"; echo x > "$P/my docs/a.md"; touch -t "$old" "$P/my docs/a.md"
printf 'TERRITORY_1="src:my docs"\nTERRITORY_2="tests"\n' >> "$P/coordination/cowork.conf"
check 'bash "$B/status.sh" | grep -q "seat-1"' "colon-separated territory with a space parses"
check 'bash "$B/status.sh" | grep seat-2 | grep -q "DEAD?"' "with TERRITORY_2=tests, seat-2 is DEAD? despite seat-1 activity"
rc=0; bash "$B/claim.sh" --takeover seat-2 2>/dev/null >/dev/null || rc=$?; check '[ $rc != 0 ]' "takeover without --reason refused"
mv "$P/coordination/outbox/seat-2.md" "$S/w2.bak"; rc=0; bash "$B/claim.sh" --takeover seat-2 --reason "x" >/dev/null 2>&1 || rc=$?; mv "$S/w2.bak" "$P/coordination/outbox/seat-2.md"; touch -t "$old" "$P/coordination/outbox/seat-2.md"
check '[ $rc != 0 ]' "takeover refused when the outbox is missing (no evidence)"
w="$(bash "$B/claim.sh" --takeover seat-2 --reason "outbox 3h stale, T1 unacked" --desc "session C")"
check '[ "$w" = seat-2 ]' "takeover succeeds → seat-2"
check '[ -d "$P/coordination/locks/seat-2.lock/takeover-1.lock" ]' "nested takeover lock takeover-1"
check 'grep -q "TAKEN OVER" "$P/coordination/registry.md"' "registry records takeover"
check 'bash "$B/status.sh" | grep seat-2 | grep -q "held(+1)"' "status shows held(+1)"
check 'grep -q "^## Takeover " "$P/coordination/outbox/seat-2.md"' "takeover announced in the outbox"
rc=0; bash "$B/claim.sh" --takeover seat-2 --reason "x" >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "second taker refused: the successor's announcement made the slot ALIVE"
# concurrent race: both takers count the same generation and collide on one mkdir — exactly one wins
touch -t "$old" "$P/coordination/outbox/seat-2.md"
( COWORK_TEST_SLEEP=1 bash "$B/claim.sh" --takeover seat-2 --reason "race A" >/dev/null 2>&1; echo $? > "$S/raceA" ) &
( COWORK_TEST_SLEEP=1 bash "$B/claim.sh" --takeover seat-2 --reason "race B" >/dev/null 2>&1; echo $? > "$S/raceB" ) &
wait
wins=0; [ "$(cat "$S/raceA")" = 0 ] && wins=$((wins+1)); [ "$(cat "$S/raceB")" = 0 ] && wins=$((wins+1))
check '[ $wins = 1 ]' "concurrent takeover race: exactly one winner (got $wins)"
check '[ -d "$P/coordination/locks/seat-2.lock/takeover-2.lock" ] && [ ! -d "$P/coordination/locks/seat-2.lock/takeover-3.lock" ]' "race produced takeover-2 only"
# alive seat refuses takeover
bash "$B/report.sh" seat-1 HEARTBEAT >/dev/null
bash "$B/dispatch.sh" seat-1 "T2 — more" -m "x" >/dev/null
rc=0; bash "$B/claim.sh" --takeover seat-1 --reason "x" >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "takeover of a recently-active seat refused without --force"

echo "== stall suppression on a finished team"
bash "$B/dispatch.sh" seat-1 --status ACTIVE >/dev/null; bash "$B/dispatch.sh" seat-2 --status DISMISSED >/dev/null
# seat-1 has no open tasks (all DONE), seat-2 dismissed: territories stale → without suppression this would exit 3
find "$P/src" "$P/tests" "$P/coordination/outbox" -type f -exec touch -t "$old" {} \; 2>/dev/null
bash "$B/lead-watch.sh" 25 45; rc=$?; check '[ $rc = 4 ]' "lead-watch does not raise a stall (3) when nothing is open below (got $rc)"
bash "$B/dispatch.sh" seat-1 "T30 — reopen" -m "x" >/dev/null; find "$P/coordination/inbox" -type f -exec touch -t "$old" {} \; 2>/dev/null
echo "== lead-watch"
# a DONE that lands between the lead's read and its next arm must still wake it
bash "$B/lead.sh" claim --desc "mw" >/dev/null 2>&1 || true
bash "$B/lead-watch.sh" 20 45 >/dev/null; rc=$?   # exit 4 (nothing new) — also persists the baseline
bash "$B/report.sh" seat-1 NOTE "landed while lead was reading" -m "x" >/dev/null
t0=$(date +%s); bash "$B/lead-watch.sh" 60 45; rc=$?; t1=$(date +%s)
check '[ $rc = 0 ] && [ $((t1-t0)) -lt 15 ]' "lead-watch fires immediately for a change since the last wake ($rc, $((t1-t0))s)"
( bash "$B/lead-watch.sh" 60 45; echo "mw-exit=$?" > "$S/mw.out" ) &
sleep 2; bash "$B/report.sh" seat-1 HEARTBEAT -m "poke" >/dev/null
i=0; while [ ! -f "$S/mw.out" ] && [ $i -lt 40 ]; do sleep 1; i=$((i+1)); done
check '[ "$(cat "$S/mw.out" 2>/dev/null)" = "mw-exit=0" ]' "lead-watch woke on outbox change (exit 0) within ${i}s"

echo "== dismiss + doctor"
bash "$B/dispatch.sh" seat-1 --status DISMISSED >/dev/null
check 'grep -q "^STATUS: DISMISSED" "$P/coordination/inbox/seat-1.md"' "STATUS rewritten to DISMISSED"
check '[ "$(grep -c "^STATUS:" "$P/coordination/inbox/seat-1.md")" = 1 ]' "exactly one STATUS line"
check 'grep -q "^## STATUS → DISMISSED" "$P/coordination/inbox/seat-1.md"' "--status also appends a visible dated entry"
check 'bash "$B/status.sh" | grep seat-1 | grep -q "DISMISSED (outbox"' "status shows a dismissed slot as DISMISSED, not ALIVE"
n0="$(ls "$P/coordination/inbox" | wc -l | tr -d " ")"; bash "$B/dispatch.sh" --help >/dev/null; bash "$B/dispatch.sh" >/dev/null; bash "$B/report.sh" --help >/dev/null 2>&1 || true
rc=0; bash "$B/dispatch.sh" bogus "x" -m "y" >/dev/null 2>&1 || rc=$?
check '[ "$(ls "$P/coordination/inbox" | wc -l | tr -d " ")" = "$n0" ] && [ $rc != 0 ]' "dispatch --help / bad seat id create no stray files"
m1="$(stat -f %m "$P/coordination/inbox/seat-1.md" 2>/dev/null || stat -c %Y "$P/coordination/inbox/seat-1.md")"; sleep 1
bash "$B/dispatch.sh" seat-1 --status DISMISSED | grep -q unchanged && m2="$(stat -f %m "$P/coordination/inbox/seat-1.md" 2>/dev/null || stat -c %Y "$P/coordination/inbox/seat-1.md")"
check '[ "$m1" = "${m2:-}" ]' "--status is idempotent (no rewrite, no wake) when unchanged"
mkdir -p "$P/coordination/outbox/seat-1.artifacts"; echo log > "$P/coordination/outbox/seat-1.artifacts/t1.log"
check '( cd "$P" && ! git check-ignore -q coordination/outbox/seat-1.artifacts/t1.log )' "artifacts are NOT gitignored (they are part of the record)"
bash "$B/doctor.sh" > "$S/doctor.out" 2>&1; rc=$?
check '[ $rc = 0 ]' "doctor exits 0 on a healthy scaffold"
check 'grep -q "healthy" "$S/doctor.out"' "doctor says healthy"
check 'grep -q "gitignore covers locks" "$S/doctor.out"' "doctor sees gitignore coverage"
( cd "$P/src" && "$KIT/cowork" status >/dev/null ); check '[ $? = 0 ]' "cowork status proxies from a subdirectory"
NTFY_DRYRUN=1 out="$(printf '{"session_id":"abc","cwd":"%s"}' "$P" | bash "$P/coordination/hooks/ntfy-hook.sh" stop)"; check '[ -z "$out" ]' "ntfy hook silent when no topic configured"
sed -i.bak 's/^NTFY_TOPIC=""/NTFY_TOPIC="demo-topic"/' "$P/coordination/cowork.conf"
out="$(printf '{"session_id":"abc","cwd":"%s"}' "$P" | NTFY_DRYRUN=1 bash "$P/coordination/hooks/ntfy-hook.sh" stop)"; check 'echo "$out" | grep -q "demo-topic"' "ntfy hook reads topic from the project conf"

echo "== lead lock, log, standby, takeover"
bash "$B/lead.sh" status | grep -q "lock held" && { rc=0; bash "$B/lead.sh" claim >/dev/null 2>&1 || rc=$?; check '[ $rc = 2 ]' "lead claim refused while held (exit 2)"; }
m="$(bash "$B/lead.sh" status)"; check 'echo "$m" | grep -q "lock held"' "lead lock held from the earlier claim"
check '[ -d "$P/coordination/locks/lead.lock" ] && grep -q "^## Lead claimed" "$P/coordination/lead-log.md"' "lead lock + log boot line"
bash "$B/lead.sh" heartbeat -m "reviewed T1" >/dev/null; check 'grep -q "^## Heartbeat" "$P/coordination/lead-log.md"' "lead heartbeat"
check 'bash "$B/status.sh" | grep "^lead:" | grep -q ALIVE' "status shows lead ALIVE"
rc=0; bash "$B/lead.sh" takeover --reason "x" >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "takeover of a live lead refused"
bash "$B/lead.sh" standby 3 1; rc=$?; check '[ $rc = 4 ]' "standby times out (exit 4) while the lead is alive"
# lead goes silent with work waiting: backdate lead-log.md + inboxes, write a fresh outbox entry
find "$P/coordination/inbox" -name '*.md' -exec touch -t "$old" {} \; ; touch -t "$old" "$P/coordination/lead-log.md"
bash "$B/report.sh" seat-1 NOTE "waiting for review" -m "DONE posted" >/dev/null
check 'bash "$B/lead.sh" status | grep -q "DEAD?"' "lead DEAD? when silent past DEAD_MIN with work waiting"
t0=$(date +%s); bash "$B/lead.sh" standby 30 1; rc=$?; t1=$(date +%s); check '[ $rc = 0 ] && [ $((t1-t0)) -lt 15 ]' "standby wakes (exit 0) on DEAD? within $((t1-t0))s"
m="$(bash "$B/lead.sh" takeover --reason "lead-log.md 3h old, seat-1 waiting" --desc "standby B")"; check '[ "$m" = lead ]' "standby takes over"
check '[ -d "$P/coordination/locks/lead.lock/takeover-1.lock" ] && grep -q "TAKEN OVER" "$P/coordination/lead-log.md"' "nested lead takeover lock + log"
check 'grep -q "Lead session replaced" "$P/coordination/inbox/seat-1.md"' "takeover notes every inbox"
check 'bash "$B/lead.sh" status | grep -q ALIVE' "new lead reads ALIVE"
printf 'LABEL_1="backend-lead"\n' >> "$P/coordination/cowork.conf"
check 'bash "$B/status.sh" | grep -q "seat-1=backend-lead"' "LABEL_N shown in status"
echo "== recursion: layers, node.sh, grow, tree"
T="$S/tree"; "$KIT/cowork" init "$T" --layers 2,2 --territories "src:tests" >/dev/null; rc=$?
check '[ $rc = 0 ] && [ -f "$T/coordination/teams/seat-2/teams/.gitkeep" ] || [ -d "$T/coordination/teams/seat-2/bin" ]' "init --layers 2,2 scaffolds nested teams"
check '[ "$(find "$T/coordination" -name PROTOCOL.md | wc -l | tr -d " ")" = 3 ]' "2,2 tree has 3 nodes"
check '! grep -rl "@@" "$T/coordination" --include=*.md | grep -q .' "no unrendered placeholders anywhere in the tree"
check 'grep -q "coordination/teams/seat-2/PROTOCOL.md" "$T/coordination/teams/seat-2/prompts/seat-boot.md"' "nested seat-boot points at its own PROTOCOL.md"
check 'grep -q "seat-2. of the team above at .coordination." "$T/coordination/teams/seat-2/prompts/node-boot.md"' "node-boot names slot above and parent dir"
check '[ ! -f "$T/coordination/prompts/node-boot.md" ] && [ ! -f "$T/coordination/teams/seat-2/prompts/lead-boot.md" ]' "top has lead-boot, nested has node-boot"
NB="$T/coordination/teams/seat-2/bin"; TB="$T/coordination/bin"
check '[ -f "$T/coordination/teams/seat-2/PLAN.md" ] && [ -f "$T/coordination/teams/seat-2/prompts/node-standby.md" ] && [ ! -f "$T/coordination/teams/seat-2/prompts/lead-standby.md" ]' "nested team gets a PLAN.md stub and node-* prompts"
check 'bash "$TB/doctor.sh" >/dev/null 2>&1' "fresh scaffold is healthy before territories exist"
check 'bash "$NB/status.sh" | head -1 | grep -q "node seat-2"' "nested status.sh knows its node path"
check 'bash "$NB/status.sh" | head -1 | grep -q "ROOT=$T\$"' "nested team resolves ROOT to the project root"
mkdir -p "$T/src" "$T/tests"
bash "$TB/dispatch.sh" seat-2 "T0 — landed before the node booted" -m "x" >/dev/null
out="$(bash "$NB/node.sh" boot --desc "node B")"; rc=$?
check '[ $rc = 0 ] && echo "$out" | grep -q "above: claimed seat-2"' "node.sh boot claims its fixed slot above"
check 'echo "$out" | grep -q "T0 — landed before the node booted"' "node.sh boot prints the inbox above (pending dispatch visible)"
check '[ -f "$T/coordination/locks/seat-2.lock/inbox-seen" ]' "node.sh boot records the inbox above as seen"
bash "$NB/node.sh" watch 15; rc=$?; check '[ $rc = 4 ]' "watch after boot does not re-fire on the already-read dispatch (exit 4)"
bash "$NB/node.sh" status >/dev/null; rc=$?; check '[ $rc = 0 ]' "node.sh status exits 0 on a leaf node"
check '[ -d "$T/coordination/locks/seat-2.lock" ] && [ -d "$T/coordination/teams/seat-2/locks/lead.lock" ]' "slot lock above + lead lock below"
check 'grep -q "^## Claimed .*node seat-2" "$T/coordination/outbox/seat-2.md"' "claim announced in the outbox above"
rc=0; bash "$NB/node.sh" boot >/dev/null 2>&1 || rc=$?; check '[ $rc = 2 ]' "second node boot refused (slot above held)"
check '[ ! -d "$T/coordination/locks/seat-1.lock" ]' "node boot never takes a different slot than its own"
check 'bash "$NB/node.sh" status | grep -q "above: seat-2 of coordination"' "node.sh status shows the link above"
bash "$NB/node.sh" inbox --quiet
( bash "$NB/node.sh" watch 60; echo "nw=$?" > "$S/nw.out" ) &
sleep 2; bash "$TB/dispatch.sh" seat-2 "T1 — milestone for node" -m "decompose me" >/dev/null
i=0; while [ ! -f "$S/nw.out" ] && [ $i -lt 40 ]; do sleep 1; i=$((i+1)); done
check '[ "$(cat "$S/nw.out" 2>/dev/null)" = "nw=10" ]' "node.sh watch exits 10 when the inbox above changes (${i}s)"
check 'bash "$NB/node.sh" inbox | grep -q "T1 — milestone for node"' "node.sh inbox reads the inbox above"
bash "$NB/node.sh" report T1 IN_PROGRESS -m "decomposing" >/dev/null
check 'grep -q "^## T1 — IN_PROGRESS" "$T/coordination/outbox/seat-2.md"' "node.sh report appends to the outbox above"
check 'bash "$TB/status.sh" | grep seat-2 | grep -q "T1(in progress)"' "top status sees the node's task in progress"
( bash "$NB/node.sh" watch 60; echo "nw2=$?" > "$S/nw2.out" ) &
sleep 2; bash "$NB/claim.sh" --desc "leaf" >/dev/null; bash "$NB/report.sh" seat-1 HEARTBEAT -m "hi" >/dev/null
i=0; while [ ! -f "$S/nw2.out" ] && [ $i -lt 40 ]; do sleep 1; i=$((i+1)); done
check '[ "$(cat "$S/nw2.out" 2>/dev/null)" = "nw2=0" ]' "node.sh watch exits 0 when an outbox below changes (${i}s)"
# tie: a below change pre-empted by an above change is not lost
bash "$NB/report.sh" seat-1 NOTE "below moved" -m "x" >/dev/null; sleep 1; bash "$TB/dispatch.sh" seat-2 "Note — above moved" -m "y" >/dev/null
bash "$NB/node.sh" watch 15; rc1=$?; bash "$NB/node.sh" inbox --quiet; bash "$NB/node.sh" watch 15; rc2=$?
check '[ $rc1 = 10 ] && [ $rc2 = 0 ]' "watch: above wins the tie (10), the below change is kept for the next call (0) — got $rc1/$rc2"
bash "$NB/node.sh" watch 15; rc3=$?; check '[ $rc3 = 4 ]' "after both were seen, watch times out (4)"
# a node working upward (outbox above fresh) is not dead below, even with its team's log stale
touch -t "$old" "$T/coordination/teams/seat-2/lead-log.md"; bash "$NB/node.sh" report T1 HEARTBEAT -m "writing the integration request" >/dev/null 2>&1 || bash "$NB/node.sh" report HEARTBEAT -m "writing the integration request" >/dev/null
check 'bash "$NB/lead.sh" status | grep -q ALIVE' "node's upward writes count as lead activity below"
bash "$NB/node.sh" heartbeat -m "both ways" >/dev/null
check 'grep -q "^## Heartbeat" "$T/coordination/outbox/seat-2.md" && grep -q "^## Heartbeat" "$T/coordination/teams/seat-2/lead-log.md"' "node.sh heartbeat writes above and below"
check 'bash "$NB/doctor.sh" >/dev/null 2>&1' "nested doctor healthy"
check 'bash "$TB/doctor.sh" | grep -q "team below: seat-2"' "top doctor lists teams below"
( cd "$T" && "$KIT/cowork" grow seat-1/seat-1 --seats 3 >/dev/null ); rc=$?
check '[ $rc = 0 ] && [ -f "$T/coordination/teams/seat-1/teams/seat-1/inbox/seat-3.md" ]' "cowork grow adds a third layer under a leaf"
check '( cd "$T" && "$KIT/cowork" tree | grep -q "^    seat-1/seat-1  \[" )' "cowork tree prints the third layer"
check 'bash "$T/coordination/teams/seat-1/teams/seat-1/bin/status.sh" | head -1 | grep -q "node seat-1/seat-1"' "depth-3 node path"
rc=0; ( cd "$T" && "$KIT/cowork" grow seat-1/seat-9 >/dev/null 2>&1 ) || rc=$?; check '[ $rc != 0 ]' "grow refuses a slot the parent does not have"
rc=0; ( cd "$T" && "$KIT/cowork" --node "../../etc" status >/dev/null 2>&1 ) || rc=$?; check '[ $rc = 1 ]' "--node with a bad path exits 1 cleanly"
mkdir -p "$T/coordination/teams/seat-1-backup"; check '( cd "$T" && "$KIT/cowork" tree | grep -qv "seat-1-backup" )' "tree ignores non-numeric team dir names"
cp -R "$T/coordination/teams/seat-1/teams/seat-1" "$T/coordination/teams/seat-1/teams/seat-7" 2>/dev/null
check 'bash "$T/coordination/teams/seat-1/bin/doctor.sh" | grep -q "orphaned team"' "doctor warns about an orphaned teams/seat-7"
check 'bash "$T/coordination/teams/seat-1/bin/doctor.sh" | grep -q "identical to its parent"' "doctor warns when a nested TERRITORIES equals the parent's"
# node takeover in one command: kill the node's evidence, then boot --takeover from a 'new session'
oldt="$(date -v-3H '+%Y%m%d%H%M' 2>/dev/null || date -d '3 hours ago' '+%Y%m%d%H%M')"
touch -t "$oldt" "$T/coordination/outbox/seat-2.md" "$T/coordination/teams/seat-2/lead-log.md"; find "$T/coordination/teams/seat-2/inbox" -name '*.md' -exec touch -t "$oldt" {} \;
bash "$T/coordination/teams/seat-2/bin/report.sh" seat-1 NOTE "waiting" -m "x" >/dev/null
out="$(bash "$NB/node.sh" boot --takeover --reason "node silent 3h, work waiting" --desc "successor")"; rc=$?
check '[ $rc = 0 ] && echo "$out" | grep -q "took over seat-2" && echo "$out" | grep -q "took over the lead lock"' "node.sh boot --takeover takes the slot above then the lead lock below"
check '[ -d "$T/coordination/locks/seat-2.lock/takeover-1.lock" ] && [ -d "$T/coordination/teams/seat-2/locks/lead.lock/takeover-1.lock" ]' "both takeover locks exist"
check 'grep -q "Lead session replaced" "$T/coordination/teams/seat-2/inbox/seat-1.md"' "node takeover notes the team below"
printf 'MARK\n' >> "$T/coordination/teams/seat-1/bin/status.sh"; "$KIT/cowork" update "$T" >/dev/null
check '! grep -q "^MARK" "$T/coordination/teams/seat-1/bin/status.sh"' "cowork update refreshes every node"
check 'grep -q "coordination/teams/seat-1/teams/seat-1/PROTOCOL.md" "$T/coordination/teams/seat-1/teams/seat-1/prompts/seat-boot.md"' "update re-renders nested prompts with the right paths"
check '( cd "$T/src" && "$KIT/cowork" --node seat-2 status | head -1 | grep -q "node seat-2" )' "cowork --node proxies into a nested team"
check 'grep -q "coordination/\*\*/locks" "$T/.gitignore"' "gitignore covers locks at every depth"
echo "== kit CLI"
check '"$KIT/cowork" prompts | grep -q "STATUS: DISMISSED"' "cowork prompts prints the seat one-liner"
echo "# local edit" >> "$P/coordination/PROTOCOL.md"; printf 'MARK\n' >> "$P/coordination/bin/status.sh"
"$KIT/cowork" update "$P" >/dev/null
check '! grep -q "^MARK" "$P/coordination/bin/status.sh"' "cowork update refreshes bin/"
check 'grep -q "up to 2 Claude Code sessions" "$P/coordination/LEAD.md"' "cowork update re-renders LEAD.md with the project's real SEATS"
check '[ -f "$P/coordination/prompts/seat-boot.md" ] && [ -f "$P/coordination/prompts/lead-resume.md" ]' "prompts are copied into the project"
check '"$KIT/cowork" --help | grep -q "cowork init" && ! "$KIT/cowork" --help | grep -q "^set -u"' "cowork --help prints only the header"
check '! bash "$B/claim.sh" --help | grep -q "common.sh"' "claim.sh --help prints only the header"
rc=0; "$KIT/cowork" init "$S/escape" --territories ".." >/dev/null 2>&1 || rc=$?; check '[ $rc != 0 ]' "init refuses a territory outside the project"
check 'grep -q "# local edit" "$P/coordination/PROTOCOL.md"' "cowork update leaves PROTOCOL.md alone"
check '[ -f "$P/coordination/LESSONS.md" ] || [ ! -f "$KIT/LESSONS.md" ]' "cowork update copies LESSONS.md when the kit has it"
check 'bash "$B/doctor.sh" >/dev/null 2>&1' "doctor still healthy after update"
echo
echo "$pass passed, $failn failed  (scratch: $S)"
[ "$failn" = 0 ]
