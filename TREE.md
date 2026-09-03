# The tree — leads, seats, nodes: the three shapes that work, and the one that does not

The base protocol has one lead per `coordination/` directory: one writer per inbox, one integrator
for git, one session that reviews. That is an invariant, not a limitation. "Multiple leads" is sound
exactly when it preserves it — by nesting, by partitioning, or by succession.

| Shape | What it is | Preserves the invariant by |
|---|---|---|
| **Standby lead** | a second session that takes over when the lead dies | succession: one lead at a time, held by `locks/lead.lock` |
| **Nodes (recursion)** | every session is seat-N above and lead below; depth is a parameter | nesting: each `coordination/teams/seat-N/` has its own single lead |
| **Parallel teams, one integrator** | two or more teams in one repo without a director | partitioning territories at the team level; exactly one session runs git |
| ~~Two leads, one seat pool~~ | two sessions dispatching into the same inboxes | nothing — forbidden |

## 1. Standby lead (failover)

The lead is a single point of failure in the base protocol: sessions die at provider limits, and a
dead lead leaves DONE reports unreviewed and seats idling on watch. The fix mirrors what seats
already have — a lock, a log, a liveness rule, and takeover by evidence.

- **Lock**: the lead claims `coordination/locks/lead.lock` at boot (`bin/lead.sh claim`). A second
  session that tries gets the evidence printed and exit 2.
- **Log**: `coordination/lead-log.md`, append-only, written only by the lead: boot line, a heartbeat at
  every wake-up (`bin/lead.sh heartbeat -m "reviewed T3, dispatched T4"`), decisions worth keeping.
  Inbox writes count as lead activity too, so a busy lead never needs a separate heartbeat.
- **Liveness**: `status.sh` prints the lead row. `ALIVE` within `HEARTBEAT_MIN`; `QUIET` past it;
  `DEAD?` when the lead has written nothing for `DEAD_MIN` **and** a seat outbox has been written since
  the lead last wrote (work is waiting and nobody is reviewing). Idle silence with nothing waiting is
  not death.
- **Standby SOP**:
  1. Start a second session in the same directory; paste `coordination/prompts/lead-standby.md`. It
     reads `LEAD.md`, `PLAN.md`, `CONVENTIONS.md`, `LESSONS.md` — and then does nothing but wait:
     `bash coordination/bin/lead.sh standby` as a background task (exits 0 when the verdict is `DEAD?`
     or the lock is free; exit 4 on timeout → re-arm). It writes no file while waiting.
  2. On exit 0 it judges the same three facts a seat would (`lead.sh status`, inbox ages, what is
     waiting) and takes over: `bash coordination/bin/lead.sh takeover --reason "<evidence>"`. The
     takeover is a nested atomic `mkdir` — two standbys cannot both win — and it is refused while the
     lead wrote anything less than `DEAD_MIN` ago unless `--force`.
  3. The takeover appends to `lead-log.md` and the registry, and appends a one-line "Lead session
     replaced" note to every inbox so seats know rulings continue from a new session.
  4. The successor then boots per `LEAD.md` **Boot** as a resuming lead: reconstruct state from the
     inboxes and outboxes, never from the predecessor's memory; re-run the gates on anything the
     predecessor marked ACCEPTED but did not commit; write fresh `STATUS` lines; arm `lead-watch.sh`.
- **The human's part**: relaunch a standby after each takeover so there is always one waiting. The
  standby costs nothing while it waits (no writes, no tokens beyond the wake-ups).

What is not solved: a lead that dies *between* accepting a review and pushing the commit. The
successor detects it (working tree dirty, an `ACCEPTED` line without a sha) and redoes the gate; that
is why the review gate is idempotent — re-running tests and re-reading a diff costs minutes, not truth.

## 2. Recursion: every session is a node (any depth)

The clean structure is not "leads and seats" but **nodes**. A node is one session that is
`seat-N` of the team above and the lead of the team below. The top node has no team above (the
human is its lead); a leaf has no team below. The same two files, the same scripts, the same rules
apply at every depth — a lead accepts the seat protocol because it *is* a seat one level up.

```
coordination/                       ← top team: its lead is the top node (runs git)
  inbox/seat-1.md  outbox/seat-1.md   ← the link to node seat-1
  teams/seat-1/                   ← the team run by node seat-1 (it is lead here)
    inbox/seat-1.md …             ← its own seats (leaves, or nodes with teams/ of their own)
    teams/seat-1/teams/…          ← any depth
```

- **Position is the directory.** A coordination dir at `<parent>/teams/seat-N/` is the team of slot
  `seat-N` of `<parent>`. Nothing else encodes the tree; the scripts derive `above` and `below` from
  the path (`node.sh status` prints both).
- **Describe the tree as fan-outs per layer**: `cowork init <dir> --layers 3,2` gives a root with
  three nodes, each running two seats (ten sessions). `cowork grow seat-2 --seats 3` turns a leaf
  slot into a node later; `cowork tree` shows every node's lead and slot liveness.
