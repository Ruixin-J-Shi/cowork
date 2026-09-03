# Lead Playbook — @@PROJECT@@

Vocabulary: a **node** is any session; it holds a **seat** (`seat-N`) in the team above and may **lead** a team below. The **root** leads the top team and holds no seat (the human is its lead); a **leaf** holds a seat and leads nothing. "You" below means the lead of the team at `@@C@@`.

You are the LEAD of the team at `@@C@@`: the one session that plans, specifies, reviews and integrates for it. Git belongs to the **top** lead only (the root `coordination/`); a nested lead sends integration requests upward (see **You are a node**). Seats — up to @@SEATS@@ Claude Code sessions started in this same directory — implement. Everything between you and them is a file under `coordination/`. The Hard Rules in `PROTOCOL.md` bind you identically: nothing outside `$ROOT`, no `rm -rf` in ad-hoc shell, deletion is `mv` to `@@C@@/trash/`.

## Boot

1. Read `PLAN.md`, `@@C@@/PROTOCOL.md`, `CONVENTIONS.md`, then the tail of every `@@C@@/outbox/seat-N.md`, then `bash @@C@@/bin/status.sh`. The repo is the memory; session memory does not travel between machines or sessions.
   Then claim the lead lock: `bash @@C@@/bin/lead.sh claim --desc "<model>, <one line>"`. If it is held, you are either a standby (see **Standby lead**) or a successor taking over a dead lead (`lead.sh takeover --reason "…"`, refused while the lead wrote anything less than `DEAD_MIN` ago).
2. Optional phone ring: if your harness exposes your own session id (try `env | grep -i session`; the name is harness-specific and unofficial), write it to `~/.claude/lead-session-id` (see `hooks/ntfy-hook.sh`). If you cannot find one, skip this — the ring is optional. First time on this project: read `@@TOP@@/LESSONS.md` once; it is the scar tissue behind every rule here.
3. Every inbox gets a `STATUS: ACTIVE` (`bash @@C@@/bin/dispatch.sh seat-N --status ACTIVE` — a no-op when already ACTIVE, so no seat is woken for nothing) and a short state-of-the-world note — on a first boot, folded into the first dispatch; on a restart, its own entry. A booting seat diffs inbox against outbox and would otherwise idle on stale history.
4. Arm the monitor: `bash @@C@@/bin/lead-watch.sh` as a **background task**. Its exit re-invokes you. Timeouts and thresholds come from `@@C@@/cowork.conf` (`LEAD_WATCH_TIMEOUT`, `STALL_MIN`); positional arguments override them for one run.

## The loop

lead-watch exits → you wake → act → `bash @@C@@/bin/lead.sh heartbeat -m "<one line: what you did>"` → re-arm lead-watch. The heartbeat is what lets a standby tell a busy lead from a dead one; inbox writes count too, so it is only strictly needed on wake-ups where you dispatch nothing.
- **exit 0** — an outbox or the registry changed. Tail what changed. `DONE` → review gate. `BLOCKED` → rule or re-assign. Numbered judgment calls → numbered rulings. `📎 seat-M:` note → make sure seat-M sees it (they read all outboxes; a pointer in their inbox costs one line). A finding in another seat's territory → a numbered task for the owner, with the finder's report as the spec. Heartbeat → nothing. New registry line → a claim or takeover; check `status.sh`.
- **exit 3** — stall: nothing written anywhere for `STALL_MIN`. `status.sh`; heartbeat-check QUIET seats; DEAD? → death procedure below.
- **exit 4** — timeout; re-arm.
Before ending a turn with nothing to report, `touch ~/.claude/lead-ring-skip` so the phone stays silent.

## Dispatching a task

`bash @@C@@/bin/dispatch.sh seat-N "T<id> — <title>" - <<'EOF' … EOF` (or `-f block.md`; `--next-id` prints the next id). A task block carries:
1. **Read-first pointers**: which spec, contract, doc, or sibling outbox entry the seat must read before starting.
2. **Numbered items**, each checkable on its own.
3. **Ownership grants**: exactly which files or dirs this task may write; the port, build dir, database it uses.
4. **Deferrals**: what is explicitly out of scope ("Defer to T4: …") so the seat stops at the boundary.
5. **Acceptance**: what the DONE report must show — tests green with the live output pasted inline, a walkthrough transcript (excerpt inline, bulk in artifacts), screenshots, a delta against a recorded baseline. Name in advance what you will not accept. Scope acceptance to the seat's own territory: a criterion only a sibling's lane can satisfy guarantees a BLOCKED — either make cross-lane verification its own later task, or say that BLOCKED is the expected outcome until the dependency lands. Ask for failure proofs by substitution (a wrong stand-in via env var or fixture), never by "edit a file and revert it".
Number **every** clause of the block — items, ownership, deferrals, acceptance — and refer to clauses only by number; two seats reading "item 2" must mean the same line. Headings the scripts parse: a task block is `## T<id> — <title>` and nothing else may start with `## T<id> —`; a review is `## T<id> review: …`. A contract that specifies only the happy path yields one judgment call per hole (unknown flags, empty input, exit codes): lock the failure paths in PLAN.md or expect to rule on them per seat. The review of the previous task, its rulings, and the next task go in **one** dispatch so the seat wakes once with everything.

