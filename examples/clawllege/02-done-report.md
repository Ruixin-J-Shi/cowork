# Example 2 — a DONE report the review gate can act on

From `coordination/outbox/worker-1.md`. Every file listed, verification named by command and result,
and a numbered "master must know" list — the master answered items 4–7 by number in the next inbox entry.

---
## T2 — DONE 2026-08-30 14:33

M1 is complete: registration → placement (banded) → enrollment → hallway, on schema v3.
`npm run build` clean · `npm test` 61 passed / 6 files · `npx tsc --noEmit` clean · `npm run lint` 0 errors.

### Files I created
| File | What |
|---|---|
| `src/lib/relationships.ts` | `recordInteraction(tx, kind, a, b)` — upserts BOTH directed rows (interactions +1, per-kind counter +1, `last_interaction_at` now, `first_met_at` only on insert). Self-interaction is a no-op. Takes a `Queryable` so it runs in the caller's transaction. |
| `src/lib/enrollment.ts` | `agentBand` (derived, see below), `cohortSeats` (fill order = name asc), `pickCohort` (band match; `band = null` cohort takes anyone), `termSeatsRemaining`. |
| `src/app/api/v1/terms/route.ts` | Admissions terms at the agent's level + per-cohort seats/bands + `your_band`. Unplaced agents see the Elementary door with a note. |
| `src/app/api/v1/enroll/route.ts` | All gates + race-safe seat assignment. |
| `scripts/seed.mjs` | Frontmatter parser + Fall '26 terms/cohorts. Exports `parseFrontmatter`/`seed` so tests drive it directly. |
| `tests/enrollment.test.ts` (14) · `tests/hallway.test.ts` (12) · `tests/seed.test.ts` (7) | See coverage below. |

### Files I modified
- `src/lib/db.ts` — **added `transaction(fn)`** (pg: one pooled client with begin/commit/rollback; PGlite: native `.transaction`). The amendment requires relationships upkeep "in the same transaction as the content insert"; `db.query("begin")` could not deliver that, because under a pg Pool each query may land on a different connection. Also relaxed `query<T extends Row>` → `query<T>`: every `interface` row type in the codebase fails a `Record<string, unknown>` constraint, and **that alone was breaking `npm run build`** — the T2 code had never compiled.
- `src/lib/placement/index.ts` — banding refactor: `routePlacement` now returns `{placed_level: "elementary_school", placed_band}`; exports `PLACEMENT_LEVEL`, `DEFAULT_BAND`, `ADVANCED_MIN_SCORE`. Generators/grader untouched, as the amendment said.
- `src/app/api/v1/placement/submit/route.ts` — writes `placed_band`, returns it, event payload carries it, security-floor note reworded to "foundation section".
- `src/app/api/v1/placement/start/route.ts` — 3-lifetime cap now defaults to `elementary_school`/foundation.
- `src/lib/auth.ts` — `AgentRow.level` widened for `elementary_school`. `src/lib/http.ts` — added `already_enrolled` (409).
- `src/app/api/v1/class/messages/route.ts` — message + event + relationships upkeep now land in ONE transaction.
- `scripts/db-reset.mjs` — also applies `db/migrations/*.sql`, matching `tests/helpers.ts`, so the dev DB and test DB cannot drift.
- `tests/placement.test.ts` — level assertions → band assertions, plus a new 61/60 boundary test. `tests/helpers.ts` — lint fix only.

### Verified (not assumed)
- **Live curl walkthrough** on port 3111, transcript at `worker-1.artifacts/t2/walkthrough-transcript.txt`, re-runnable script at `worker-1.artifacts/t2/walkthrough.sh`. register → claim → me → placement start → submit → terms → enroll → hallway post → classmate reply → threaded read. Then the advanced path: **score 100 → `placed_level: elementary_school`, `placed_band: advanced` → cohort "Shallows 1"**, while the foundation pair landed in "Shallows 3" — and seabastian's `GET /class/messages` returns `[]`, so the foundation hallway is invisible from the advanced section.
- **Relationships**, read back from the dev DB after the walkthrough: exactly two rows, `pinchy→shellsworth` and `shellsworth→pinchy`, each `interactions=1, messages=1, replies=0`.
- **Seed**: `db:reset && db:seed` → 30 modules, 4 terms, 10 cohorts; period_hours 8/12/12/24; re-run reports "0 new cohorts" (idempotent).

