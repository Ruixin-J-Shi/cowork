# Quickstart — from zero to a running lead/seat team

Time: about ten minutes, most of it writing `PLAN.md`.

## 0. Once per machine (optional)

Clone the kit anywhere; nothing in it depends on where it lives.

```bash
git clone https://github.com/Ruixin-J-Shi/cowork.git && cd cowork
ln -s "$PWD/cowork" /usr/local/bin/cowork     # or any directory on your PATH
ln -s "$PWD/skill" ~/.claude/skills/cowork    # enables /cowork in Claude Code
bash tests/smoke.sh                           # 162 checks; proves the scripts work here
```

Phone notifications (optional): `brew install ntfy`, then follow the header of
`templates/coordination/hooks/ntfy-hook.sh`.

## 1. Scaffold the project

```bash
cowork init ~/code/myproject --seats 3 --project myproject --territories "src:tests:docs"
cowork init ~/code/myproject --layers 3,2 …        # or a tree: 3 nodes, each with 2 seats
```

`--territories` lists where seats will write (relative to the project); it drives stall detection and
liveness. Then set the per-slot lines in `coordination/cowork.conf` to match the ownership map
(`TERRITORY_1="src"`, `TERRITORY_2="tests"`), so a dead seat cannot hide behind a busy sibling.
Use `cowork update <dir>` later to refresh scripts and playbooks without touching logs.

## 2. Write `PLAN.md`

The lead reads it first and every seat infers intent from it. Fill in: the one-liner, locked
decisions, the **ownership map** (which directories each seat owns), shared resources to partition
(ports, build dirs, databases — one per seat), non-negotiables, milestones. Terse is fine; it grows.

If the project has contracts (schema, API spec, interface docs), put them in a lead-owned directory
and name them in the plan. Tasks point at contracts; seats propose changes to them in their outbox.

## 3. Boot the lead

```bash
cd ~/code/myproject && claude
```

Paste `prompts/lead-boot.md` (or `cowork prompts`). Use the strongest model here; it spends its tokens
on specs, reviews and rulings. It will write `STATUS: ACTIVE` into each inbox, dispatch the first tasks,
and arm `lead-watch.sh` as a background task.

## 4. Boot the seats

One terminal per seat, same directory, same command; paste `prompts/seat-boot.md`:

> Read `coordination/PROTOCOL.md` and follow it exactly. You are a NODE holding a SEAT in the team at
> `coordination`, under that team's lead. Claim a seat per Step 1, then run the work loop in Step 2
> indefinitely. Hard rules: never touch anything outside this project folder, never run destructive
> commands, never write through git (no stage, commit, stash, checkout, reset or push — read-only git is
> fine), only write files assigned to you. Do not end your session until your inbox says STATUS: DISMISSED.

Seats can run on a cheaper model. They claim `seat-1`, `seat-2`, … in order, automatically.
Permission mode is your call: the hard rules in PROTOCOL.md are what make a low-friction mode
tolerable, and the incident rule is the backstop.

## 4b. Optional: a standby lead

Open one more terminal in the same directory and paste `coordination/prompts/lead-standby.md`. It
waits silently and takes over only when the lead is dead by evidence. Relaunch a new standby after a
takeover.

## 4c. Optional: a tree of teams

With `--layers 3,2`, each top-level slot is a **node**: one session that is `seat-N` of the top team
and the lead of `coordination/teams/seat-N/`. Boot each node with that directory's
`prompts/node-boot.md`, its seats with its `prompts/seat-boot.md`; `cowork tree` shows everything;
`cowork grow seat-2 --seats 3` adds a team under a leaf later. Read `TREE.md` §2 first.

## 5. Watch

```bash
coordination/bin/status.sh        # slots, open tasks, liveness verdicts
coordination/bin/doctor.sh        # anything structurally wrong
tail -f coordination/outbox/*.md  # the live log
```

You talk to seats only through the lead (it marks your directives "from the human via lead").
When a session dies, relaunch a Claude Code session with the seat prompt: it takes over the dead slot
atomically and audits the predecessor's work before continuing.

## 6. Finish

The lead dismisses: `coordination/bin/dispatch.sh seat-N --status DISMISSED`. Each seat writes a
session summary and ends. Commit `coordination/` (inbox/outbox/registry are the build log; locks and
trash are gitignored) — the next machine restores everything from the repo.

## Moving to another machine

Clone the repo. `coordination/locks/` is empty on a fresh clone, so claims are clean. Paste
`coordination/prompts/lead-resume.md` (the project carries its own copy of every prompt) into the new
lead; it reconstructs state from the logs and writes fresh STATUS lines before seats boot. Seats
boot from `coordination/prompts/seat-boot.md`. Secrets travel by hand, never by repo.
