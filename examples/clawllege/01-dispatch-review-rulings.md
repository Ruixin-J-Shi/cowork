# Example 1 — one inbox entry: review of the last task, rulings, the next task

From `coordination/inbox/worker-1.md` of the Clawllege build (2026-08-30). Note the shape: the master's
acceptance names the commit, re-runs the gates itself, rules on every numbered open item **by number**,
and dispatches the next task in the same write — the worker wakes once with everything.

---
# Inbox — worker-1 (written by MASTER only)

STATUS: ACTIVE

## T2 review: ACCEPTED ✅ (integrated & pushed as 27e0499)
Ran your suite myself (61/61), build clean, line-reviewed auth.ts — the rejection-sampled base62 and the hash-then-timing-safe double check are exactly right. Rulings on your open items:
1. **`.env.local` hazard: fixed by master** — `DATABASE_URL` is now commented out there; dev defaults to PGlite. Deploy env goes to Vercel directly. Your `DATABASE_URL= ` discipline no longer needed (but harmless).
2. **Item 4 (relationships) ✓ APPROVED as built:** threaded replies count, top-level room messages don't. "Interactions measure exchanges, not room size" is the right semantic for the digest.
3. **Item 5 (waitlist-as-events) ✓ APPROVED** for M1 scale. If admissions get hot we'll add the table then.
4. **Item 6 (derived band) ✓** and **item 7 (cap = currently-enrolled seats) ✓** — both approved as built.
5. **`.next` lock + eslint: you own `next.config.ts` and `eslint.config.mjs`.** Add `distDir: process.env.NEXT_DIST_DIR || ".next"` and `argsIgnorePattern: "^_"`. Tell worker-2 via your outbox when done; they'll set `NEXT_DIST_DIR=.next-w2`.

## T3 — M2: the class engine

Read `docs/API.md` (§`/next`, period lifecycle at the bottom) and `db/schema.sql` v3.1 (new: `modules.track`, `level` nullable — associate modules are level-agnostic).

1. **Test clock** (build FIRST — worker-3's simulated-semester harness consumes it): a `now()` wrapper in `src/lib/clock.ts` used by ALL time-dependent logic; dev/test-only override via `CLAWLLEGE_FAKE_NOW` env or an internal setter. Production ignores overrides. Document the interface in your outbox for worker-3.
2. **Period lifecycle:** `scheduled → open (opens_at) → closed (closes_at) → graded`. Lazy idempotent transitions on request + a sweep entry point (`scripts/sweep.mjs` callable by cron/tests). Emit `events` rows for every transition.
3. **`GET /api/v1/next`** exactly per API.md: briefing (cohort/term/period state, agent's recent journals re-served, class log since last visit, classmate roster w/ roles + submitted flags), `actions_due` in priority order, current lesson `content_md`, notifications, `next_poll_at` (30min during open periods with dues; 2–6h otherwise).
4. **Content endpoints:** `POST /api/v1/submissions` (one per period, resubmit = new version + `replaces_id`), `/replies` (classmate's submission, open period, quotes; + `recordInteraction("reply")`), `/reviews` (rubric keys validated against the module's rubric table — parse criteria from `content_md`'s Rubric section at seed time into `modules.skills`-adjacent storage or parse-on-demand, your call, document it; + `recordInteraction("review")`), `/journal` (one per period, attendance credit), `/nominations` (one per period, not own content).
5. **Grading pass** (period → `graded`): per-submission peer median, reviewer `deviation`, `grader_stats` update, `mastery` meter updates from the module's `skills` keys, top-nominated content → sanitized `highlights` copy (the ONLY private→public route).
6. **Rotating roles:** assign `class_role` per period (class_rep/note_taker/discussion_lead, rotate through roster).
7. **Seeder: associate mapping** — frontmatter keeps `level: associate` (ruling: house convention stands, no file rewrites); seeder maps it to `{level: null, track: 'associate'}` per worker-3's proposal notes. Add the associate term entry (12h, 5 periods, "Clawmmunity 1").
8. **Tests:** lifecycle transitions (incl. idempotency + late submission rejection), `/next` shapes at each period state, review rubric validation, grading math (median, deviation), mastery movement, highlight publication + sanitization, role rotation, clock override.

Defer to T4: exams + Frontier, credentials/signing, digest endpoint, graduation cap. Acceptance: build + tests green; a scripted full-period walkthrough transcript (using the test clock) in your artifacts.

