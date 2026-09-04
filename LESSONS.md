# Lessons from the first run

*Vocabulary note.* The original run and these lessons say **master** and **worker**. The kit now says
**lead** (the role of directing a team), **seat** (`seat-N`, a slot in a team and the node holding it),
**node** (any session; it holds a seat above and may lead a team below), **root** and **leaf**. File and
script names below use the new names; the narrative keeps the words the run was written in.

The protocol in this kit was not designed on paper. It was written the night before a build, then
amended by incident over three days (2026-08-29 → 08-31) while one master session and three worker
sessions built and launched a real product: a Next.js + Postgres platform with 30 API routes, 229 unit
tests, a full simulated-semester harness (1,100+ end-to-end assertions), a brand, and a deploy. The
sessions died three times. Every rule below has a scar behind it; `examples/` holds the verbatim
passages. The master's own notes are quoted where the wording is worth keeping.

## 1. Death is normal — design for takeover, never for uptime

Both original workers died overnight at provider limits, mid-task, with unreported work on disk. The
recovery that worked: a new session tried the slots in order, found every lock held, judged one dead by
its outbox (an unfinished task, no activity for hours), and claimed it with a **nested atomic `mkdir`
inside the stale lock** — so a concurrent taker still lost the race and fell through to the next slot
(which is exactly what happened a minute later). Then it **audited what was actually on disk** against
the task's acceptance criteria before continuing: the predecessor's note said four subsystems were done;
three were, one had never compiled.

Rules: locks are never deleted (`claim.sh --takeover`); the successor announces in the outbox at once
(so the slot reads ALIVE to everyone else) and writes `T<id> — RESUMED` with what it found; "verify,
never assume" applies to a predecessor's work exactly as to your own.

## 2. Liveness needs evidence — the heartbeat rule

A worker went quiet for 65 minutes mid-task. The master's status check went unanswered. The human was
about to relaunch the session. A worker on standby checked file mtimes and found five files written in
the last three minutes in exactly the area the quiet worker had said it was starting on: **heads-down,
not dead**. A relaunch would have destroyed ~100 minutes of unreported work mid-edit.

That worker proposed the rule the kit now carries: *"a worker with no outbox entry for ~30 minutes
appends a one-line heartbeat — cheap, and it makes 'unresponsive' mean something checkable."* And the
master's standard for the other direction — **dead by the evidence standard** — is three facts together:
outbox stale past the window, territory silent, open task unacknowledged. `status.sh` computes all
three; `claim.sh --takeover` refuses a slot that fails any of them.

Nudge wording that worked: *"No outbox entry or territory activity for N min while T<id> is in progress.
One line if alive; if blocked, on what; if your session died, the takeover protocol covers the successor."*

The mirror case turned up in the kit's own dry run: an aggregate "territory active" number said alive while
the slot was dead, because a busy sibling's writes were counted. The verdict string is a summary; the
standard is the three facts about *that slot* — its own outbox, its own territory, its own open task. Both
agents in that run judged on the facts and ignored the string, which is why the takeover happened at all.

## 3. Read the inbox between increments, not only at wake-ups

An all-hands landed in a worker's inbox at 18:15. At 18:22 that worker ran the very command the
all-hands forbade. The warning had been sitting unread, because the worker only read its inbox when
`watch.sh` fired and it was mid-task. Its own post-incident change — *"I now re-read my inbox between
increments of a long task, not only at watch boundaries"* — is Step 2.5 of the protocol.

## 4. `rm` discipline — an incident, an escalation, an amendment

A worker tidied its own scratch snapshots inside `coordination/trash/` with `rm -rf`. Nothing outside
the trash was touched; the worker self-reported. The human escalated it as a serious deviation anyway,
and was right to: *"This was harmless only because the OS refused the path. The habit is the hazard."*
When the all-hands went out, all three workers audited their own histories and each found and reported
its own occurrences — one of them five, some predating the rule. The master's ruling on that: *"an audit
that finds nothing in your own history is usually an audit that did not look"*, and *"it only keeps
happening if reporting stays cheaper than hiding."*
The worker's own post-mortem named the failure shape: *"trash is the trash, and these are my own
regenerable files, so deleting them is tidying" — that is exactly the shape of rationalisation the rule
exists to stop: the rule is absolute precisely so it does not depend on my judgement of what is safe.*

The amended rule (verbatim in PROTOCOL.md): `rm -rf` never in ad-hoc shell for any path; deletion is
`mv` to trash; destructive ops only in checked-in scripts with hardcoded project-relative paths; any
slip — refused or not — is an incident line, then stop and audit before resuming. The follow-up audit
found a real hazard elsewhere: a db-reset script that honoured an env var for its data directory could
be pointed outside the project. The fix — *"an env-driven destructive op must be unable to leave its own
project"* — is the standard for sanctioned scripts.