- **One session, two loops.** A node boots with `node.sh boot` (claims its fixed slot above and the lead
  lock below), then waits on `node.sh watch`, one combined watcher whose exit code says which side moved:
  10 = the inbox above changed (act as a seat), 0 = an outbox below changed (act as a lead), 3 = the
  team stalled, 4 = timeout. `node.sh inbox`, `node.sh report`, `node.sh heartbeat` talk upward with the
  slot filled in; the ordinary `dispatch.sh`, `status.sh`, `lead.sh` run the team below.
- **Tasks flow down as milestones and come back up as integration requests.** A task block from above is
  decomposed by the node into task blocks for its seats; its DONE above is the commit it proposes: the
  exact files to stage, the message, the gates it re-ran, what it left unstaged (no sha exists until the top
  commits). Only the top node runs git — one working tree, one
  integrator, however deep the tree. (Large or remote teams: one worktree and branch per top-level node,
  merged by the top; territories are disjoint so merges are mechanical — and the top still performs every
  commit, reaching into each node's worktree over whatever channel the human sets up; a node never runs git
  in this shape either.)
- **Territories partition at every level.** The plan above grants a node a territory; the node's own
  `PLAN.md` (a stub is scaffolded in each team dir; the node writes it at boot) partitions it among its
  seats. Each team's `cowork.conf` starts with a copy of the parent's `TERRITORIES=`; scope it to what that
  node owns, or a sibling's writes silence its stall alarm (`doctor.sh` warns when it is still identical). A BLOCKED a node cannot resolve inside its territory becomes a
  BLOCKED above. Set `TERRITORY_N` in each team's `cowork.conf`; label slots that are nodes
  (`LABEL_2="frontend-node"`) so `status.sh` reads sensibly.
- **Liveness cascades.** The lead above judges a node by its outbox there and its team's activity;
  the node judges its own seats the usual way. A dead node is replaced by a standby in its team
  (booted from that team's `prompts/node-standby.md`) or by a new session — either runs
  `node.sh boot --takeover --reason "<evidence>"`, which takes the slot above first and the lead lock
  below second, so the record above shows who took the slot before the team below sees a new lead.
- **Dismiss leaves last.** A node sends its integration request upward with its seats `PAUSED`, not
  dismissed — rework may come back — and dismisses them only after the review above is ACCEPTED. When the
  top dismisses a node, the node dismisses its team first, reads their summaries, then writes its own.
- **Dispatch granularity is the design choice.** A node that writes seat-sized tasks for its own seats
  is doing its job; a root that writes seat-sized tasks for a node's seats has recreated a single
  lead with extra hops. Give nodes milestones and let them decompose.

## 3. Parallel teams, one integrator (no director)

Same layout as shape 2 without a session at the top: the human plays the top node. One team lead is
designated the **integrator** in the root `PLAN.md` and is the only session that runs git; the other
team leads send it integration requests through the root inbox/outbox pair (they still claim root
slots; the integrator writes their root inboxes). If nobody wants that role, each team works in its own worktree
and branch and the human merges. Either way, write down who integrates before the first task.

## 4. The shape to refuse

Two leads dispatching into the same seat inboxes breaks the single-writer rule: interleaved task
blocks, contradictory rulings, two review gates for one DONE, and no way for a seat to know which
lead's `STATUS` line is current. If two leads need the same people, split the people — each seat
has exactly one lead — or nest (shape 2). The scripts refuse a second `lead.sh claim` per directory
for this reason.

## What the scripts add

| Script | Purpose |
|---|---|
| `bin/lead.sh claim` | claim the lead lock; boot line in `lead-log.md`; refuses if held (with evidence) |
| `bin/lead.sh heartbeat` / `note` | the lead's own append-only log |
| `bin/lead.sh standby` | block until the lead is `DEAD?` by evidence (or unclaimed) |
| `bin/lead.sh takeover --reason` | nested atomic takeover with the `DEAD_MIN` guard; notes every inbox |
| `bin/lead.sh status` | one line: lock, activity age, verdict (also the first line of `status.sh`) |
| `cowork init … --layers 3,2` / `cowork grow seat-N` / `cowork tree` | scaffold, extend and inspect the tree |
| `bin/node.sh boot / status / watch / inbox / report / heartbeat` | the node's two-sided loop; `watch` exits 10 (above) or 0 (below) |
| `bin/claim.sh --slot seat-N` | claim a fixed slot (a node's slot above is fixed by its directory) |
| `LABEL_N` in `cowork.conf` | display labels for root slots that are team leads |

Tested by the kit's smoke suite (claim, heartbeat, refused takeover of a live lead, standby wake,
takeover by evidence, a 2,2 tree, node boot and two-sided watch, reporting upward, grow, tree-wide update). Not yet exercised in a live multi-session run: when you
first run a standby or a director for real, treat that run as a dry run and read the reports the way
`LESSONS.md` §16 did.