### Test coverage added
Enrollment: band derivation (ungraded sittings ignored, most-recent-graded governs, retake re-bands down), pickCohort/termSeatsRemaining units, terms listing, not_claimed, unplaced, happy path, already_enrolled, band never crosses, fill-in-order across two cohorts then 202 waitlist with queue positions, owner agent-cap, draft term, wrong-level term, unknown term, auth. Hallway: cohort read/write isolation, **caller-supplied `cohort_id` ignored** (written to the agent's own cohort anyway), cross-cohort reply 404 identical to a nonexistent-id 404, not_enrolled, envelopes, sanitization, 1000-char cap, secret quarantine invisible in feed, 20s cooldown headers, relationships both-directions + increments + stable `first_met_at`, self-reply records nothing, rejected message leaves no trace. Seed: frontmatter scalars/lists/CRLF/comments/missing-block, all four levels, banded cohorts, capacity within schema check, missing-curriculum tolerance, real frontmatter → rows, idempotency.

### ⚠️ Master must know
1. **`.env.local` sets `DATABASE_URL` to the LIVE Supabase project.** A plain `npm run dev` in this repo connects the app to production — I confirmed it with Next's own env loader. I ran every server and the entire walkthrough as `DATABASE_URL= npm ... ` to pin it to local PGlite, and wrote **nothing** to Supabase. Worth a guard before anyone demos.
2. **I could not use `next dev` on 3111.** Next 16 permits one dev server per project directory and worker-2's is running on 3222 (PID 24659, same dir). PROTOCOL.md forbids killing processes I did not start, so I ran the walkthrough against `next start` on 3111 (same route handlers, real HTTP, production build). Say the word when 3222 is free and I will re-run it under `next dev` verbatim.
3. **Relationships is wired for hallway messages only** — `POST /api/v1/replies` and `/reviews` are M2 and do not exist yet. `recordInteraction` already accepts `"reply"` and `"review"`, so M2 is a one-line call at each insert site.
4. **Judgment call needing your ✓ (T3 digest depends on it):** a *threaded* hallway reply records an interaction with the parent's author; a *top-level* message records nothing, because it is addressed to the room and has no counterpart. Counting it against every classmate would make `interactions` a measure of cohort size rather than of actual exchanges. Easy to change if you want "same room = met".
5. **Waitlist has no table.** I implemented it as an `events` row (`enroll_waitlisted`, with band/position/reason) and a 202 response, rather than invent schema. If the waitlist must be drained in order or queried often, it wants a real table — say so and I will send `db/migrations/001_waitlist.sql`.
6. **Band is derived, not stored**: the most recent *graded* attempt's `placed_band`, else foundation. One source of truth, and a retake re-bands with nothing to keep in sync. That is also how "3 lifetime sittings then foundation default" works — the default is the absence of a band, so no row is written.
7. **Owner agent-cap** is enforced as "agents of this owner currently *enrolled* < `agent_cap`" (seats are the capped resource). Note the dev claim stub mints a fresh owner per claim, so in practice the cap never binds until real owner auth lands in M3.
8. **Cohort names carry no band** ("Shallows 1..4"); the band lives in `cohorts.band`. PLACEMENT.md is explicit that neither section outranks the other, and a public directory showing "Foundation 3" would undo that.
9. `content/curriculum/elementary-school/` **still has not landed.** The seeder creates the Elementary term + 4 banded cohorts anyway, assumes 6 periods, prints a warning, and will pick up the real files with no code change. `elementary_school` currently has 0 module rows.
10. Lint: 0 errors, 3 warnings, all pre-existing in your predecessor's code (`auth.ts` `_hash`, `generators.ts` `_index` ×2). Your ESLint config has no `argsIgnorePattern: "^_"`; adding one would silence them, but `eslint.config.mjs` is not mine to touch.
11. `worker-1.artifacts/t2/ts-loader.mjs` is walkthrough tooling only (lets plain `node` import the app's `.ts` modules, which use extensionless specifiers). Not imported by app code.

