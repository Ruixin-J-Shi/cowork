# cowork — lead/seat coordination for parallel Claude Code sessions

One **lead** session plans, specifies, reviews, integrates and runs git. Any number of **seat**
sessions, started in the same directory, implement. It recurses: a seat can be a **node** that runs a
team of its own (`--layers 3,2`), to any depth, with the same files and rules at every level. Nothing talks over a network: every message is a
Markdown file under `coordination/`, every wake-up is a file-mtime watcher, every slot claim is an
atomic `mkdir`. Sessions die (provider limits, closed laptops) and are replaced by takeover; the repo,
not any session, is the memory.

This kit is the protocol distilled from a real three-day, four-session build (see `examples/` and
`LESSONS.md`), packaged so the next project starts with it in one command.

```
git clone https://github.com/Ruixin-J-Shi/cowork.git && cd cowork        # any location works
./cowork init ~/code/myproject --seats 3 --territories "src:tests"        # one team
./cowork init ~/code/myproject --layers 3,2 --territories "src:tests"     # 3 nodes × 2 seats
```

Put `cowork` on your PATH (`QUICKSTART.md` §0) and drop the `./`; the kit resolves its own location.

That copies a **self-contained** `coordination/` into the project — scripts, protocol, lead playbook —
plus a `PLAN.md` and `CONVENTIONS.md` if absent. The project never depends on this kit again.

## The mental model

```
                 ┌──────────── LEAD session ────────────┐
                 │ PLAN.md · specs · review gate · git     │
                 └──┬───────────▲──────────────────▲───────┘
   writes inbox/seat-N.md     │ reads outbox/*   │ lead-watch.sh (bg) wakes on outbox change
                 ┌──▼────┐  ┌───┴───┐          ┌───┴───┐
                 │seat-1│  │seat-2│   ...   │seat-N│   each: claim.sh → loop{ read inbox, work,
                 └────────┘  └────────┘          └────────┘         report.sh, watch.sh (bg) }
   locks/seat-N.lock (atomic mkdir; takeover = nested mkdir)   outbox = append-only log + artifacts/
```

- **Inbox** (`coordination/inbox/seat-N.md`): written only by the lead. Task blocks `## T<n> — title`,
  reviews, rulings, all-hands. A `STATUS:` line at the top (ACTIVE / PAUSED / DISMISSED).
- **Outbox** (`coordination/outbox/seat-N.md`): written only by that seat, append-only.
  `## T<n> — IN_PROGRESS|DONE|BLOCKED|RESUMED <ts>`, heartbeats, incidents, notes to siblings.
- **Ownership, not worktrees**: every task block says which files it may write; a seat that needs
  another file reports BLOCKED and the lead re-assigns ownership explicitly.
- **Liveness by evidence**: a working seat writes a line every 30 min; silence past that gets a nudge;
  a stale outbox + silent territory + unacknowledged task = dead, and the slot can be taken over.
- **Hard rules** bind lead and seats alike: nothing outside the project, no `rm -rf` in ad-hoc
  shell (deletion = `mv` to `coordination/trash/`), seats never write through git, slips are self-reported.

## Layout of this kit

| Path | What |
|---|---|
| `cowork` | CLI: `init --layers`, `grow`, `tree`, `update`, `prompts`, and proxies for every `bin/` script (`--node seat-2/seat-1` targets a nested team) |
| `templates/coordination/` | what `init` copies: `PROTOCOL.md` (seats), `LEAD.md` (lead), `bin/*.sh`, `hooks/ntfy-hook.sh`, `cowork.conf`, `registry.md` |
| `templates/project/` | `PLAN.md`, `CONVENTIONS.md`, `.gitignore` lines seeded into the project root |
| `prompts/` | the exact text to paste into a lead / seat / resuming-lead / standby-lead session (copied into `coordination/prompts/` by `init`) |
| `skill/` | a Claude Code skill (`/cowork …`) — optional; from the clone: `ln -s "$PWD/skill" ~/.claude/skills/cowork` |
| `examples/clawllege/` | verbatim excerpts from the original run, one mechanism each |
| `LESSONS.md` | what the original run taught, incident by incident, and the rule each produced |
| `ARCHITECTURE.md` | why files rather than an MCP server or A2A, when to add each, and a verified survey of existing projects |
| `TREE.md` | standby lead (failover), recursion (nodes to any depth), parallel teams with one integrator — and the shape to refuse |
| `tests/smoke.sh` | end-to-end test of the scripts (init → claim → dispatch → watch → report → takeover → dismiss → doctor) |

`QUICKSTART.md` walks a new project from zero to a running team.

## The scripts (all in `<project>/coordination/bin/`, bash 3.2+, macOS and Linux)

| Script | Who | Does |
|---|---|---|
| `claim.sh` | seat | claim the first free slot atomically; `--takeover seat-N --reason …` for a dead one |
| `inbox.sh` | seat | print the inbox and record which version was read (what makes the watch race-free) |
| `report.sh` | seat | append `IN_PROGRESS / DONE / BLOCKED / RESUMED`, `HEARTBEAT`, `INCIDENT`, `ACK`, `NOTE` to its own outbox |
| `watch.sh` | seat | block until the inbox changes since the last `inbox.sh` read; exit 4 on timeout (run as a background task) |
| `dispatch.sh` | lead | append a task / ruling / note to an inbox, `--all` broadcast, `--status`, `--next-id` |
| `lead-watch.sh` | lead | block until an outbox or the registry changes; exit 3 on stall (run as a background task) |
| `lead.sh` | lead / standby | `claim`, `heartbeat`, `note`, `status`; `standby` blocks until the lead is dead by evidence; `takeover --reason` |
| `node.sh` | node | `boot` (slot above + lead lock below), `watch` (exit 10 above / 0 below), `inbox`, `report`, `heartbeat` upward, `status` |
| `status.sh` | anyone | slots, locks, STATUS, write ages, open tasks, liveness verdicts, territory activity |
| `doctor.sh` | anyone | structure, config, stale locks, gitignore coverage, hooks |

Body text for `dispatch.sh` / `report.sh` is always explicit: `-m "text"`, `-f file`, or `-` with a heredoc.

## License

MIT — see `LICENSE`.
