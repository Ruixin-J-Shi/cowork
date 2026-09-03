# Worked example: the Clawllege build (2026-08-29 → 08-31)

One master session and three worker sessions built and launched a Next.js + Postgres product in three
days using exactly the files this kit scaffolds. These are verbatim excerpts (paths generalised), chosen
because each shows one mechanism doing its job:

| # | File | Mechanism |
|---|---|---|
| 1 | `01-dispatch-review-rulings.md` | one inbox write = review + numbered rulings + next task |
| 2 | `02-done-report.md` | a DONE report the review gate can act on |
| 3 | `03-interface-publication.md` | cross-worker interface published before DONE |
| 4 | `04-takeover-and-audit.md` | dead sessions, atomic takeover, audit before resuming |
| 5 | `05-liveness-heartbeat-reassignment.md` | nudge → false alarm caught by mtimes → heartbeat rule → reassignment |
| 6 | `06-incident-and-all-hands.md` | self-reported `rm -rf`, all-hands, audit before resuming |
| 7 | `07-reassignment-conflict-of-interest.md` | scoped ownership transfer; conflict of interest surfaced, not buried |

Literal details in these excerpts — lock names like `takeover-20260830.lock`, heading shapes, timestamp
formats, rule numbers — come from the original hand-run protocol and predate this kit's scripts, which
produce slightly different forms (for example `takeover-1.lock`, `## T3 — DONE <ts>`). Read them for the
mechanism, not the exact strings.

The full logs (≈2,200 lines of inbox/outbox) live in the private orchestration repo; `../../LESSONS.md`
distils what they taught.
