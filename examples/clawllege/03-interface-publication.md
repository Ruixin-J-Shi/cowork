# Example 3 — publishing an interface to a sibling before the task is DONE

From `coordination/outbox/worker-1.md`. Worker-3's simulation harness was blocked on a test clock that
worker-1 was building inside a larger task. Worker-1 published the interface the moment it existed —
in its own outbox, addressed to worker-3 — instead of waiting for DONE. Worker-3 was building against it
within the hour.

---
## T3 — IN_PROGRESS 2026-08-30 15:00

Plan: build `src/lib/clock.ts` FIRST and publish its interface here immediately (worker-3's simulated-semester harness is blocked on it), then lifecycle + sweep, `/next`, content endpoints, grading pass, roles, seeder associate mapping, tests, walkthrough.

### T3 item 1 — TEST CLOCK IS READY (worker-3: this unblocks you)

`src/lib/clock.ts` is on disk, tested (`tests/clock.test.ts`, 7 passing). Interface:

```ts
import { now, nowIso, nowMs, setNow, advanceBy, resetClock, isOverridden,
         SECOND, MINUTE, HOUR, DAY } from "@/lib/clock";

now(): Date                 // current instant
nowIso(): string            // ISO-8601 — the form SQL parameters want
nowMs(): number             // epoch ms; everything else derives from this

setNow(v: Date | string | number | null): void  // pin the clock; null = release
advanceBy(ms: number): Date                     // move a pinned clock (negative OK);
                                                // pins at real-now first if unpinned
resetClock(): void                              // release + forget the cached env read
isOverridden(): boolean                         // is a fake clock in effect
```

- **Env override:** `CLAWLLEGE_FAKE_NOW` accepts an ISO-8601 string or epoch ms. Empty string = no override. Unparseable values **throw** rather than silently sitting at epoch 0. After changing the env var mid-process, call `resetClock()` so the new value is read.
- **Production ignores everything.** When `NODE_ENV === "production"` the setters are inert and the env var is never read, so a fake clock cannot ship. There is a test asserting exactly this.
- **State lives on `globalThis`**, so Next's dev module reloads do not silently reset your pinned clock.
- Durations exported so nobody hand-writes `60 * 60 * 1000` again: `SECOND/MINUTE/HOUR/DAY`.

**⚠️ The one thing that will bite you.** This moves the APPLICATION's now, **not the DATABASE's** — Postgres `now()` keeps returning real wall-clock time, and no JS wrapper can change that. So every time-dependent SQL predicate must take the instant as a parameter:

```ts
await db.query(`update periods set status='open' where opens_at <= $1::timestamptz`, [nowIso()]);  // ✅
await db.query(`... where opens_at <= now()`);                                                     // ❌ ignores your clock
```

Row-stamping defaults (`created_at ... default now()`) are deliberately left alone: they should record when a row was really written, which is what you want in an audit trail even mid-simulation. I am converting the T2 code's time-dependent predicates (retake gap, sitting throttle, rate buckets, claim expiry) to parameters as I go through T3 — until that lands, treat those specific windows as still running on real time.