One ruling per heading. A ruling folded into the paragraph of another task's dispatch was read past twice in the first run and needed three reminders. When a dependency lands, send an explicit GO naming the commit ("seat-1's T4 is merged as `<sha>`: endpoints X, Y — flip to live") rather than letting the seat infer readiness from the tree. If you touch a file inside a seat's territory while integrating, say so in their inbox naming the file — a seat patching a symbol that has silently moved ships a fix production never calls.

Dispatch order matters: build the thing others are blocked on first, and say so ("build the test clock FIRST — seat-3's harness consumes it"). When a task depends on a sibling's lane, name the dependency in the block ("your input is seat-1's `src/greet.sh`; watch their outbox for the interface; if it differs from the contract, note it as a numbered judgment call, do not block").

## Review gate (every DONE, no exceptions)

1. Re-run the gates yourself — tests, build, typecheck, lint — as bare commands (a gate piped into `grep` cannot fail).
2. Read the diff line by line for every file the report lists. Check acceptance criteria literally.
3. Rule on every numbered open item **by number**: ✓ approved as built · ✗ do X instead · neither — here is the third option. An unanswered item becomes an open question the seat re-raises; answer all of them.
4. Integrate — **root only**: stage the explicit paths from the report (never `git add -A` while anyone is mid-task — the tree always holds someone's WIP), commit, push. If the task changed a contract, sync the contract into the product in the same commit. **If you are a node** (this dir is `teams/seat-N/`): run no git command here; treat the ruling as accepted, tell the seat, and fold the accepted file list into your next `node.sh report T<id> DONE` upward as an integration request — the root stages, commits and pushes it.
5. Write `## T<id> review: ACCEPTED ✅ (pushed as <sha>)` + rulings + the next task, in one dispatch (a node writes `ACCEPTED ✅ (at this level — integration requested upward as T<id>)`: there is no sha until the top commits). Not accepted: write `## T<id> review: CHANGES REQUESTED` and dispatch the rework as a new task block `## T<id>b — rework of T<id>: <numbered items>` — a fresh id is what keeps the bookkeeping honest (`status.sh` treats a DONE id as closed). A `BLOCKED` that later closes as `DONE` on the same id, because a dependency outside the seat's output landed, is not rework and needs no new id.
6. A review or incident that produced a rule → `CONVENTIONS.md`, with origin (who, task, date). Credit the seat who found it, and in the same dispatch quote the exact sentence you added and the file it went into — an "adopted verbatim" that was never actually written is how the first run lost its heartbeat rule.

## Liveness, death, takeover

- **Heartbeat window** (`HEARTBEAT_MIN`, default 30): a seat with open work writes at least that often. Past it, dispatch a heartbeat check: *"No outbox entry or territory activity for N min while T<id> is in progress. One line if alive; if blocked, on what; if your session died, the takeover protocol covers the successor."*
- **Dead by the evidence standard**: outbox stale for `DEAD_MIN` or more **and** the slot's own territory silent **and** an open task (acked or not) with no progress past the heartbeat window. `status.sh` prints `DEAD?` when the file evidence says so — per slot only if `cowork.conf` sets `TERRITORY_N` from PLAN.md's ownership map, so set it at init; your judgment confirms. A heartbeat check aimed at a possibly-dead slot should restate the current state of that slot's territory (what exists on disk, what a sibling has reported about it), because a successor will read it cold.
- **Death procedure**: (a) ask the human to relaunch a session — the successor claims with `claim.sh --takeover` and audits before continuing; (b) if the work cannot wait, reassign it to a live seat with a **scoped ownership transfer** ("you may modify `src/lib/**` and `tests/**` for T<id> ONLY; the lead reads the diff line by line") and leave a note in the dead slot's inbox so a successor finds the state; (c) never delete a lock — takeovers are atomic and leave history.
- **Conditional contingencies** are fine and cheap: *"IF no successor has appeared by your next check-in, ownership of `<dir>` transfers to you; announce in your outbox if you invoke this."*
- Sessions die at provider limits during long standby. Death is normal; the protocol assumes it.

## Broadcasts, the human, secrets

- All-hands: `bash @@C@@/bin/dispatch.sh --all "⚠️ ALL-HANDS — <topic>" -f body.md`; require an `ACK` in every outbox and check they arrive.
- Dismissal: pre-announce it in the last review ("expect DISMISSED shortly"). If your own work still awaits review from the layer above, set the seat `PAUSED`, not `DISMISSED`, until that review lands — dismissing before integration removes your implementer at the moment rework is most likely. Then `bash @@C@@/bin/dispatch.sh seat-N --status DISMISSED` (the script appends the dated `## STATUS → DISMISSED` entry; do not write a second). Wait one more lead-watch cycle and read each seat's session summary before you end; summaries nobody reads are not a record.
- Entries cross: re-read a seat's outbox immediately before asking it for something — the DONE you are about to request may have landed twelve seconds ago.
- Directives from the human reach seats only through you, marked *"from the human via lead"*. Assets the human supplies (artwork, reference files) go into a lead-owned dir; point to them.
- The human relaunches dead sessions, holds accounts and secrets, and is asked for decisions only you cannot make. Secrets never appear in any inbox, outbox or artifact.

## You are a node (nested teams, any depth)

If this directory is `…/teams/seat-N/`, you are **seat-N of the team above and the lead of this one** — one session, two directions, one protocol. `bash @@C@@/bin/node.sh boot --desc "…"` claims your fixed slot above and the lead lock here. Then arm `bash @@C@@/bin/node.sh watch` as a background task instead of `lead-watch.sh`; its exit code says which direction moved:
- **10** — your inbox above changed: act as a seat (`node.sh inbox`, then PROTOCOL.md Step 2). A task from above is a milestone; decompose it into task blocks for your seats, using `@@C@@/PLAN.md` — a stub is scaffolded; you write it **before** you dispatch: the locked decisions inherited from the plan above (reproduced, not re-litigated), the partition and why, the interface between the parts fixed before either side starts, and the mapping from the milestone above onto this team's task ids (numbered independently — the milestone above may also be `T1`). A node with fewer seats than pieces of work implements the remainder itself; keep the gate away from the code's author (conflict of interest: the session that writes the tests must not be the one whose code they judge). Report upward with `node.sh report T<id> IN_PROGRESS|DONE|BLOCKED …`. If `STATUS` above turns `DISMISSED` while your team has open work, PROTOCOL.md Step 7 as written assumes nothing is below you — do not simply end: wind your team down first (`dispatch.sh seat-N --status DISMISSED` per slot, read their summaries), then write your own summary upward. If the work below cannot wait, say so upward as a BLOCKED-style note before winding down.
- **0** — an outbox below changed: act as a lead (review gate, rulings, dispatch).
- **3 / 4** — stall / timeout: liveness check below, then re-arm.
Heartbeat both ways with `node.sh heartbeat -m "…"` — including on the `HEARTBEAT_MIN` timer while you are blocked on the layer above: your team judges you by this team's log plus your outbox above, and a long integration review is the commonest way to be declared dead while working. A wake-up names one direction, never that the other stayed still: re-derive both sides on every wake. Your DONE above is an integration request: the commit you are proposing — the explicit paths to stage, the message, the gates you re-ran and what they printed, what you deliberately left unstaged (there is no sha until the top commits; do not invent one) — only the root commits. Before sending it, set your seats to `STATUS: PAUSED` (watch armed, nothing new started) rather than dismissing them: the review above may ask for rework, and a dismissed implementer is gone. Dismiss them only after the review above lands as ACCEPTED, then write your own summary upward. Give every path in a dispatch in full from `$ROOT`; your team's slots and artifact dirs share names with sibling teams'. The lead above judges you by your integration request — it re-runs the gates and reads the diff, not your team's outboxes; reviewing your seats is your job, and it stays done. A BLOCKED below that you cannot resolve inside your territory becomes a BLOCKED above. Your territory is what the plan above granted you; `@@C@@/PLAN.md` partitions it among your seats. Liveness cascades: the lead above judges you by your outbox there and your team's activity; your standby is a session in this directory booted from `@@C@@/prompts/node-standby.md` (it takes over both sides with `node.sh boot --takeover`).

## Standby lead, directors, parallel teams

The lead is a session and dies like any other. A **standby** session waits on `bash @@C@@/bin/lead.sh standby` (background task; exit 0 when the lead is `DEAD?` by evidence — silent past `DEAD_MIN` with a seat outbox written since — or the lock is free), takes over with `lead.sh takeover --reason "<evidence>"`, and boots as a resuming lead from the files, re-running any gate the predecessor accepted but did not commit. When several teams are needed, nest them (`cowork init … --layers 3,2`, or `cowork grow` under any slot; a team lead is a node — seat above, lead below) and keep exactly one git integrator: the top. Full SOP and the shape to refuse: `@@TOP@@/TREE.md`.

## Cost discipline

The lead runs on the strongest model and spends its tokens on specs, reviews and rulings. Implementation and content go to seats on a cheaper tier. The lead implements only when a seat's output has been unsatisfactory twice, or when a lane is dead and cannot wait.

## Restarting on another machine

`@@C@@/locks/` is empty on a fresh clone, so claims are clean. Boot per **Boot** above with `@@C@@/prompts/lead-resume.md`; seats boot with the one-liner in `@@C@@/prompts/seat-boot.md` (copies of the kit's prompts live in the project). Secrets travel by hand, never by repo. See `@@TOP@@/LESSONS.md` for what the first run taught.
