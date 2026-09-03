---
name: cowork
description: Lead/seat coordination for parallel Claude Code sessions in one project directory (file-based inbox/outbox, atomic slot locks, watch loops)
disable-model-invocation: true
---

# /cowork

Kit root: `~/Desktop/cowork`. A project is "initialised" when it has `coordination/bin/common.sh`.

Parse the argument and take the matching branch (`init`, `lead`, `seat`, `node`, `standby`, `grow`, `tree`, `status`, `doctor`, `resume`). With no argument, run `bash ~/Desktop/cowork/cowork --help` and show the output.

## `init [--seats N | --layers 3,2] [--project NAME] [--territories "a:b"]`

Run `bash ~/Desktop/cowork/cowork init "$PWD" <the given options>`. Then open `PLAN.md` and fill the ownership map and shared-resource partition from what you know of the project (ask for what you cannot infer). Done when `bash coordination/bin/doctor.sh` prints `healthy`.

## `lead`

Read `coordination/LEAD.md` and follow it exactly from **Boot**, as the LEAD session. Done only when the human dismisses the team.

## `seat`

Read `coordination/PROTOCOL.md` and follow it exactly: claim a slot per Step 1, run the work loop in Step 2 indefinitely. Hard rules: never touch anything outside this project folder, never run destructive commands, never write through git (read-only git is fine), only write files assigned to you. Done only when the inbox says `STATUS: DISMISSED`.

## `standby [<node-path>]`

Top (no path): follow `coordination/prompts/lead-standby.md` exactly. A node (`standby seat-2`): follow `coordination/teams/seat-2/prompts/node-standby.md` exactly (it takes over both sides with `node.sh boot --takeover`). Done only when the team is dismissed.

## `node <path>` (e.g. `node seat-2`)

Read `coordination/teams/<path>/prompts/node-boot.md` and follow it exactly: you are the lead of that team and a seat of the team above; boot with `node.sh boot`, then loop on `node.sh watch` (exit 10 = act above as a seat, 0 = act below as a lead). Done only when your inbox above says `STATUS: DISMISSED`.

## `grow <path> [--seats N]` · `tree`

Run `bash ~/Desktop/cowork/cowork grow <path> …` / `bash ~/Desktop/cowork/cowork tree` from the project and report the output.

## `status [<node-path>]` · `doctor [<node-path>]` · `tree`

Run `bash ~/Desktop/cowork/cowork [--node <path>] status` / `doctor`, or `cowork tree` for every node, and report the output verbatim, then say in one line what needs the human (a dead slot, a stall, a structural FAIL).

## `resume [<node-path>]`

A node (`resume seat-2`): follow `coordination/teams/seat-2/prompts/node-resume.md` exactly. Top: as LEAD after a restart: read `coordination/LEAD.md`, `PLAN.md`, `CONVENTIONS.md`, `coordination/LESSONS.md`, the tails of every inbox and outbox, `status.sh` and `doctor.sh`; reconstruct accepted / open / dead; write a state-of-the-world note and fresh `STATUS: ACTIVE` into each inbox; arm `lead-watch.sh`; continue the loop.
