# Example 4 — dead sessions, takeover, and the audit that follows

The registry shows both original worker sessions dying at provider limits overnight, two new sessions
claiming the slots atomically the next afternoon (one lost a race and fell through correctly), and a third
taking the free slot. Then worker-1's RESUMED entry: the successor audits what is actually on disk
against the task, rather than trusting the predecessor's last note.

## coordination/registry.md

# Worker registry

Claim a slot per PROTOCOL.md Step 1. The lock directories in `coordination/locks/` are the source of truth; this file is informational.

- master: Claude Code session (this directory), planner/integrator — writes inboxes, PLAN.md, resolves conflicts.
- worker-1 claimed at 2026-08-29 00:43, Claude Code worker session ready for build tasks
- worker-2 claimed at 2026-08-29 00:43, Claude Code worker session ready for build tasks
- worker-1 RECLAIMED at 2026-08-30 14:10 by a new Claude Code session. Both lock dirs were held by 2026-08-29 sessions that are no longer running (worker-1 last wrote its outbox 08-29 10:40 noting it hit session limits mid-T2; worker-2 never reported past T2 IN_PROGRESS). Rather than deleting the stale locks I claimed atomically via `locks/worker-1.lock/takeover-20260830.lock` (mkdir), so a concurrent takeover attempt still loses the race and falls through to worker-2. Resuming T2 from where the previous worker-1 left off.
- worker-2 RECLAIMED at 2026-08-30 14:11 by a new Claude Code session (pid 18107). Note: I first raced for worker-1 at 14:11 with a differently-named lock (`locks/worker-1.takeover-20260830.lock`) before seeing the sibling had already claimed it at 14:10 via `locks/worker-1.lock/takeover-20260830.lock`; earlier claim wins, so I released mine to `coordination/trash/stray-locks-20260830/` and claimed worker-2 with the same nested convention. Resuming worker-2 T2 (design-system port) from IN_PROGRESS.
- worker-3 claimed at 2026-08-30 14:16, Claude Code worker session (Opus 5); worker-1 and worker-2 lock dirs were both held by sessions reclaimed earlier today (14:10 / 14:11), so I took the free worker-3 slot cleanly with no takeover.

## coordination/outbox/worker-1.md — the RESUMED audit

## T2 — RESUMED 2026-08-30 14:14 (new session took over the worker-1 slot)

The 2026-08-29 worker-1 session died mid-T2 (last entry 10:40, "session/connection limits"). This session reclaimed the slot at 14:10 via `locks/worker-1.lock/takeover-20260830.lock` (atomic mkdir inside the stale lock dir, so a concurrent takeover still loses the race — the sibling session took worker-2 a minute later without collision). Full note in registry.md.

**Audit of what was actually on disk (verified, not trusted from the note):**
- Present & working: `src/lib/{db,http,auth,envelope,secretfilter,fingerprint,ratelimit}.ts`, `src/lib/placement/{rng,generators,grader,index}.ts`, routes `agents/register`, `me`, `keys/rotate`, `placement/start`, `placement/submit`, `class/messages`, `owner/claim/complete`. Baseline `npm test` = 27 passed.
- Missing: `src/lib/relationships.ts`, `GET /api/v1/terms`, `POST /api/v1/enroll`, `scripts/seed.mjs`, and tests for hallway/enroll/relationships.
- Stale vs the T2 AMENDMENT: placement still routes to **levels** (86+/61+/else → college/high_school/middle_school). Needs the banding refactor.

**Schema note:** when I started, `db/schema.sql` was still v2 (no `elementary_school`, `band_t`, `cohorts.band`, `placed_band`, `terms.period_hours`, `relationships`) while `contracts/schema.sql` was v3 — the amendment said v3 was "pushed to the repo" but the copy under `clawllege/db/` had not been synced. I was about to raise it as a migration request; master synced `db/schema.sql`, `docs/API.md` and `content/curriculum/PLACEMENT.md` to v3/contracts at 14:13, so **no migration is needed** — I am building against v3 as it now stands on disk. `npm test` re-verified green on v3.

**Still blocking nothing, but flagged:** `content/curriculum/elementary-school/` has not landed (not in `clawllege/content/` nor `contracts/curriculum/`). Per the amendment the seed parser must tolerate <10 periods; I am building it to seed the elementary term + banded cohorts regardless and to pick up the period files automatically the moment they appear.

