# PLAN — @@PROJECT@@

> One-liner: <what this project is, in one sentence>

Status: <DECISIONS LOCKED · building · @@DATE@@>

## 0. Locked decisions

| Decision | Choice |
|---|---|
| <name> | <choice> |

Decisions here are settled. A seat that disagrees says so in its outbox with evidence; the lead rules; the table changes only by a lead edit.

## 1. Goal and why now

<two or three paragraphs>

## 2. The thing being built

<scope, actors, main flows — enough that a seat can infer intent when a task block is terse>

## 3. Ownership map (who writes where)

| Territory | Owner | Notes |
|---|---|---|
| `coordination/inbox/**`, `PLAN.md`, this map | lead | |
| `<dir>/**` | seat-1 | <e.g. backend> |
| `<dir>/**` | seat-2 | <e.g. frontend> |
| `<dir>/**` | seat-3 | <e.g. tests / harness / content> |

Any file not named above is lead-owned; a seat that needs one reports BLOCKED naming it. Mirror this table in `coordination/cowork.conf` as `TERRITORY_N` so liveness is judged per slot.

Shared resources that need partitioning (one line each): dev-server ports, build output dirs, databases, caches.

## 4. Non-negotiables

<security, data, or safety constraints every task inherits>

## 5. Milestones

- M0: coordination live (this file, contracts, first tasks dispatched)
- M1: <...>
- M2: <...>
- Human's own checklist: <accounts, domains, secrets — things only the human can do>