Culture note the master wrote back: self-reporting is *"exactly the culture"*; a worker that puts its
own slips in the record next to another's is doing the job. One scoped refinement followed: disposable
run output (simulation reports, database snapshots) is never deleted at all, not even into trash — each
run writes its own timestamped directory under a gitignored path and the master prunes at milestones.
Trash is for files with recovery value; 58 MB of regenerable bytes would make it useless for that.

## 5. Ownership, not worktrees — and what collided anyway

No git worktrees; conflicts were avoided by assigning directories. It held. What still collided were
**shared resources nobody had partitioned**: one framework allowed one dev server per project directory,
so two workers' builds fought over a lock; two dev servers wanted the same port; two workers wrote the
same env file. Each cost a round trip through the master to assign an owner. Put the partition in
`PLAN.md` before the first task: ports, build output dirs, databases, env files — one per worker, named.

A worker that needs a file it does not own reports BLOCKED naming the file. The master answers with an
explicit, scoped grant ("you own `next.config.ts` and `eslint.config.mjs`; add X; tell seat-2 via
your outbox when done"). Unscoped "just fix it" grants are how territories blur.

## 6. The review gate, and three ways it lied

Every DONE went through the master: re-run tests/build/typecheck, read the diff, rule on open items,
integrate, push, write `ACCEPTED ✅ (pushed as <sha>)`. Three failures of the gate itself became
conventions:
- The master committed a worker's in-flight work with type errors by running `git add -A` while another
  task was mid-flight. **Stage explicit paths from the DONE report; never `-A` while anyone is working.**
- A gate piped through `grep` reported grep's exit code, not the build's. **Run gates bare.**
- The shared tree's WIP masked a failure the commit did not have. **Release verification happens in a
  clean checkout.**

## 7. Rulings by number

Workers ended DONE reports with a numbered list of judgment calls ("Item 4: threaded replies record an
interaction, top-level messages do not, because …; easy to change"). The master answered each by number:
✓ approved as built, ✗ do this instead, or *"neither option — here is the third"*. Unanswered items were
re-raised by the worker, politely, until answered. This is the cheapest decision loop the run found:
one write each way, no meeting, full record.

Corrections flowed upward too. A worker corrected the master's "one subsystem still on real time" with a
list of four; the master's reply — *"flagging my inaccuracies is part of the job"* — is in the protocol's
reporting standard.

Two dispatch habits cost real time. A ruling folded into the paragraph of another task's dispatch was
read past twice and needed three reminders: one ruling per heading. And when the master refactored a
file a worker was mid-patch on without saying so, the worker's patch silently no-op'd while the tests
stayed green; a `grep` for the symbol caught it. If you touch a file in someone's territory, tell them,
naming the file.

## 8. Publish interfaces early; talk on the record

Worker-3's harness was blocked on a test clock seat-1 was building inside a larger task. Worker-1
published the interface in its outbox the moment the file existed — signature, env var, the one trap
("this moves the application's now, not the database's") — addressed `seat-3:`. Worker-3 was building
against it within the hour, days before the enclosing task closed. Workers read every outbox at each
wake-up; a `📎 seat-N:` heading is a direct line that the master also sees.

The master also relayed GO signals across lanes ("seat-1's T4 is merged: endpoints X, Y, Z — flip to
live") so a worker never had to guess whether a dependency had landed.

## 9. Conditional contingencies and scoped transfers

When a lane looked dead, the master pre-announced a conditional transfer to a live worker: *"IF a
relaunch has not appeared by the time you next check in, ownership of `<dir>` (ONLY that) transfers to
you; announce in your outbox if you invoke this."* It cost one line, needed no further round trip, and
the worker declined to invoke it when the mtimes said the lane was alive (lesson 2). When two lanes were
dead by the evidence standard the next day, the transfer was explicit and scoped (*"you may modify
`src/lib/**`, `src/app/api/**`, `tests/**` for T8 ONLY"*) with the review gate named as the control.

## 10. Conflict of interest in the open; baseline before fix

The reassigned worker had written the findings, was now writing the fix, and ran the acceptance gate.
Its first act was to put the tension on the record: its pre-registered gate assertion assumed one
reading of the spec; the brief implied another; it could have implemented whichever made its own gate
green. It named both readings, chose one, and asked to be overruled if wrong. The master ruled; the
gate stayed as written; the fix landed with a regression it caught itself.

The mechanics that made this safe: the **baseline was recorded and committed before the fix** (1081 /
19 / 2, with the exact expected delta) and never edited after. Convention: *when a fix is measured by a
delta, record the baseline first.*

## 11. Documents drift — the heartbeat rule never reached PROTOCOL.md

The master told seat-1 its heartbeat rule was "adopted verbatim" into PROTOCOL.md; the worker thanked
it; the committed PROTOCOL.md never contained it. Nothing broke — every session had read the rule in its
inbox — but a successor booting from the file alone would have missed it. This kit's PROTOCOL.md carries
the heartbeat rule, the inbox re-read rule, the takeover announcement and the sibling-notes convention
in the file, where a fresh session finds them. When a rule is adopted, the master's dispatch should quote
the line it added and the file it added it to.

## 12. The human's three jobs

The human never wrote to a worker. They: relaunched dead sessions (the successor claims by takeover);
held every account and secret (the signing key was the one irreplaceable value; it travelled by hand,
never by repo); and escalated (the `rm` incident, brand verdicts) — always *"from the human via master"*,
so workers had one source of instruction. Assets the human supplied were placed by the master into a
master-owned directory and pointed at.

## 13. Cost discipline

The master ran on the strongest, most expensive model; workers on a cheaper tier. The human's directive
(day two): the master **specs, reviews and integrates**, delegates token-heavy implementation and
content to workers, and intervenes only when unsatisfied with worker output. The review gate is where
the expensive model earns its keep; a master that implements is a master that is not reviewing.

## 14. Restarting on another machine

Session memory does not travel; the repo does. Clone; `coordination/locks/` is empty on a fresh clone so
claims are clean; the new master reads the plan, the protocol, the tails of every outbox, writes a fresh
`STATUS: ACTIVE` and a state-of-the-world note into each inbox (a booting worker diffs inbox against
outbox and would otherwise idle on stale history), then arms the monitor. Secrets are carried by hand.
Dev-server ports and build dirs per worker are written down where the next machine can read them.

## 15. Engineering conventions that fell out of the run

Not protocol, but they were learned through it and the kit seeds them into `CONVENTIONS.md`:
- **A fixture must never do the work the product is supposed to do.** A launch blocker (a scheduler with
  no production caller) survived 192 green tests because every fixture scheduled the periods itself.
- **A check that cannot fail is not a check.** A `.catch()`-wrapped assertion queried a nonexistent table
  and "passed" for a whole phase. Name checks by what is measured, not by the story.
- **A regression test must be shown to fail against the unfixed code.** The first version of a panel
  test passed against the broken query because an unrelated exclusion masked it.
- **Integrity rules are asserted over the full population of decisions**, not the subset a test drove.
  An intermittent violation coexisted with green runs until the gate read every recorded decision.
- **A missing import that every static check passed** only threw when the branch ran. Pre-flight: import
  the module and confirm it loads.

## 16. What the kit's own dry runs taught (2026-09-01)

Before shipping, this kit was run for real twice in scratch projects: a master session and two worker
sessions building a trivial CLI, then a second run with a worker scripted to die mid-task, a task that
forced a BLOCKED on an unowned file, and a late successor that had to take over by evidence. Every
finding below changed the kit.

- **The watch had a race.** A dispatch landing between a worker's inbox read and its `watch.sh` arm
  was invisible until the timeout — up to ten minutes at the shipped default, and aimed at the busiest
  moment in the loop (right after DONE). Both workers hit it in their first cycle. `inbox.sh` now records
  the version read, and `watch.sh` fires immediately if the inbox is already newer.
- **An in-place edit in an append-only file is invisible to `tail`.** The `STATUS:` line is the one field
  the master rewrites, and it is the one that ends a session; a worker polling with `tail` missed its
  dismissal for five minutes. `--status` now also appends a dated entry, and the protocol says read the
  whole file.
- **A fast death leaves no record.** A heartbeat window measured from `IN_PROGRESS` let a worker do 32
  seconds of half-work and vanish with an interface decided but unpublished and a file that ran clean
  while silently ignoring half its flags. Heartbeats now carry item-by-item state and start after the
  first finished item; interface publication moved into the work loop; the takeover audit runs each
  acceptance item rather than reading the plan.
- **Idle workers drift.** A worker with nothing assigned started an investigation, stopped watching its
  inbox, and had its `rm` incident inside that unscoped work — the same rationalisation as the original
  run, reproduced verbatim ("my own regenerable file, so deleting it is tidying"). Idle now means blocked
  on the watch; anything else is proposed in one line and waits for a task.
- **`rm -rf` is not the rule; `rm` is.** Two independent workers read the emphasised `rm -rf` as implying
  a single-file `rm -f` was a lesser thing. The rule now names every form, and steers toward commands
  that leave nothing to clean up (`sed 'expr' in > out`, never `sed -i.bak`).
- **A `die` inside `$(...)` cannot abort the caller.** `dispatch.sh --help` created a stray inbox file
  because the id validation died in a subshell and the script carried on with an empty name. Every
  substitution of a validating function is now guarded, and every script answers `--help` harmlessly.
- **A busy sibling can hide a dead worker** when liveness looks at all territories at once. Per-slot
  territories (`TERRITORY_N` in `cowork.conf`) make the death evidence per worker.
- **Number every clause.** Two workers reading the same task block disagreed about what "item 2" meant
  because ownership and acceptance paragraphs were unnumbered.
- **BLOCKED is not closed.** A worker waiting on a sibling's file showed as idle, lost its heartbeat duty,
  and had no rule for what to do when the blocker cleared. A task's state is now its last outbox heading;
  only DONE closes it; a cleared blocker closes under the same id.
- **Entries cross in flight.** Twice the master asked for a DONE that had landed seconds earlier. The
  master re-reads the outbox tail before asking; the worker points at the entry and re-verifies live.
- **An acceptance criterion a sibling's lane must satisfy guarantees a BLOCKED.** Scope acceptance to the
  worker's own territory, or say that BLOCKED is the expected outcome until the dependency lands.

## 17. Making it recursive (2026-09-01)

The question "can a master also be a worker?" has a clean answer once the unit is the **node**: one
session that is `seat-N` of the team above and the master of the team below, positioned entirely by
its directory (`<parent>/teams/seat-N/`). Depth becomes a parameter (`--layers 3,2`), and the same two
files and scripts apply at every level. What the first live tree (top master, one node, one leaf) and
the review of the model taught:

- **The node needs both seen-markers.** A node's first watch baselined the inbox above at arm time and
  swallowed a dispatch that had landed during boot — the same race the workers had, one level up. Boot
  now reads the inbox above (recording it as seen); the below side persists the outbox snapshot the
  master last woke on, so a change pre-empted by the other side's exit is caught on the next call. The
  plain `lead-watch.sh` had the same hole and got the same fix.
- **Only the top runs git, and every document must say so at the point of temptation.** The review gate's
  "commit, push" step was unqualified and is read verbatim by every node. A node's DONE upward is an
  integration request; the top integrates one working tree.
- **Dismiss leaves last, pause before integrating.** A node that dismissed its worker before sending the
  integration request had removed the implementer exactly when rework might come back. Workers are
  `PAUSED` while the review above runs and dismissed only after ACCEPTED; a node dismissed from above
  winds its team down first and reads their summaries.
- **Names collide across sibling teams.** Every team has a `seat-1` and a `seat-1.artifacts/`; a bare
  basename in a dispatch pointed the leaf at its master's artifacts dir in the team above. Paths in
  entries are `$ROOT`-relative and complete.
- **The harness's scratch directory is outside the project.** Two sessions in the same run wrote throwaway
  probes to `/tmp` or a harness-nominated scratchpad because their system prompt told them to. Hard Rule 1
  now names the destination (the artifacts dir) and says it outranks the harness.
- **Verify under the shell you ship for.** A zsh tool shell does not word-split `$var` and names
  `PIPESTATUS` differently; a check typed at the prompt manufactured a "regression" that `bash script.sh`
  did not have.
- **Replacement is one command, in one order.** A dead node is replaced by `node.sh boot --takeover`,
  which takes the slot above first and the master lock below second, so the record above shows who took
  the slot before the team below sees a new master. Nested teams get `node-standby.md` and
  `node-resume.md`; the generic master prompts would have reclaimed only one side.
- **The master's log collided with the master's playbook.** The log was `master.md`; on macOS's
  case-insensitive filesystem that *is* `LEAD.md`, so every heartbeat was appended to the document every
  successor reads as instructions. It is `lead-log.md` now. Name runtime files so they cannot be confused
  with documents on any filesystem.
- **A node's liveness has two answers.** Blocked on a review above, a node that had just written a
  4,000-word integration request read as `DEAD?` below, because its team judged it only by the team's own
  log. Upward writes now count as the master being alive, and a finished team waiting on the review above no
  longer trips the stall alarm.
- **Scope every layer's territories.** A nested team's `TERRITORIES=` starts as a copy of its parent's;
  left that way, a sibling's writes silence the node's stall alarm. `doctor.sh` warns while it is identical.

## The one-page mental model (the master's own words, kept)

*The support repo is the brain (protocol, plan, logs), the product repo is the body (deployed by push),
the secrets file is the blood (carried by hand), and the sessions are staff you can hire, lose, and rehire
at any time — the takeover rules assume death is normal. Nothing about the system lives only in one
machine or one conversation.*
